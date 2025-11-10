-- auto-run everything in order
\include 01_ticks_local.sql
\include 02_ticks_kafka.sql
\include 03_kafka_to_buffer_mv.sql
\include 04_ticks_buffer.sql
\include 05_ticks_all.sql
\include 06_ticks_dedup.sql
\include 07_trades_1m_agg.sql
\include 08_trades_1m_mv.sql
\include 09_local_to_dedup_mv.sql
