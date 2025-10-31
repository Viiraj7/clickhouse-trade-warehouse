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

(These are placeholder values. You will run the dashboard and fill in your *real* results in `results/benchmark.csv`.)

| Query Type | SQL Table | Rows Scanned (Approx) | Query Time (ms) | Speedup |
| :--- | :--- | :--- | :--- | :--- |
| **"Slow Query"** | `ticks_all` (Raw Scan) | ~1,000,000 | **~8245 ms** | 1x |
| **"Fast Query"** | `trades_1m_agg` (Rollup) | ~100 | **~45 ms** | **~183x** |

### Deduplication Benchmark

This shows the performance trade-off of using `FINAL` on a `ReplacingMergeTree`.

| Query | Purpose | Query Time (ms) | Result (Rows) |
| :--- | :--- | :--- | :--- |
| `COUNT()` | Fast, but shows duplicates | ~75 ms | 10,500,000 |
| `COUNT() FINAL` | Slow, but 100% accurate | ~950 ms | 10,000,000 |

## 🛠️ How to Run

1.  **Start Infrastructure:**
    ```bash
    docker-compose up -d
    ```
    *(Wait 1-2 minutes for ClickHouse and Kafka to start.)*

2.  **Start Data Producer:**
    ```bash
    # (In a new terminal)
    cd data_producer
    pip install -r requirements.txt
    python producer.py
    ```

3.  **Start API Server:**
    ```bash
    # (In a new terminal)
    cd api
    pip install -r requirements.txt
    uvicorn main:app --reload
    ```

4.  **Start Dashboard:**
    ```bash
    # (In a new terminal)
    cd dashboard
    pip install -r requirements.txt
    streamlit run streamlit_app.py
    ```

5.  **Open the Dashboard:**
    Open `http://localhost:8501` in your browser.

6.  **Explore (Optional):**
    Open `notebooks/exploration.ipynb` in VS Code or Jupyter Lab to run ad-hoc queries.