-- This Materialized View is the "robot arm" for our deduplication pipeline.
-- It watches the 'ticks_local' table...
CREATE MATERIALIZED VIEW IF NOT EXISTS default.local_to_dedup_mv ON CLUSTER analytics_cluster
TO default.ticks_dedup -- ...and inserts the data INTO our 'ticks_dedup' table.
AS SELECT
    -- It's a simple 1-to-1 copy.
    -- The 'ticks_dedup' table's engine (ReplacingMergeTree)
    -- will handle the actual deduplication logic in the background.
    exchange,
    symbol,
    event_time,
    seq_id,
    event_type,
    price,
    size,
    side,
    source_version
FROM default.ticks_local;