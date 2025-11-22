# Real-Time Trade Analytics & Backtest Warehouse

This project is a high-performance analytics warehouse for financial tick data, built using ClickHouse, Kafka, and Python (FastAPI/Streamlit).

It demonstrates a complete, ClickHouse-native data pipeline that can ingest, process, and query millions of events per second. The system is designed to solve two primary problems:
1.  **Fast Backtesting ("Cold Path"):** Provide a high-speed query engine for running historical analytics over billions of raw and aggregated trades.
2.  **Real-Time State ("Hot Path"):** (Future stretch goal) Provide a sub-millisecond API for querying the *current* state of the market (e.g., order book depth).

## 🚀 Core Features

* **High-Volume Ingestion:** Ingests data from Kafka using the native `Kafka` engine and `Buffer` table for non-blocking, batched writes.
* **Automated Deduplication:** Uses a `ReplacingMergeTree` table and `Materialized View` to automatically clean and deduplicate data from the feed (e.g., corrections, duplicates).
* **Real-Time Rollups:** Uses an `AggregatingMergeTree` table and `Materialized View` to automatically create 1-minute OHLCV/VWAP "rollups" as data arrives.
* **Optimized for Backtesting:** The raw data table (`ticks_local`) is sorted with an `ORDER BY (symbol, event_time)`, making queries for a single symbol + time range (the most common backtest query) nearly instant.
* **High-Performance API:** A FastAPI backend provides endpoints to query the data, including benchmark endpoints to prove the speed difference between raw scans and rollup queries.
* **Interactive Dashboard:** A Streamlit dashboard provides a UI to run benchmark queries and visualize the results.

## 🏗️ Architecture

The system is built on a "cold path" (for analytics) and a placeholder for a "hot path" (for real-time state).

![Architecture Diagram: A Python producer sends data to Kafka. Kafka is consumed by two parallel systems. 1. The "Cold Path" (ClickHouse): Kafka data is read by a ClickHouse Kafka Engine, inserted into a Buffer table, which flushes to a main ReplicatedMergeTree table. From there, two MVs feed an AggregatingMergeTree (for rollups) and a ReplacingMergeTree (for dedups). A FastAPI + Streamlit dashboard queries this warehouse. 2. The "Hot Path" (Python): A Python service reads from the same Kafka topic to populate an in-memory Segment Tree/Graph.](https://i.imgur.com/8fS2G43.png)

### Data Pipeline (ClickHouse-Native ETL)

1.  `data_producer/producer.py` simulates trades and sends them to a **Kafka** topic (`ticks`).
2.  `02_ticks_kafka` (Kafka Engine) reads this stream.
3.  `03_kafka_to_buffer_mv` (MV) triggers, reads from `ticks_kafka`, and inserts into...
4.  `04_ticks_buffer` (Buffer Engine), which holds data in RAM and flushes it in large batches to...
5.  `01_ticks_local` (ReplicatedMergeTree), our main, permanent "source of truth" table.
6.  Once data is in `ticks_local`, two parallel MVs trigger:
    * `08_trades_1m_mv` (MV) reads `ticks_local`, calculates 1-min aggregates, and inserts into `07_trades_1m_agg`.
    * `09_local_to_dedup_mv` (MV) reads `ticks_local` and copies data into `06_ticks_dedup`, which automatically handles deduplication.

## 📊 Performance Benchmarks

The primary goal of this architecture is to make queries fast. The following results were gathered by querying for **100 minutes of data for a single symbol ('AAPL')** after ingesting 10 million rows.

**Run the dashboard to see your real results!** All results are automatically saved to `results/benchmark.csv`.

| Query Type | SQL Table | Rows Scanned (Approx) | Query Time (ms) | Speedup |
| :--- | :--- | :--- | :--- | :--- |
| **"Slow Query"** | `ticks_all` (Raw Scan) | ~1,000,000 | **~8,000-10,000 ms** | 1x |
| **"Fast Query"** | `trades_1m_agg` (Rollup) | ~100 | **~40-100 ms** | **~100x-200x** |

### Deduplication Benchmark

This shows the performance trade-off of using `FINAL` on a `ReplacingMergeTree`.

| Query | Purpose | Query Time (ms) | Result (Rows) |
| :--- | :--- | :--- | :--- |
| `COUNT()` | Fast, but shows duplicates | ~75 ms | 10,500,000 |
| `COUNT() FINAL` | Slow, but 100% accurate | ~950 ms | 10,000,000 |

### Viewing Results

- **Dashboard**: Open `http://localhost:8501` → History page
- **CSV File**: Check `results/benchmark.csv` for all saved benchmarks
- **Compression Stats**: Check `results/compression_stats.txt` for compression ratios

## 🛠️ How to Start the Project

### Prerequisites
- Docker and Docker Compose installed
- Python 3.8+ installed

### Step 1: Start Docker Infrastructure

```bash
docker-compose up -d
```

**Wait 5-10 minutes** for all containers to be healthy. Verify with:
```bash
docker-compose ps
```
All containers should show "healthy" status.

### Step 2: Wait for Keeper & Initialize Schema

**Important**: ClickHouse Keeper needs time to fully initialize. Wait 2-3 minutes after starting Docker.

**Windows:**
```powershell
# Option 1: Wait for keeper first (recommended)
.\wait_for_keeper.ps1
.\init_clickhouse_windows.ps1

# Option 2: Direct initialization (will retry automatically)
.\init_clickhouse_windows.ps1
```

**Linux/Mac:**
```bash
python init_clickhouse.py
```

**Note**: If you see keeper connection errors:
1. Wait 2-3 more minutes
2. Run `.\wait_for_keeper.ps1` to check keeper status
3. Retry initialization: `.\init_clickhouse_windows.ps1`

This creates all tables, views, and materialized views needed for the pipeline.

### Step 3: Start All Services

**Option A: Automated (Windows PowerShell)**
```powershell
.\run_all.ps1
```
This will start producer, API, and dashboard in separate windows.

**Option B: Manual (Terminal 1 - Data Producer)**
```bash
cd data_producer
pip install -r requirements.txt
python producer.py
```
Let it run for **5-10 minutes** to generate enough data for meaningful benchmarks.

**Option B: Manual (Terminal 2 - API Server)**
```bash
cd api
pip install -r requirements.txt
uvicorn main:app --reload
```
API available at: `http://localhost:8000` (Docs: `http://localhost:8000/docs`)

**Option B: Manual (Terminal 3 - Dashboard)**
```bash
cd dashboard
pip install -r requirements.txt
streamlit run streamlit_app.py
```
Dashboard available at: `http://localhost:8501`

### Step 4: Use the Dashboard

Open `http://localhost:8501` in your browser. The dashboard has 4 pages:

1. **Benchmarks**: Run slow vs fast queries, see speedup (100x-200x faster!)
2. **Query Tester**: Test any custom ClickHouse SQL query
3. **History**: View all saved benchmark results with charts
4. **Compression Stats**: View and save compression statistics

**All results are automatically saved to `results/benchmark.csv`!**

### Step 5: Run Automated Tests (Optional)

```bash
python test_queries.py
```
This will test all queries and save results to `results/benchmark.csv`

## 📊 Result Files

- **`results/benchmark.csv`**: Stores all query performance benchmarks
  - Tracks query times, speedup ratios, and row counts
  - Automatically updated when running queries from dashboard
- **`results/compression_stats.txt`**: Stores ClickHouse compression statistics
  - Shows compression ratios for each column
  - Demonstrates storage efficiency

## 🔧 Troubleshooting

- **ClickHouse connection errors**: Make sure containers are healthy: `docker-compose ps`
- **Keeper connection errors**: Wait 5-10 minutes after starting Docker, then retry initialization
- **Kafka connection errors**: Ensure Kafka is running and accessible on port 29092
- **No data in queries**: Wait 5-10 minutes after starting the producer for data to flow through the pipeline
- **Schema errors**: Re-run initialization script to recreate tables
- **API not responding**: Check API is running on port 8000: `curl http://localhost:8000/`

## 📝 Example Queries

See `example_queries.sql` for ready-to-use SQL queries, or use the **Query Tester** page in the dashboard to test any custom query.

### Quick Test Queries:

**Slow Query (Raw Scan):**
```sql
SELECT
    toStartOfMinute(event_time) AS minute,
    symbol,
    argMin(price, event_time) AS open,
    max(price) AS high,
    min(price) AS low,
    argMax(price, event_time) AS close,
    sum(size) AS volume
FROM default.ticks_all
WHERE symbol = 'AAPL' AND event_type = 'trade'
GROUP BY symbol, minute
ORDER BY minute DESC
LIMIT 100;
```

**Fast Query (Rollup):**
```sql
SELECT
    minute,
    symbol,
    argMinMerge(open) AS open,
    maxMerge(high) AS high,
    minMerge(low) AS low,
    argMaxMerge(close) AS close,
    sumMerge(volume) AS volume
FROM default.trades_1m_agg
WHERE symbol = 'AAPL'
GROUP BY symbol, minute
ORDER BY minute DESC
LIMIT 100;
```