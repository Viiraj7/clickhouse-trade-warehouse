# Quick Start Guide - ClickHouse Trade Warehouse

## Prerequisites
- Docker Desktop running
- Python 3.8+ installed
- PowerShell (Windows)

## Complete Setup - Run These Commands

### Step 1: Clean Start
```powershell
docker-compose down -v
docker-compose up -d
```

### Step 2: Wait for Services (60 seconds)
```powershell
Start-Sleep -Seconds 60
```

### Step 3: Verify ClickHouse is Running
```powershell
docker-compose ps
docker exec clickhouse-01 clickhouse-client --query "SELECT 1"
```

### Step 4: Initialize Database Schema (Run these commands one by one)

```powershell
Get-Content sql_schema\01_ticks_local.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\02_ticks_kafka.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\04_ticks_buffer.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\03_kafka_to_buffer_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\05_ticks_all.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\06_ticks_dedup.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\07_trades_1m_agg.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\08_trades_1m_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
Get-Content sql_schema\09_local_to_dedup_mv.sql -Raw | docker exec -i clickhouse-01 clickhouse-client --multiquery
```

### Step 5: Verify Tables Created
```powershell
docker exec clickhouse-01 clickhouse-client --query "SHOW TABLES"
```

You should see:
- kafka_to_buffer_mv
- local_to_dedup_mv
- ticks_all
- ticks_buffer
- ticks_dedup
- ticks_kafka
- ticks_local
- trades_1m_agg
- trades_1m_mv

### Step 6: Start Data Producer (Terminal 1)
```powershell
cd data_producer
pip install -r requirements.txt
python producer.py
```

Keep this running. It will send trade data to Kafka.

### Step 7: Start API Server (Terminal 2)
```powershell
cd api
pip install -r requirements.txt
python -m uvicorn main:app --reload
```

API will be available at: http://localhost:8000/docs

### Step 8: Start Dashboard (Terminal 3)
```powershell
cd dashboard
pip install -r requirements.txt
python -m streamlit run streamlit_app.py
```

Dashboard will open at: http://localhost:8501

##  Testing the Dashboard

1. **Backtest Query Benchmark**:
   - Symbol: `AAPL`
   - Minutes: `100`
   - Click both "Run Slow Query" and "Run Fast Query"
   - Compare the execution times!

2. **Deduplication Benchmark**:
   - Symbol: `AAPL`
   - Click both "Count WITHOUT Final" and "Count WITH Final"
   - See the difference in results and performance!

## Troubleshooting

### If ClickHouse containers keep restarting:
```powershell
docker-compose logs clickhouse-01
docker-compose logs clickhouse-keeper
```

Wait 2-3 more minutes for Keeper to fully start.

### If API shows "Authentication failed":
The API is configured with NO password. Check `api\main.py`:
```python
client = Client(
    host='localhost',
    port=9000,
    user='default',
    password='',  # No password
)
```

### If tables fail to create:
Wait longer (2-3 minutes) for ClickHouse Keeper to be fully ready, then run the schema commands again.

### To start fresh:
```powershell
docker-compose down -v
# Then repeat from Step 1
```

## Project Structure

- `sql_schema/` - ClickHouse table definitions
- `data_producer/` - Python script that generates and sends trade data to Kafka
- `api/` - FastAPI backend that queries ClickHouse
- `dashboard/` - Streamlit dashboard for visualization
- `docker-compose.yml` - Docker services configuration
- `config/clickhouse/` - ClickHouse configuration files

## Architecture

```
Kafka Producer -> Kafka -> ClickHouse Kafka Engine -> 
  Buffer Table -> Local Table (ReplicatedMergeTree) -> 
  Distributed Table (ticks_all) -> API -> Dashboard
```

## Key Features Demonstrated

1. **Real-time data ingestion** from Kafka
2. **Clustered setup** with 2 ClickHouse nodes + Keeper
3. **Materialized views** for real-time aggregations
4. **ReplacingMergeTree** for deduplication
5. **Query performance** comparison (raw vs. pre-aggregated)
6. **TTL** for automatic data cleanup
7. **Buffer tables** for write optimization

Enjoy exploring ClickHouse! 🚀
