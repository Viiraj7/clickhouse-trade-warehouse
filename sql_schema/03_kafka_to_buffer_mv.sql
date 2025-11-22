-- This Materialized View is the "glue" that connects the Kafka pipe to the Buffer table.
-- It runs automatically in the background.
CREATE MATERIALIZED VIEW IF NOT EXISTS default.kafka_to_buffer_mv ON CLUSTER analytics_cluster
TO default.ticks_buffer -- It inserts data INTO the 'ticks_buffer' table (which we'll create next).
AS SELECT
    -- We read the raw string data from ticks_kafka and cast/parse it
    -- into the correct data types defined in our main 'ticks_local' table.
    exchange,
    symbol,
    
    -- parseDateTime64BestEffort is robust for converting string timestamps
    parseDateTime64BestEffort(event_time) AS event_time, 
    
    seq_id,
    
    -- CAST safely converts the string to Enum8
    CAST(event_type AS Enum8('trade' = 1, 'quote' = 2, 'book' = 3)) AS event_type, 
    
    price,
    size,
    
    -- CAST converts 'buy'/'sell' strings to their Enum8 values (1 or 2)
    CAST(side AS Enum8('buy' = 1, 'sell' = 2)) AS side, 
    
    source_version
    
FROM default.ticks_kafka -- It reads data FROM the 'ticks_kafka' table.
WHERE length(symbol) > 0; -- A simple data quality check to filter out empty messages