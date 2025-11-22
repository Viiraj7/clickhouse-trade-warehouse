# Troubleshooting Guide

## Issue: ClickHouse containers keep restarting

**Symptoms:**
- `docker-compose ps` shows containers with "Restarting" status
- Tables cannot be created
- Keeper connection errors

**Root Cause:**
ClickHouse servers are trying to connect to ClickHouse Keeper before it's fully ready.

**Solution:**
1. Restart containers and wait longer:
```powershell
docker-compose restart clickhouse-01 clickhouse-02
Start-Sleep -Seconds 180  # Wait 3 full minutes
```

2. Check if Keeper is healthy:
```powershell
docker exec clickhouse-keeper clickhouse-keeper-client -q "mntr" 2>&1 | Select-String "zk_server_state"
```

3. If still failing, check logs:
```powershell
docker-compose logs clickhouse-keeper --tail 50
docker-compose logs clickhouse-01 --tail 50
```

4. Nuclear option - full restart:
```powershell
docker-compose down -v
docker-compose up -d
Start-Sleep -Seconds 180
```

## Issue: Authentication failed / password incorrect

**Symptoms:**
- API shows: `Authentication failed: password is incorrect`
- Error code 516

**Root Cause:**
The ClickHouse driver is trying to authenticate but the configuration mismatch.

**Solution:**
The API has been fixed to use empty password. Just restart the API:
```powershell
cd api
python -m uvicorn main:app --reload
```

If still failing, verify ClickHouse configuration:
```powershell
docker exec clickhouse-01 clickhouse-client --query "SELECT 1"
```

## Issue: TTL expression error (DateTime64 vs DateTime)

**Symptoms:**
- Error: `TTL expression result column should have DateTime or Date type, but has DateTime64`

**Root Cause:**
The `01_ticks_local.sql` file has `TTL event_time + INTERVAL 30 DAY` but `event_time` is DateTime64.

**Solution:**
The SQL has been fixed to use `TTL toDateTime(event_time) + INTERVAL 30 DAY`. Re-run the initialization:
```powershell
docker-compose down -v
docker-compose up -d
Start-Sleep -Seconds 120
Get-Content sql_schema\01_ticks_local.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
```

## Issue: PowerShell script syntax error

**Symptoms:**
- `Unexpected token '}' in expression or statement`
- Script won't run

**Solution:**
Use the new fixed script:
```powershell
.\setup_windows.ps1
```

## Issue: Dashboard shows 503 errors

**Symptoms:**
- Dashboard loads but all queries return "503 Service Unavailable"

**Root Cause Chain:**
1. API not running → 503
2. API running but can't connect to ClickHouse → 503  
3. ClickHouse running but tables don't exist → 503
4. Tables exist but no data → Empty results (not 503)

**Diagnostic Steps:**

1. **Check if API is running:**
```powershell
# In API terminal, you should see:
# INFO: Uvicorn running on http://127.0.0.1:8000
```

2. **Check if ClickHouse is responding:**
```powershell
docker exec clickhouse-01 clickhouse-client --query "SELECT 1"
# Should return: 1
```

3. **Check if tables exist:**
```powershell
docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"
# Should show: ticks_local, ticks_kafka, ticks_buffer, etc.
```

4. **Check if data exists:**
```powershell
docker exec clickhouse-01 clickhouse-client --query "SELECT count() FROM ticks_local"
# Should return a number > 0 if producer has been running
```

**Solutions:**

- If API not running: Start it
- If ClickHouse not responding: Wait 2-3 minutes, containers may still be initializing
- If tables missing: Run `.\setup_windows.ps1`
- If no data: Start the producer

## Issue: Producer connects but no data appears

**Symptoms:**
- Producer shows "Sent X ticks..." incrementing
- But queries return 0 rows

**Diagnostic:**
```powershell
# Check Kafka topic
docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list

# Check if Kafka consumer is active
docker exec clickhouse-01 clickhouse-client --query "SELECT * FROM ticks_kafka LIMIT 5"
```

**Common Causes:**
1. Kafka topic not created → Producer creates it automatically, wait 30 seconds
2. Buffer hasn't flushed yet → Wait up to 60 seconds
3. Materialized view not working → Check MV exists

**Solution:**
```powershell
# Verify full pipeline
docker exec clickhouse-01 clickhouse-client --query "SELECT count() FROM ticks_kafka"
docker exec clickhouse-01 clickhouse-client --query "SELECT count() FROM ticks_buffer"
docker exec clickhouse-01 clickhouse-client --query "SELECT count() FROM ticks_local"
```

## Complete Reset Procedure

If nothing works, do a complete reset:

```powershell
# 1. Stop everything
docker-compose down -v

# 2. Clean up any stuck processes
docker ps -a
docker rm -f $(docker ps -aq)  # If any containers stuck

# 3. Start fresh
docker-compose up -d

# 4. Wait for full initialization (IMPORTANT!)
Start-Sleep -Seconds 180

# 5. Verify containers are healthy
docker-compose ps
# All should show "healthy" or "running"

# 6. Test basic connectivity
docker exec clickhouse-01 clickhouse-client --query "SELECT 1"

# 7. Initialize schema
.\setup_windows.ps1

# 8. Start components in separate terminals
# Terminal 1: cd data_producer; python producer.py
# Terminal 2: cd api; python -m uvicorn main:app --reload  
# Terminal 3: cd dashboard; python -m streamlit run streamlit_app.py
```

## Checking System Resources

ClickHouse requires significant resources:

```powershell
# Check Docker resource allocation
docker stats --no-stream

# ClickHouse needs:
# - At least 4GB RAM
# - At least 2 CPU cores
```

If your machine is low on resources:
1. Close other applications
2. Increase Docker Desktop resource limits
3. Consider running only 1 ClickHouse node (modify docker-compose.yml)

## Getting More Help

If issues persist:

1. Check full logs:
```powershell
docker-compose logs > full_logs.txt
```

2. Check ClickHouse system tables:
```powershell
docker exec clickhouse-01 clickhouse-client --query "SELECT * FROM system.errors ORDER BY last_error_time DESC LIMIT 10"
docker exec clickhouse-01 clickhouse-client --query "SELECT * FROM system.warnings"
```

3. Verify network connectivity:
```powershell
docker network ls
docker network inspect clickhouse_trade_warehouse_default
```
