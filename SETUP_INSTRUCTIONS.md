# ClickHouse Trade Warehouse - Setup Instructions

## Quick Start (Windows)

### Step 1: Start Infrastructure
```powershell
# Clean up any existing containers and start fresh
docker-compose down -v
docker-compose up -d

# Wait for containers to be healthy (2 minutes)
Start-Sleep -Seconds 120
```

### Step 2: Initialize ClickHouse Schema
```powershell
# Run SQL files in order
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

### Step 3: Start Data Producer
Open a **new terminal**:
```powershell
cd data_producer
python producer.py
```
Leave this running to generate test data.

### Step 4: Start API Server
Open a **new terminal**:
```powershell
cd api
python -m uvicorn main:app --reload
```
API will be available at: http://localhost:8000

### Step 5: Start Dashboard
Open a **new terminal**:
```powershell
cd dashboard
python -m streamlit run streamlit_app.py
```
Dashboard will be available at: http://localhost:8501

## Troubleshooting

### ClickHouse Containers Keep Restarting
```powershell
# Check logs
docker-compose logs clickhouse-01
docker-compose logs clickhouse-keeper

# Wait longer for ClickHouse Keeper to be ready
Start-Sleep -Seconds 180

# Try initialization again
```

### API Shows "Authentication Failed"
The API is now configured to use default user with empty password. This should work automatically.

### Tables Not Created
```powershell
# Check if ClickHouse is responding
docker exec clickhouse-01 clickhouse-client --query "SELECT 1"

# If this fails, wait 2-3 more minutes and try again
```

### Dashboard Shows 503 Errors
Make sure:
1. Docker containers are running: `docker-compose ps`
2. API server is running: Check terminal where you ran uvicorn
3. Tables exist: `docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"`
4. Data producer has sent some data (check its terminal output)

## Automated Setup Script

For convenience, run the automated setup script:
```powershell
.\setup_complete_fixed.ps1
```

This will:
1. Clean up existing containers
2. Start fresh containers
3. Wait for them to be healthy
4. Initialize all tables
5. Verify everything is working

Then just start the three components (producer, API, dashboard) in separate terminals.

## What Data to Enter in Dashboard

Once everything is running:

### 1. Backtest Query Benchmark
- **Symbol**: AAPL (or any symbol your producer is generating)
- **Minutes**: 100 (adjust based on how long producer has been running)

This compares querying raw data vs. pre-aggregated rollups.

### 2. Deduplication Benchmark
- **Symbol**: AAPL (same as above)

This shows the difference between raw count (fast but includes duplicates) vs. FINAL count (slower but accurate).

## System Architecture

```
Data Producer (Python) → Kafka → ClickHouse Kafka Engine → Buffer Table → Local Tables
                                                                              ↓
                                                              Materialized Views create:
                                                              - Deduplicated data
                                                              - 1-minute OHLCV rollups
                                                                              ↓
API (FastAPI) queries: ← Dashboard (Streamlit) queries API for visualizations
- Raw tick data
- Aggregated rollups
- Dedup comparisons
```

## Ports

- ClickHouse HTTP: 8123, 8124
- ClickHouse Native: 9000, 9001
- ClickHouse Keeper: 9181, 9444
- Kafka: 9092, 29092
- Zookeeper: 2181
- API: 8000
- Dashboard: 8501
