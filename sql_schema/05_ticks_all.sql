-- This is the "Front Door" table that our API and dashboard will query.
-- It's a Distributed table that provides a single, unified view across
-- all shards in our 'analytics_cluster'.
CREATE TABLE IF NOT EXISTS default.ticks_all ON CLUSTER analytics_cluster
AS default.ticks_local -- It uses the same schema as our local tables.
ENGINE = Distributed(
    analytics_cluster, -- The name of the cluster (from metrika.xml).
    'default',         -- The database where the local tables live.
    'ticks_local',     -- The name of the local tables to query.
    rand()             -- The sharding key (rand() = distribute writes randomly).
);