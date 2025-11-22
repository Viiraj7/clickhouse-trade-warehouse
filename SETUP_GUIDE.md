# ClickHouse Trade Warehouse - Complete Setup Guide

## Prerequisites
- Docker Desktop installed and running
- Python 3.8+ installed
- PowerShell 7+ (Windows)

## Quick Start - 3 Steps

### Step 1: Start Docker Containers and Initialize Database

```powershell
# Clean and start containers
docker-compose down -v
docker-compose up -d

# Wait for containers to be healthy (2 minutes)
Start-Sleep -Seconds 120

# Initialize ClickHouse schema
Get-Content sql_schema\01_ticks_local.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\02_ticks_kafka.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\04_ticks_buffer.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\03_kafka_to_buffer_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\05_ticks_all.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\06_ticks_dedup.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\07_trades_1m_agg.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\08_trades_1m_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\09_local_to_dedup_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery

# Verify tables
docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"
```

### Step 2: Start Data Producer (Terminal 1)

```powershell
cd data_producer
pip install -r requirements.txt
python producer.py
```

Leave this running. It will generate ~1000 trades per second.

### Step 3: Start API and Dashboard (Terminal 2 & 3)

**Terminal 2 - API:**
```powershell
cd api
pip install -r requirements.txt
python -m uvicorn main:app --reload
```

**Terminal 3 - Dashboard:**
```powershell
cd dashboard
pip install -r requirements.txt
python -m streamlit run streamlit_app.py
```

### Access the System

- **Dashboard**: http://localhost:8501
- **API Docs**: http://localhost:8000/docs
- **ClickHouse HTTP**: http://localhost:8123

## Testing the Dashboard

1. Wait for producer to send ~10,000+ ticks (about 10 seconds)
2. In the dashboard:
   - Enter symbol: `AAPL`
   - Minutes to fetch: `100`
   - Click both "Run Slow Query" and "Run Fast Query"
3. Observe the speed difference!

## Troubleshooting

### If ClickHouse containers keep restarting:

```powershell
# Check logs
docker-compose logs clickhouse-01
docker-compose logs clickhouse-keeper

# If you see keeper connection errors, wait longer (3 minutes)
Start-Sleep -Seconds 180

# Then retry the schema initialization
```

### If API shows "Authentication failed":

The API is trying to connect to port 9000 with empty password. This is correct for the default ClickHouse setup. The error means ClickHouse isn't ready yet or the containers are still starting.

**Solution**: Wait 2-3 minutes after `docker-compose up -d`, then restart the API.

### If dashboard shows 503 errors:

The API isn't running or ClickHouse isn't ready.

1. Make sure API is running (Terminal 2)
2. Check API logs for connection errors
3. Restart API if needed

## Complete Reset

If something goes wrong, reset everything:

```powershell
# Stop everything
docker-compose down -v

# Start from Step 1 again
docker-compose up -d
Start-Sleep -Seconds 120
# ... run schema initialization commands ...
```

## What Each Component Does

- **ClickHouse Cluster**: 2 replicated nodes + keeper for coordination
- **Kafka**: Message broker for streaming trades
- **Data Producer**: Generates fake market data
- **API**: FastAPI backend for queries
- **Dashboard**: Streamlit UI for visualization

## Expected Results

- **Slow Query**: 50-200ms (scans raw data)
- **Fast Query**: 1-10ms (reads pre-aggregated rollups)
- **Speed improvement**: 10-50x faster!
