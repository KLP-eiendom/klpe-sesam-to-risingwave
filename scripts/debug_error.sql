select * from rw_event_logs where event_type like '%FAIL%' or event_type like '%ERROR%' order by timestamp desc;

SELECT id, name, definition FROM rw_catalog.rw_sinks WHERE id = 4123;

-- Finn dupliserte kundenummer i mrt_global_customer (årsak til IX_Kunde_Nummer-brudd)
SELECT kundenummer, COUNT(*) AS antall, array_agg(contactid ORDER BY contactid) AS contactids
FROM mrt_global_customer
WHERE kundenummer IS NOT NULL
GROUP BY kundenummer
HAVING COUNT(*) > 1
ORDER BY antall DESC;

-- Finn hvilken materialisert visning (strømmejobb) som inneholder fragmentet
SELECT f.fragment_id, f.table_id, j.name AS job_name, j.id AS job_id
FROM rw_catalog.rw_fragments f
LEFT JOIN rw_catalog.rw_streaming_jobs j ON f.table_id = j.id
WHERE f.fragment_id = 36997;