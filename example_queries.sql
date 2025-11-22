-- ============================================================
-- EXAMPLE QUERIES FOR TESTING THE COLD PATH
-- ============================================================
-- Run these queries using:
-- docker exec clickhouse-01 clickhouse-client --query "YOUR_QUERY_HERE"
-- Or use the clickhouse-client interactively:
-- docker exec -it clickhouse-01 clickhouse-client

-- ============================================================
-- 1. BASIC CHECKS
-- ============================================================

-- Check if tables exist
SHOW TABLES;

-- Count rows in each table
SELECT 'ticks_local' AS table_name, count() AS row_count FROM default.ticks_local
UNION ALL
SELECT 'ticks_buffer', count() FROM default.ticks_buffer
UNION ALL
SELECT 'ticks_dedup', count() FROM default.ticks_dedup
UNION ALL
SELECT 'trades_1m_agg', count() FROM default.trades_1m_agg
UNION ALL
SELECT 'ticks_all', count() FROM default.ticks_all;

-- ============================================================
-- 2. SLOW QUERY - Raw Scan (Backtesting)
-- ============================================================
-- This query scans the raw ticks_all table and calculates
-- 1-minute OHLCV aggregates on the fly.
-- EXPECTED TIME: 8-10 seconds for 10M rows

SELECT
    toStartOfMinute(event_time) AS minute,
    symbol,
    argMin(price, event_time) AS open,
    max(price) AS high,
    min(price) AS low,
    argMax(price, event_time) AS close,
    sum(size) AS volume,
    sum(price * size) / sum(size) AS vwap
FROM default.ticks_all
WHERE symbol = 'AAPL' AND event_type = 'trade'
GROUP BY symbol, minute
ORDER BY minute DESC
LIMIT 100;

-- ============================================================
-- 3. FAST QUERY - Pre-aggregated Rollup
-- ============================================================
-- This query reads from the pre-calculated trades_1m_agg table.
-- EXPECTED TIME: 40-100ms for same result
-- SPEEDUP: 100x-200x faster!

SELECT
    minute,
    symbol,
    argMinMerge(open) AS open,
    maxMerge(high) AS high,
    minMerge(low) AS low,
    argMaxMerge(close) AS close,
    sumMerge(volume) AS volume,
    sumMerge(vwap_pv) / sumMerge(volume) AS vwap
FROM default.trades_1m_agg
WHERE symbol = 'AAPL'
GROUP BY symbol, minute
ORDER BY minute DESC
LIMIT 100;

-- ============================================================
-- 4. DEDUPLICATION TEST
-- ============================================================

-- Fast count (may include duplicates)
-- EXPECTED TIME: ~75ms
SELECT count() AS raw_count FROM default.ticks_dedup WHERE symbol = 'AAPL';

-- Accurate count (forces deduplication with FINAL)
-- EXPECTED TIME: ~950ms
SELECT count() AS final_count FROM default.ticks_dedup FINAL WHERE symbol = 'AAPL';

-- Compare both
SELECT 
    (SELECT count() FROM default.ticks_dedup WHERE symbol = 'AAPL') AS raw_count,
    (SELECT count() FROM default.ticks_dedup FINAL WHERE symbol = 'AAPL') AS final_count,
    raw_count - final_count AS duplicates_removed;

-- ============================================================
-- 5. DATA INGESTION PIPELINE STATUS
-- ============================================================

-- Check Kafka table (should be 0 or very low - data flows through quickly)
SELECT 'Kafka' AS stage, count() AS row_count FROM default.ticks_kafka
UNION ALL
-- Check Buffer (should be low - flushes every 60 seconds or 1M rows)
SELECT 'Buffer', count() FROM default.ticks_buffer
UNION ALL
-- Check main table (should have most data)
SELECT 'Local (Main)', count() FROM default.ticks_local
UNION ALL
-- Check if rollups are being created
SELECT 'Rollups (1m)', count() FROM default.trades_1m_agg
UNION ALL
-- Check deduplication table
SELECT 'Dedup', count() FROM default.ticks_dedup;

-- ============================================================
-- 6. SAMPLE DATA EXPLORATION
-- ============================================================

-- Latest 10 trades
SELECT * FROM default.ticks_local 
WHERE symbol = 'AAPL' 
ORDER BY event_time DESC 
LIMIT 10;

-- Price statistics by symbol
SELECT 
    symbol,
    min(price) AS min_price,
    max(price) AS max_price,
    avg(price) AS avg_price,
    count() AS trade_count
FROM default.ticks_local
WHERE event_type = 'trade'
GROUP BY symbol
ORDER BY trade_count DESC;

-- Volume by symbol
SELECT 
    symbol,
    sum(size) AS total_volume,
    count() AS trade_count,
    sum(size) / count() AS avg_trade_size
FROM default.ticks_local
WHERE event_type = 'trade'
GROUP BY symbol
ORDER BY total_volume DESC;

-- ============================================================
-- 7. TIME-BASED QUERIES (Backtesting Scenarios)
-- ============================================================

-- Get data for a specific time range (SLOW - raw scan)
SELECT
    toStartOfMinute(event_time) AS minute,
    symbol,
    argMin(price, event_time) AS open,
    max(price) AS high,
    min(price) AS low,
    argMax(price, event_time) AS close,
    sum(size) AS volume
FROM default.ticks_all
WHERE symbol = 'AAPL' 
    AND event_type = 'trade'
    AND event_time >= now() - INTERVAL 1 HOUR
    AND event_time < now()
GROUP BY symbol, minute
ORDER BY minute;

-- Same query but FAST (using rollups)
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
    AND minute >= now() - INTERVAL 1 HOUR
    AND minute < now()
GROUP BY symbol, minute
ORDER BY minute;

-- ============================================================
-- 8. PERFORMANCE COMPARISON
-- ============================================================
-- Run these with --time flag to see execution time:
-- docker exec clickhouse-01 clickhouse-client --query "QUERY" --time

-- Example:
-- docker exec clickhouse-01 clickhouse-client --query "
-- SELECT count() FROM default.ticks_all WHERE symbol = 'AAPL'
-- " --time

-- ============================================================
-- 9. CHECK FOR CORRECTIONS/DEDUPLICATION
-- ============================================================

-- Find rows with same seq_id but different source_version
-- (These are corrections that should be deduplicated)
SELECT 
    symbol,
    seq_id,
    count() AS version_count,
    min(source_version) AS min_version,
    max(source_version) AS max_version
FROM default.ticks_dedup
GROUP BY symbol, seq_id
HAVING version_count > 1
ORDER BY version_count DESC
LIMIT 10;

-- ============================================================
-- 10. VWAP (Volume-Weighted Average Price) Analysis
-- ============================================================

-- VWAP by symbol (from rollups - FAST)
SELECT
    symbol,
    sum(sumMerge(vwap_pv)) / sum(sumMerge(volume)) AS overall_vwap,
    sum(sumMerge(volume)) AS total_volume
FROM default.trades_1m_agg
GROUP BY symbol
ORDER BY total_volume DESC;

-- VWAP by symbol (from raw data - SLOW)
SELECT
    symbol,
    sum(price * size) / sum(size) AS overall_vwap,
    sum(size) AS total_volume
FROM default.ticks_all
WHERE event_type = 'trade'
GROUP BY symbol
ORDER BY total_volume DESC;

