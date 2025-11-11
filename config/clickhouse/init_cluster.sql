CREATE DATABASE IF NOT EXISTS analytics;

CREATE TABLE IF NOT EXISTS analytics.ticks ON CLUSTER analytics_cluster
(
    event_time      DateTime64(6),
    exchange        String,
    symbol          String,
    event_type      String,
    price           Float64,
    size            UInt32,
    side            String,
    seq_id          UInt64,
    source_version  UInt64
)
ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/ticks', '{replica}', source_version)
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (symbol, event_time, seq_id);
