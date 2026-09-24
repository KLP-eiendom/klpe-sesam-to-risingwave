#!/usr/bin/env python3
"""
seed_overrides.py — per-table overrides + a small IdExpression evaluator for seed_from_sesam.py.

The generic seeder path (strip Sesam namespace → case-insensitive match to the stg DDL columns →
clean transit values → keep Sesam's _id) covers most tables. This module holds the EXCEPTIONS,
plus a minimal Python port of RisingWavePollerCommon/Services/IdExpressionEvaluator.cs for the few
tables whose stg _id must be a computed expression (so within-table dedup ordering matches prod).

Add an override only when a seed --dry-run warns about dropped/missing fields or a wrong _id.

Override schema (all keys optional), keyed by stg table name:
  {
    "sesam_dataset": str,   # explicit Sesam source dataset (else verify_staging_counts.table_to_sesam_dataset)
    "id":            str,   # IdExpression -> _id (else keep Sesam's _id)
    "field_renames": dict,  # {sesam_key: stg_column}, applied AFTER strip_prefix
    "computed_fields": dict,  # {stg_column: callable(row) -> value}; injects a computed top-level
                              # key (for PK columns derived from NESTED payload fields, which the
                              # webhook writer's entity.get(col) extraction can't reach)
    "table_type":    str,   # force "webhook" | "poller" (else auto-detected from the staging SQL)
    "where_filter":  callable,  # row -> bool; keep only rows the poller's WhereClause would fetch
  }
"""

# ── Per-table overrides ──────────────────────────────────────────────────────────

SEED_OVERRIDES = {
    # The one table whose mart takes MAX(_id) for ordering (mrt_global_property building image),
    # so its _id must match the poller's composite, not Sesam's _id.
    "stg_fdvweb_building_image": {
        "id": 'concat(byggNavnId, "-", bildearkivTekst)',
    },
    # Children-flattening table (eiendom poller expands tasks[] from the parent). Dataset name
    # differs from the derived one; the child rows live under a nested array.
    # NOTE: children handling is implemented in seed_from_sesam only if/when this table is seeded.
    "stg_eiendom_prosjektsortedusertask": {
        "sesam_dataset": "forvalter-prosjektsortedusertask",
    },
    # Sesam SOURCE flattens nested paths with '/' (contactPhone/formattedNumber); the production
    # SuperOffice webhook that mrt_superoffice_contactsimple was built against delivers camelCase
    # (payload->>'contactPhoneFormattedNumber'). Rename so the mart field resolves. ('description'
    # is absent from the Sesam source entirely → stays NULL; prod-webhook-only field — see F8.)
    "stg_superoffice_contactsimple": {
        "field_renames": {"contactPhone/formattedNumber": "contactPhoneFormattedNumber"},
    },
    # F1 (Option B): seed the CANONICAL user set, not the raw feed. Sesam's raw `superoffice-user`
    # holds 36371 rows keyed `superoffice-user:<personId>-<email>`; `superoffice-migrateduser`
    # filters to the 6701 rows whose _id is the pure `superoffice-user:<personId>` form — the set
    # every downstream user pipe is built on. Seeding the raw feed made all user sinks over-produce
    # ~3× (see seed_findings.md F1). The real prod webhook needs its own reduction later
    # (associateDbId candidate) — that's a mart concern, not a seed concern.
    "stg_superoffice_user": {
        "sesam_dataset": "superoffice-migrateduser",
    },
    # Historic ticket payloads mix TicketId/ticketId key casing (marts COALESCE both). The PK
    # webhook table declares "ticketId", and the webhook seed path extracts extra columns
    # case-sensitively — rename so the PK column always populates from PascalCase-era entities.
    "stg_superoffice_ticket": {
        "field_renames": {"TicketId": "ticketId"},
    },
    # PK column `id` mirrors Sesam's own dataset identity (bisnode-leverandor._id):
    # concat(dunsNumber, "_", coalesce(registrationNumber, vatNumber, "")). dunsNumber is the
    # primary disambiguator; falls back to the legacy identifikasjon.{dunsnr,orgnr} shape for
    # historical rows.
    "stg_bisnode_leverandor": {
        "computed_fields": {"id": lambda r: _bisnode_leverandor_id(r)},
    },
    # PK column `id` mirrors Sesam's bisnode-sanksjoner._id: if verifiedCompany.dunsNo is set,
    # concat(dunsNo, "_", regNo); otherwise the screening reference, so every no-match
    # screening keeps its own identity instead of collapsing into the queried company's key.
    "stg_bisnode_sanksjoner": {
        "computed_fields": {"id": lambda r: _bisnode_sanksjoner_id(r)},
    },
}


def _bisnode_leverandor_id(row):
    ids = (row.get("companyInformation") or {}).get("identifiers") or {}
    duns = ids.get("dunsNumber")
    reg_or_vat = ids.get("registrationNumber") or ids.get("vatNumber")
    if duns is None:
        identifikasjon = row.get("identifikasjon") or {}
        duns = identifikasjon.get("dunsnr")
        reg_or_vat = reg_or_vat or identifikasjon.get("orgnr")
    if duns is None:
        return None
    return f"{duns}_{reg_or_vat if reg_or_vat is not None else ''}"


def _bisnode_sanksjoner_id(row):
    verified = row.get("verifiedCompany") or {}
    duns = verified.get("dunsNo")
    if duns:
        reg_no = verified.get("regNo")
        return f"{duns}_{reg_no if reg_no is not None else ''}"
    return row.get("reference")


def get_override(table_name):
    return SEED_OVERRIDES.get(table_name, {})


# ── Minimal IdExpression evaluator (port of IdExpressionEvaluator.cs) ──────────────
# Supports: concat(...), coalesce(...), lower(x), upper(x), string(x), date(x),
# "string literals", and bare identifiers (case-insensitive lookup in the row dict).

class _Tok:
    FUNC, IDENT, STR, COMMA, RPAREN, END = range(6)


def _tokenize(expr):
    toks, i, n = [], 0, len(expr)
    while i < n:
        c = expr[i]
        if c.isspace():
            i += 1
            continue
        if c == ",":
            toks.append((_Tok.COMMA, ",")); i += 1; continue
        if c == ")":
            toks.append((_Tok.RPAREN, ")")); i += 1; continue
        if c == '"':
            j = i + 1; buf = []
            while j < n and expr[j] != '"':
                if expr[j] == "\\" and j + 1 < n:
                    buf.append(expr[j + 1]); j += 2
                else:
                    buf.append(expr[j]); j += 1
            toks.append((_Tok.STR, "".join(buf))); i = j + 1; continue
        if c.isalnum() or c == "_":
            j = i
            while j < n and (expr[j].isalnum() or expr[j] == "_"):
                j += 1
            word = expr[i:j]
            # function call if the next non-space char is '('
            k = j
            while k < n and expr[k].isspace():
                k += 1
            if k < n and expr[k] == "(":
                toks.append((_Tok.FUNC, word)); i = k + 1
            else:
                toks.append((_Tok.IDENT, word)); i = j
            continue
        raise ValueError(f"IdExpression: unexpected char {c!r} in {expr!r}")
    toks.append((_Tok.END, ""))
    return toks


def _lookup(row, name):
    if name in row:
        return row[name]
    low = name.lower()
    for k, v in row.items():
        if k.lower() == low:
            return v
    return None


def _apply(fn, args):
    fn = fn.lower()
    if fn == "concat":
        return "".join("" if a is None else str(a) for a in args)
    if fn == "coalesce":
        for a in args:
            if a is not None and a != "":
                return a
        return ""
    if fn == "lower":
        return ("" if args[0] is None else str(args[0])).lower()
    if fn == "upper":
        return ("" if args[0] is None else str(args[0])).upper()
    if fn == "string":
        return "" if args[0] is None else str(args[0])
    if fn == "date":
        return "" if args[0] is None else str(args[0])[:10]
    raise ValueError(f"IdExpression: unknown function {fn!r}")


def evaluate(expr, row):
    """Evaluate an IdExpression against a (strip-prefixed) Sesam entity dict -> str."""
    toks = _tokenize(expr)
    pos = 0

    def parse_value():
        nonlocal pos
        kind, val = toks[pos]
        if kind == _Tok.STR:
            pos += 1
            return val
        if kind == _Tok.IDENT:
            pos += 1
            return _lookup(row, val)
        if kind == _Tok.FUNC:
            pos += 1  # consume FUNC (its '(' was already consumed by the tokenizer)
            args = []
            if toks[pos][0] != _Tok.RPAREN:
                args.append(parse_value())
                while toks[pos][0] == _Tok.COMMA:
                    pos += 1
                    args.append(parse_value())
            if toks[pos][0] != _Tok.RPAREN:
                raise ValueError(f"IdExpression: expected ')' in {expr!r}")
            pos += 1  # consume ')'
            return _apply(val, args)
        raise ValueError(f"IdExpression: unexpected token {val!r} in {expr!r}")

    result = parse_value()
    if toks[pos][0] != _Tok.END:
        raise ValueError(f"IdExpression: trailing tokens in {expr!r}")
    return "" if result is None else str(result)
