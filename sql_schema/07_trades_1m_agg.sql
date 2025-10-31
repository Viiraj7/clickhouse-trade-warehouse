-- This table uses AggregatingMergeTree to store pre-calculated "states".
-- This makes querying 1-minute OHLCV/VWAP data almost instantaneous.
CREATE TABLE IF NOT EXISTS default.trades_1m_agg ON CLUSTER analytics_cluster
(
    `symbol` LowCardinality(String),
    `minute` DateTime('UTC'), -- The 1-minute bucket timestamp

    -- We use special AggregateFunction data types to store the intermediate states.
    -- This is the "magic" of AggregatingMergeTree.
    
    -- argMinState stores the 'price' (arg) with the 'event_time' (Min)
    `open` AggregateFunction(argMin, Float64, DateTime64(6, 'UTC')),
    
    -- maxState stores the max 'price'
    `high` AggregateFunction(max, Float64),
    
    -- minState stores the min 'price'
    `low` AggregateFunction(min, Float64),
    
    -- argMaxState stores the 'price' (arg) with the 'event_time' (Max)
    `close` AggregateFunction(argMax, Float64, DateTime64(6, 'UTC')),
    
    -- sumState stores the sum of 'size'
    `volume` AggregateFunction(sum, UInt32),
    
    -- We store the sum of (price * size) to calculate VWAP later.
    `vwap_pv` AggregateFunction(sum, Float64)
)
ENGINE = ReplicatedAggregatingMergeTree(
    '/clickhouse/tables/{shard}/trades_1m_agg', -- Keeper path
    '{replica}'                                  -- Replica name macro
)
PARTITION BY toYYYYMM(minute)
ORDER BY (symbol, minute)
TTL minute + INTERVAL 2 YEAR; -- Keep these rollups for 2 years (much longer than raw data)