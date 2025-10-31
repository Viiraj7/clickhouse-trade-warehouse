-- This table uses ReplicatedReplacingMergeTree to automatically handle duplicates.
-- It stores the *clean* version of our data, keeping only the row with the
-- highest 'source_version' for any given (symbol, seq_id) pair.
CREATE TABLE IF NOT EXISTS default.ticks_dedup ON CLUSTER analytics_cluster
(
    -- The schema is identical to ticks_local
    `exchange` String,
    `symbol` LowCardinality(String),
    `event_time` DateTime64(6, 'UTC'),
    `seq_id` UInt64,
    `event_type` Enum8('trade' = 1, 'quote' = 2, 'book' = 3),
    `price` Float64,
    `size` UInt32,
    `side` Enum8('buy' = 1, 'sell' = 2),
    `source_version` UInt64 -- This column is the "version"
)
ENGINE = ReplicatedReplacingMergeTree(
    '/clickhouse/tables/{shard}/ticks_dedup', -- Keeper path
    '{replica}',                               -- Replica name macro
    source_version                             -- The column to use for versioning
)
PARTITION BY toYYYYMM(event_time)
ORDER BY (symbol, seq_id); -- This is the deduplication key
-- Any rows with the same (symbol, seq_id) will be collapsed
-- to the one with the max(source_version).