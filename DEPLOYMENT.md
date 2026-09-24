# Camunda CDC Deployment Guide

Complete guide for deploying RisingWave CDC from Camunda PostgreSQL database.

## Summary of Changes

### 1. Created Dedicated CDC User ✅
- **User**: `risingwave-cdc-user` (read-only)
- **Privileges**:
  - `REPLICATION` - Access to PostgreSQL WAL for CDC
  - `SELECT` on all tables - Read Camunda data
  - No write access - Security best practice

### 2. Infrastructure Changes ✅
**Files Modified** (in the separate internal infrastructure/Terraform repo, not part of this repo):
- `terraform/dev/camunda.tf`
- `terraform/dev/variables.tf`
- `terraform/dev/main.tf`

**What was added**:
1. Database flags for logical replication
2. New CDC user with proper privileges
3. Kubernetes secrets for north cluster
4. kubernetes.north provider configuration

### 3. SQL Files Created ✅
**Location**: `KdiRisingWave/sql/`

```
sql/
├── 1_sources/
│   └── camunda_cdc_source.sql       # PostgreSQL CDC source
├── 2_staging/
│   └── camunda_tables.sql           # 30+ Camunda tables with PRIMARY KEYs
├── 3_marts/
│   └── camunda_materialized_views.sql  # 20+ analytics views
└── deploy_all.sql                   # Master deployment script
```

## Deployment Steps

### Step 1: Apply Terraform Changes

**Important**: This will restart the Camunda database instance!

```bash
cd terraform/dev   # in the separate internal infrastructure repo

# You'll need the postgres superuser password
# Get it from GCP Cloud SQL console or secret manager

# Set the postgres password
export TF_VAR_postgres_password="YOUR_POSTGRES_PASSWORD"

# Or use a .tfvars file
cat > terraform.tfvars <<EOF
postgres_password = "YOUR_POSTGRES_PASSWORD"
EOF

# Initialize and apply
tofu init
tofu plan
tofu apply
```

**What this does**:
1. ✅ Enables logical replication flags (requires restart)
2. ✅ Creates `risingwave-cdc-user` with password
3. ✅ Grants REPLICATION + SELECT privileges
4. ✅ Creates Kubernetes secret in north cluster

### Step 2: Verify Database Configuration

After Terraform apply completes, verify the setup:

```bash
# Connect to Camunda database
gcloud sql connect <camunda-sql-instance>-dev --user=postgres --database=process-engine

# Check logical replication is enabled
SHOW wal_level;
-- Should show: logical

# Check CDC user privileges
SELECT rolname, rolreplication FROM pg_roles WHERE rolname = 'risingwave-cdc-user';
-- Should show: risingwave-cdc-user | t

# Check table permissions
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE grantee = 'risingwave-cdc-user'
LIMIT 5;
-- Should show SELECT privileges

\q
```

### Step 3: Deploy CDC to RisingWave

Run the deployment script:

```bash
cd scripts
./deploy-camunda-cdc.sh --env dev
```

**What this does**:
1. ✅ Connects to Kubernetes cluster
2. ✅ Retrieves CDC credentials
3. ✅ Creates ConfigMaps with SQL files
4. ✅ Port-forwards to RisingWave
5. ✅ Executes SQL deployment

### Step 4: Verify Deployment

Connect to RisingWave and verify:

```bash
# Port-forward (if not already running)
kubectl port-forward svc/risingwave-frontend-service 4566:4566

# Connect
psql -h localhost -p 4566 -d dev -U root

# Check CDC source
SHOW SOURCES;

# Check tables
SELECT count(*) FROM rw_catalog.rw_tables WHERE name LIKE 'act_%';
-- Should show: 30+ tables

# Check materialized views
SELECT count(*) FROM rw_catalog.rw_materialized_views WHERE name LIKE 'mv_%';
-- Should show: 20+ views

# Test a simple query
SELECT * FROM mv_system_health_dashboard;

\q
```

## Troubleshooting

### Issue: "Postgres user must be superuser or replication role"

**Cause**: CDC user doesn't have REPLICATION privilege

**Solution**:
```sql
-- Connect as postgres superuser
ALTER ROLE "risingwave-cdc-user" WITH REPLICATION;
```

### Issue: "CDC table without primary key constraint"

**Cause**: Missing PRIMARY KEY in table definition

**Solution**: Tables are already defined with PRIMARY KEYs in `camunda_tables.sql`. If you see this error, verify the SQL file is being used.

### Issue: "sql parser error: expected ',' or ')' after column definition"

**Cause**: VARCHAR with length specifications (e.g., VARCHAR(64)) is not supported in RisingWave CDC tables

**Solution**: ✅ FIXED - All VARCHAR types in `camunda_tables.sql` have been updated to use VARCHAR without length specifications. RisingWave CDC tables must use VARCHAR, not VARCHAR(n).

### Issue: "failed to create source worker"

**Cause**: Logical replication not enabled or incorrect permissions

**Solution**:
```sql
-- Check wal_level
SHOW wal_level;  -- Should be 'logical'

-- For GCP Cloud SQL, ensure flag is set
cloudsql.logical_decoding = on

-- Check user can create replication slots
SELECT * FROM pg_replication_slots;
```

### Issue: "port 4566 already in use"

**Solution**:
```bash
# Kill existing port-forward
netstat -ano | findstr :4566
taskkill /PID <PID> /F

# Or on Linux/Mac
pkill -f "port-forward.*4566"
```

## Security Notes

### Dedicated CDC User
✅ **Best Practice**: Separate read-only user for CDC
- `risingwave-cdc-user` - CDC only (REPLICATION + SELECT)
- `camunda-user` - Camunda application (full access)
- `postgres` - Superuser (admin only)

### Network Security
✅ IP Allowlisting on Cloud SQL:
- Dev cluster: `10.0.0.0/16`
- Only authorized IPs can connect

### Credentials Management
✅ Stored in Kubernetes secrets:
- Secret: `risingwave-camunda-cdc-credentials`
- Namespace: default (north cluster)
- Labels: `application=risingwave`, `source=camunda`

## Monitoring

### Check CDC Health

```sql
-- RisingWave: Check source status
SELECT name, source_type FROM rw_catalog.rw_sources;

-- PostgreSQL: Check replication slots
SELECT slot_name, active, restart_lsn
FROM pg_replication_slots
WHERE slot_name LIKE 'risingwave%';

-- PostgreSQL: Check publications
SELECT pubname FROM pg_publication WHERE pubname LIKE 'risingwave%';
```

### Performance Metrics

```sql
-- RisingWave: Row counts
SELECT 'Executions' as table, count(*) FROM act_ru_execution
UNION ALL
SELECT 'Tasks', count(*) FROM act_ru_task
UNION ALL
SELECT 'Incidents', count(*) FROM act_ru_incident;

-- Dashboard view
SELECT * FROM mv_system_health_dashboard;
```

## Next Steps

After successful deployment:

1. **Set up monitoring alerts** for CDC lag
2. **Create custom materialized views** for specific business metrics
3. **Configure retention policies** for historical data
4. **Set up backups** for RisingWave state
5. **Apply same setup to test and prod** environments

## References

- [RisingWave Docs](https://docs.risingwave.com/)
- [PostgreSQL CDC Connector](https://docs.risingwave.com/docs/current/ingest-from-postgres-cdc/)
- [Camunda Database Schema](https://docs.camunda.org/manual/latest/user-guide/process-engine/database/database-schema/)

## Support

For issues:
1. Check logs: `kubectl logs -l app=risingwave`
2. Check this guide's troubleshooting section
3. Review RisingWave documentation
