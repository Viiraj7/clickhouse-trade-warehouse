-- This Buffer table sits in front of ticks_local.
-- It absorbs high-frequency writes and flushes them to disk in optimal batches.
-- Its schema is identical to ticks_local, so we just use 'AS default.ticks_local'.
CREATE TABLE IF NOT EXISTS default.ticks_buffer ON CLUSTER analytics_cluster
AS default.ticks_local -- Inherit the exact schema from ticks_local
ENGINE = Buffer(
    default,                -- The database to flush to
    'ticks_local',          -- The table to flush to
    16,                     -- num_layers: Parallelism. Default is 16.
    10,                     -- min_time (seconds)
    60,                     -- max_time (seconds)
    10000,                  -- min_rows
    1000000,                -- max_rows
    1048576,                -- min_bytes (1MB)
    10485760                -- max_bytes (10MB)
);
-- This table will flush data to 'ticks_local' if:
-- - It's been 60 seconds (max_time) since the first write.
-- - It has 1,000,000 rows (max_rows).
-- - It has 10MB of data (max_bytes).
-- ...whichever happens first.