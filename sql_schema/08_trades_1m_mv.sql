-- This Materialized View is the "robot arm" for our rollups.
-- It watches the 'ticks_local' table...
CREATE MATERIALIZED VIEW IF NOT EXISTS default.trades_1m_mv ON CLUSTER analytics_cluster
TO default.trades_1m_agg -- ...and inserts the calculated rollups INTO 'trades_1m_agg'.
AS SELECT
    symbol,
    
    -- Group all timestamps into 1-minute buckets
    toStartOfMinute(event_time) AS minute,
    
    -- We use the '...State' aggregate functions.
    -- These create the lightweight intermediate states that
    -- are stored in the 'trades_1m_agg' table.
    
    -- Get the price (arg) at the minimum event_time (Min)
    argMinState(price, event_time) AS open,
    
    -- Get the maximum price
    maxState(price) AS high,
    
    -- Get the minimum price
    minState(price) AS low,
    
    -- Get the price (arg) at the maximum event_time (Max)
    argMaxState(price, event_time) AS close,
    
    -- Get the sum of all trade sizes
    sumState(size) AS volume,
    
    -- Get the sum of (price * size), which we'll use to calculate VWAP
    sumState(price * size) AS vwap_pv

-- We read FROM our main 'ticks_local' table
FROM default.ticks_local

-- We only want to aggregate actual trades, not quotes or other events
WHERE event_type = 'trade'

-- We group by the 1-minute bucket and the symbol
GROUP BY symbol, minute;