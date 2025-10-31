-- This table is the "connector port" to our Kafka topic.
-- It doesn't store data; it just provides a live stream for the MV to read from.
-- It must be created 'ON CLUSTER' so all nodes are aware of it.
CREATE TABLE IF NOT EXISTS default.ticks_kafka ON CLUSTER analytics_cluster
(
    -- The schema here matches the JSON from our Python producer.
    -- We read everything as simple types (String, UInt64, Float64)
    -- and will parse them (e.g., string to DateTime) in the next step.
    `exchange` String,
    `symbol` String,
    `event_time` String, -- Read as a string first, parse in the MV
    `seq_id` UInt64,
    `event_type` String, -- Read as a string, cast to Enum in the MV
    `price` Float64,
    `size` UInt32,
    `side` String, -- Read as a string, cast to Enum in the MV
    `source_version` UInt64
)
ENGINE = Kafka
SETTINGS
    -- This must match the 'hostname:port' of the Kafka service in docker-compose.yml
    kafka_broker_list = 'kafka:9092',
    
    -- The Kafka topic we are subscribing to
    kafka_topic_list = 'ticks',
    
    -- All ClickHouse nodes will join the same consumer group
    -- This ensures each message is read only once by the cluster
    kafka_group_name = 'clickhouse_ticks_consumer_group',
    
    -- The format of the messages in Kafka (from our Python producer)
    kafka_format = 'JSONEachRow',
    
    -- How many consumers (threads) to run per node
    kafka_num_consumers = 1,
    
    kafka_skip_broken_messages = 1;