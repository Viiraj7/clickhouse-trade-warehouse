-- This is the main table on each shard, optimized for backtesting.
-- It uses ReplicatedMergeTree to be cluster-aware and fault-tolerant.
-- The 'ON CLUSTER analytics_cluster' clause ensures this table is created on ALL nodes defined in our cluster.
CREATE TABLE IF NOT EXISTS default.ticks_local ON CLUSTER analytics_cluster
(
    -- === Columns ===
    `exchange` String,                          -- Name of the exchange (e.g., XNAS)
    `symbol` LowCardinality(String),           -- Trading symbol (e.g., AAPL). LowCardinality is good for repeated strings.
    `event_time` DateTime64(6, 'UTC') CODEC(DoubleDelta, ZSTD), -- High-precision timestamp. DoubleDelta+ZSTD is best for timestamps.
    `seq_id` UInt64,                           -- Sequence ID from the feed (used for ordering and identifying original event)
    `event_type` Enum8('trade' = 1, 'quote' = 2, 'book' = 3), -- Type of event (we primarily use 'trade')
    `price` Float64 CODEC(Gorilla, ZSTD),      -- Trade price. Gorilla+ZSTD is best for float time-series.
    `size` UInt32,                             -- Trade size/volume
    `side` Enum8('buy' = 1, 'sell' = 2),       -- Side of the trade (less relevant for raw ticks, but good practice)
    `source_version` UInt64                    -- Increasing version number (used by ReplacingMergeTree later)

    -- === Engine Configuration ===
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/ticks_local', '{replica}')
-- '/clickhouse/tables...' is the path in ClickHouse Keeper where this table's metadata is stored.
-- '{shard}' and '{replica}' are macros automatically filled by ClickHouse based on the node's identity.

-- === Table Settings ===
PARTITION BY toYYYYMM(event_time)           -- Group data into monthly partitions on disk. Good balance for TTL and query speed.
ORDER BY (symbol, event_time, seq_id)      -- CRITICAL FOR BACKTESTING: Data is physically sorted by symbol, then time. Makes symbol+time range queries instant.
TTL toDateTime(event_time) + INTERVAL 30 DAY           -- Automatically delete data older than 30 days.
SETTINGS index_granularity = 8192;         -- Default index granularity, good starting point.