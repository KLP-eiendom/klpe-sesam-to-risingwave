# Leverandørflyt mot Dalux FM (RisingWave → Dalux)

Issue [#22](#22), under
story #21. Gjelder skriveretningen; leseretningen (`dalux-entity-poller` →
`stg_dalux_leverandor`) er uendret.

## Eierskap

```
SuperOffice ─┐
             ├─► mrt_global_leverandorvurdering ─┐
Bisnode ─────┤     (vurdering + lokasjon +       │
D365 ────────┘      evalueringskommentar)        ├─► mrt_leverandor_dalux_writeback ─┐
                                                 │        (ønsket tilstand)          │
D365-staging (gate, postnr, tlf, engangslev.) ───┤                                   │
seed: dalux_klassifisering_status ───────────────┘                                   │
                                                                                     ▼
stg_dalux_leverandor (Daluxs faktiske selskaper) ── join gir companyId ──► snk_leverandor_dalux
                                                                                     │
                                                              PubSub ─► pubsub-writer ─► PATCH Dalux
```

**D365 er primær eier** av leverandørnummer, organisasjonsnummer, navn, adresser og
virksomhetens gyldighet. **SuperOffice** eier contactId, klassifisering, lokasjon og
evalueringskommentar. **Bisnode** bidrar med vurdering og sanksjonsscreening.
**Dalux er slave** — aldri en kilde; ingen mart bærer Dalux-kolonner.

### Kilden er vurderingsmarten — og det snevrer inn

`mrt_global_leverandorvurdering` er `FROM so`, filtrert på `d365_leverandornummer
IS NOT NULL` og deduplisert med `ROW_NUMBER() PARTITION BY d365_leverandornummer
… WHERE vendor_rn = 1`. Den er altså allerede én rad per leverandørnummer, men
**drevet av SuperOffice**: en leverandør som finnes i D365 uten SO-kontakt er ikke
med, og når ikke Dalux. Det er bevisst — vi vedlikeholder de leverandørene noen
faktisk har vurdert. En slik leverandør som allerede står i Dalux blir stående
urørt, ikke deaktivert.

Marten plukker bare tolv felter fra SO-payloaden, og henter verken gateadresse,
postnummer, telefon eller engangsleverandør-flagget fra D365. Write-back-marten
gjør derfor et 1:1-oppslag i `stg_d365_leverandor` på leverandørnummeret for de
feltene. Den delte marten røres ikke, så de tre `snk_leverandorvurdering_*`-sinkene
og `mrt_leverandor_omsetning_superoffice` er upåvirket.

`mrt_global_leverandor` har etter dette ingen konsumenter igjen, men **beholdes** —
den er Sesam-pariteten for `global-leverandor`. Ikke rydd den bort som død kode.

## Nøkkelen: `organisationId` = D365 `leverandor_id`

Bekreftet mot ekte `/companies`-data: companyId 10/19/56 bærer organisationId
500351/500142/503280 — D365s leverandørnummer, ikke norsk organisasjonsnummer.
Dalux-selskaper uten `organisationId` er manuelt opprettet og røres ikke.

Organisasjonsnummer har sitt eget hjem i Dalux: user-defined-feltet `Org.nr.`.

## Hva vi skriver

| Dalux-felt | Kilde |
|---|---|
| `name` | `navn` — vurderingsmarten gjør allerede `COALESCE(d365_navn, nameDepartment, bl_navn)` |
| `address.road` | `gate_adresse` (D365-staging) — ikke `adresse`, som er flerlinjes sammensetning |
| `address.zipCode` | `postnummer` (D365-staging) |
| `address.city` | `city` (SuperOffice) — vurderingsmarten har ikke D365s poststed |
| `address.number` | *(ingen kilde — bevares i Dalux)* |
| `phoneNo` | `kontakt_tlf` (D365-staging) |
| `email` | `emailAddress` (SuperOffice) |
| `isActive` | avledet, se under |
| UDF `Org.nr.` | `organisasjonsnummer` (D365) → `orgnr` (SO), begge normalisert |
| UDF `Klassifisering` | `klassifiseringbeskrivelse` (SO custom field 16) |
| UDF `Lokasjon` | `lokasjon` (SO custom field 8) |
| UDF `Vurderingskommentar` | `evalueringskommentar` (SO custom field 20) |

Alle fire user-defined-feltene i Dalux er altså KLP-eide. Merk navneforskjellen på
den siste: vår kolonne heter `evalueringskommentar`, Dalux-feltet heter
`Vurderingskommentar` — oversettelsen skjer i `UserDefinedFields.Map`.

**Aldri skrevet:** `companyTypes`, `disciplines` (begge «ignored on write» i APIet,
og de skal bære Dalux-egne verdier), `description`, `website`.

**Ikke bruk `unique_orgnr`** til `Org.nr.` — den faller tilbake på
`'uuid-' || contactId` når organisasjonsnummeret mangler, og den strengen skal aldri
skrives til Dalux.

### Tomt betyr «ingen mening», ikke «slett»

En tom verdi hos oss skal utelates fra PATCH-en, slik at en verdi noen
vedlikeholder manuelt i Dalux overlever. En sink kan ikke uttrykke dette — den
serialiserer enhver tom kolonne som `null`, og Dalux leser det som «blank ut
feltet». Derfor fjerner `pubsub-writer` null-felter før sending
(`StripNullProperties`). Marten gjør sin del ved å `NULLIF(TRIM(...), '')`-e alt:
en tom streng må bli NULL, ikke tom tekst.

Det siste er ikke en formalitet med denne kilden. Vurderingsmarten NULLIF-er ikke
sin egen SuperOffice-tekst — `lokasjon` er en ren `REGEXP_REPLACE(udf_8_dt, …)` —
så en tom DisplayText kommer hit som `''`. Uten NULLIF-en ville første PATCH blanket
ut `Lokasjon` i Dalux på alle leverandører der feltet ikke er satt i SuperOffice.

### isActive — enhver inaktiverende kilde vinner

`isActive = false` når **én** av disse slår til:

- D365: `sperret` (leverandørsperre ≠ 0), `underavvikling` (avvikling eller
  tvangsavvikling), `aktiv = 'nei'`, `engangsleverandor = 'ja'`
- SuperOffice: `stop = true` på kontakten
- Klassifiseringen er markert `dalux_aktiv = false` i seed-en
- **Bisnode: `sanksjonert`** — treff i sanksjonslistene. `COALESCE(sanksjonert, FALSE)`:
  NULL betyr «ikke screenet», ikke «rent»

En leverandør som er sperret i D365 kan aldri bli aktiv i Dalux fordi
klassifiseringen sier noe annet. Engangsleverandører skal ikke inn i Dalux; FM
APIet har ingen sletting, så inaktiv er eneste tilgjengelige uttrykk.

Øvrige Bisnode-felter — kredittrating, soliditet, betalingsanmerkning, revisor —
skrives ikke og får ingen konsekvens. Dalux har ingen felter å vise dem i, og å
opprette nye user-defined fields er ikke mulig via APIet.

### Klassifiseringsregelen bor i en seed

`dbt/seeds/dalux_klassifisering_status.csv` — `klassifiseringbeskrivelse`,
`dalux_aktiv`. Aktive: `Godkjent`, `Alltid godkjent`, `Konsernintern`. Alle andre
i lista er inaktive.

**Nøkkelen er beskrivelsen, ikke koden.** SuperOffice-kodene er miljøavhengige
(dev 17–22 og 31–32, test og prod 33–40), mens beskrivelsene er identiske. Én seed
virker derfor i alle miljøer, og det er samme verdi som skrives til UDF-en.

**Ukjent beskrivelse regnes som aktiv**, og flagges i stedet som
`klassifisering_ukjent` på marten. Motsatt default ville latt en ny eller omdøpt
tekst i SuperOffice stille deaktivere leverandører ved neste poll.

**Historikk verdt å kjenne:** `mrt_global_leverandor` leste feltet fra
`superOffice:16_DisplayText` (understrek), mens payloaden bruker
`superOffice:16:DisplayText` (kolon) — der var `klassifiseringbeskrivelse` NULL på
hver eneste rad til det ble rettet. Vurderingsmarten, som write-backen nå leser,
har alltid brukt kolon-nøkkelen og pakket ut den lokaliserte strengen
(`NO:"Ikke godkjent";`) riktig.

## Hvorfor sink, og hva det koster

Transportveien er repoets vanlige utgående mønster: mart → sink → Pub/Sub →
`pubsub-writer` → REST. Alternativet — en diff-fase i polleren som sammenlikner
mot Daluxs faktiske tilstand og bare sender det som avviker — ble vurdert og valgt
bort til fordel for konsistens med resten av repoet.

Konsekvensen er verdt å kjenne: en sink vet ikke hva Dalux har, så hver melding
blir en PATCH. D365-polleren upserter alle leverandørrader hver kjøring, så hele
settet kan re-emitteres per syklus. Med ~800 leverandører og 200 ms mellom kall er
det ~3 minutter. Det har også en fordel: en manuell endring i Dalux blir
overskrevet ved neste syklus, uten at noen trenger å oppdage den.

`SubscriptionConfig.SuppressUnchangedPayloads` kan slå av re-sendingen hvis volumet
blir et problem — men den er **av** som default nettopp fordi den ville latt
manuelle endringer i Dalux overleve.

## Skrivingen (`pubsub-writer`)

All forming skjer i `Services/PayloadShaper.cs`, styrt av `SubscriptionConfig`.
Ingenting av det nevner Dalux i kode:

| Innstilling | Gjør |
|---|---|
| `Method` + `IdField` | `PATCH {BaseUrl}/2.1/companies/{companyId}` |
| `ExcludeIdFieldFromBody` | `companyId` brukes i URL-en, ikke i kroppen |
| `WrapInProperty: "data"` | kroppen blir `{"data": {…}}`, slik `Company`-skjemaet krever |
| `StripNullProperties` | fjerner null-felter (se over) |
| `NestedObjects` | bygger `address` fra flate `address_*`-kolonner |
| `UserDefinedFields` | skriver de fire KLP-eide feltene inn i UDF-arrayet |
| `ApiKeyHeader` + `ApiKey` på destinasjonen | `X-API-Key` i stedet for OAuth |

**UDF-mekanikken:** sinken sender Daluxs *nåværende* UDF-array rått
(`userDefinedFields` fra staging), og writeren bytter kun `values` på de fire
mappede feltene. Hvert element sendes tilbake redusert til `name` + `values` —
**verifisert mot APIet**: en PATCH med den formen slår gjennom, og da slipper vi å
sende `userDefinedFieldId` og `description`, som spec-en riktignok kaller «ignored
on write», men som aldri er bekreftet tolerert. Alle elementer sendes tilbake, også
de vi ikke eier: å utelate ett kan tømme det, og APIet har ingen sletting å angre med. Siden `userDefinedFieldId` og `name` er
dokumentert «ignored on write», er det den eneste tolkningen som ikke kan ødelegge
feltene Dalux eier. Matching skjer på **navn**, ikke id: id-ene (1294–1297) er per
Dalux-miljø, navnene er stabile. Et selskap som mangler feltet hoppes over og
logges — APIet kan ikke opprette UDF-er.

## Sinken

`snk_leverandor_dalux` INNER JOINer `mrt_leverandor_dalux_writeback` mot
`stg_dalux_leverandor`. Joinen gjør to ting: den henter `companyId`, og den gjør
dette til update-grenen — en leverandør Dalux ikke kjenner emitterer ikke.
Oppretting (`POST /2.1/companies`) er ikke koblet opp; APIet har ingen
idempotensnøkkel på create, og omfanget må avklares mot reelle data først.

En duplikatvakt (`GROUP BY organisationid HAVING COUNT(*) = 1`) hindrer at et
organisationId på to Dalux-selskaper vifter ut i to PATCH-er mot vilkårlige
duplikater. Feltet er unikt i praksis, så vakten dropper ingenting normalt.

## Deploy

1. `./deploy.sh <env> --seed --select mrt_global_leverandor+ mrt_leverandor_dalux_writeback+ --full-refresh`

   **`--seed` er ikke valgfritt her.** `deploy.sh` kjører bare `dbt seed` når flagget
   er med — uten det finnes ikke `dalux_klassifisering_status` i miljøet, og marten
   feiler på `table or source not found: dalux_klassifisering_status`. Flagget seeder
   alt, ikke bare den nye fila, og kjører før `dbt run`.

   **Begge selektorene trengs.** `mrt_global_leverandor+` rydder Dalux-joinen ut av
   masteren, men write-back-marten henger ikke lenger under den: den leser
   `mrt_global_leverandorvurdering` og `stg_d365_leverandor`. Uten den andre
   selektoren blir verken marten eller `snk_leverandor_dalux` bygget.
2. `DROP MATERIALIZED VIEW mrt_dalux_leverandor;` manuelt per miljø, **etter**
   steg 1. dbt sletter ikke objekter for modeller som fjernes fra prosjektet, og
   RisingWave nekter å droppe den før `mrt_global_leverandor` ikke lenger avhenger
   av den.
3. `stg_dalux_leverandor` fikk kolonnen `website` (ny i 2.5.0) — staging må
   gjenskapes (`--select stg_dalux_leverandor+ --full-refresh`), og poller-brukeren
   trenger GRANT på nytt etterpå. Tabellen er tom til neste poll.
4. Terraform i den separate interne infrastruktur-repoet: topic `leverandor-dalux-<env>`, subscription
   `leverandor-dalux-worker-<env>` med retry + dead-letter, og Dalux-API-nøkkelen
   inn i `pubsub-writer` sine Vault-secrets.
5. **`paused` betyr at sinken ikke finnes, ikke at den står stille.** `deploy.sh`
   oversetter `DALUX_SINK_MODE=paused` til `--exclude *snk*dalux`, så stegene over
   bygger marten, men oppretter aldri `snk_leverandor_dalux`. Gjennomgå SELECT-en
   først — `dbt compile --select snk_leverandor_dalux --target <env>` virker uansett,
   siden compile ikke deployer noe.
6. Når SELECT-en er godkjent: sett `DALUX_SINK_MODE=running` og kjør
   `./deploy.sh <env> --select snk_leverandor_dalux` for å faktisk opprette sinken.
   Det er dette steget som starter skrivingen til Dalux — ikke gjør det før
   Terraform i steg 4 er på plass, ellers står meldingene og hoper seg opp.

## Kunnskap som ikke må gå tapt

Fra `mrt_dalux_leverandor`, som er slettet (den hadde ingen konsumenter igjen etter
at masteren ble renset). Begge punktene er utledet fra ekte data:

- **`companyTypes` kan pakke flere typer i ett array-element** som
  semikolonseparert streng: `["Installatør; Leverandør; Serviceleverandør"]`. En
  containment-sjekk må splitte hvert element på `;` og sammenlikne trimmede
  tokens. Verken eksakt match eller `LIKE '%Leverandør%'` er riktig — den første
  bommer på det pakkede tilfellet, den andre kan treffe `Serviceleverandør`.
- **Kolonnen er rå tekst.** Et `::jsonb`-kast på ugyldig JSON kaster exception i
  RisingWave i stedet for å returnere NULL, så kastet må guardes med en
  `TRIM(...) LIKE '[%'`-sjekk først.

## Åpne punkter

- **Skrivetilgang** er bekreftet for nøkkelen som ble brukt i den manuelle
  PATCH-testen. Det gjenstår å bekrefte at det er *samme* nøkkel som ligger i Vault
  for `pubsub-writer` — er den en annen identitet, vises det som 403/E40301 ved
  første kjøring.
- ~~Bekreft UDF-adresseringen~~ — **verifisert**: en PATCH med
  `data.userDefinedFields.items[]` der hvert element bare har `name` og `values`
  virker som forventet. Feltet identifiseres på navn alene.
- Historikk må være avslått for alle fire feltene, ellers avviser APIet skrivingen.
  Ikke verifisert per felt ennå.
- **Idempotent opprettelse** — finnes upsert på `organisationId`? Forutsetning for
  å skru på oppretting.
- **Avviksrapport** er utsatt: når sinken kjører, overskrives manuelle endringer i
  Dalux stille, og for `companyTypes`/`disciplines` er de permanente og usynlige.
  Formen er skissert i planen — et `materialized='view'` som FULL OUTER JOINer
  ønsket mot faktisk tilstand.
