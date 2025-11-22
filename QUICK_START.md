# Quick Start Guide

## Complete Setup Steps (Windows)

### Step 1: Start Docker Containers
```powershell
docker-compose down -v
docker-compose up -d
```

### Step 2: Wait for Services (60 seconds minimum)
```powershell
Start-Sleep -Seconds 60
```

### Step 3: Initialize ClickHouse Schema (Manual Commands)
Run these commands **one by one** in PowerShell:

```powershell
# 1. Create main local table
Get-Content sql_schema\01_ticks_local.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# 2. Create Kafka consumer table
Get-Content sql_schema\02_ticks_kafka.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# 3. Create buffer table
Get-Content sql_schema\04_ticks_buffer.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# 4. Create Kafka to Buffer materialized view
Get-Content sql_schema\03_kafka_to_buffer_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# 5. Create distributed table
Get-Content sql_schema\05_ticks_all.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# 6. Create deduplication table
Get-Content sql_schema\06_ticks_dedup.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# 7. Create 1-minute aggregation table
Get-Content sql_schema\07_trades_1m_agg.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# 8. Create 1-minute aggregation materialized view
Get-Content sql_schema\08_trades_1m_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# 9. Create local to dedup materialized view
Get-Content sql_schema\09_local_to_dedup_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
```

### Step 4: Verify Tables Created
```powershell
docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"
```

You should see 9 tables:
- kafka_to_buffer_mv
- local_to_dedup_mv
- ticks_all
- ticks_buffer
- ticks_dedup
- ticks_kafka
- ticks_local
- trades_1m_agg
- trades_1m_mv

### Step 5: Start Data Producer
In a **new terminal**:
```powershell
cd data_producer
python producer.py
```

Let it run and generate ~50,000-100,000 ticks (about 1-2 minutes).

### Step 6: Start the API
In a **new terminal**:
```powershell
cd api
python -m uvicorn main:app --reload
```

API will be available at: http://localhost:8000

### Step 7: Start the Dashboard
In a **new terminal**:
```powershell
cd dashboard
python -m streamlit run streamlit_app.py
```

Dashboard will be available at: http://localhost:8501

## Testing the Dashboard

1. **Symbol**: Enter `AAPL`, `GOOGL`, `MSFT`, or `TSLA`
2. **Minutes**: Try `100` or `1000`
3. Click the run buttons to see the performance difference!

## Common Issues

### Issue: "Authentication failed" error in API
**Solution**: The API is already configured correctly with an empty password. If you see this:
1. Stop all terminals (Ctrl+C)
2. Run: `docker-compose restart clickhouse-01 clickhouse-02`
3. Wait 30 seconds
4. Restart the API: `cd api && python -m uvicorn main:app --reload`

### Issue: "Connection refused" to port 9000
**Solution**: ClickHouse is still starting.
```powershell
# Check status
docker-compose ps

# Wait for healthy status
docker-compose restart clickhouse-01 clickhouse-02
Start-Sleep -Seconds 30
```

### Issue: Tables not created / Keeper connection errors
**Solution**: Wait longer for ClickHouse Keeper to be ready.
```powershell
docker-compose down -v
docker-compose up -d
Start-Sleep -Seconds 90  # Wait 90 seconds instead of 60
# Then run the SQL commands from Step 3 again
```

### Issue: Dashboard shows 503 errors
**Solution**: Make sure the API is running and connected:
1. Check API terminal - should show "Successfully connected to ClickHouse"
2. If not, restart: `cd api && python -m uvicorn main:app --reload`
3. Verify: http://localhost:8000 should return JSON

## Full Reset (If Everything Breaks)

```powershell
# Stop everything
docker-compose down -v

# Clean start
docker-compose up -d
Start-Sleep -Seconds 90

# Run all SQL setup commands from Step 3
# Then start producer, API, and dashboard
```

## Performance Tips

- Let the producer run for at least 1-2 minutes to generate enough data
- Try different symbols: AAPL, GOOGL, MSFT, TSLA
- Compare "slow" vs "fast" query times - you should see 10-100x difference!
- The "fast" query uses pre-aggregated rollups, demonstrating ClickHouse's power
