#!/usr/bin/env python3
"""
ClickHouse Schema Initialization Script

This script initializes all tables, views, and materialized views
required for the cold path data pipeline.

Run this script after starting Docker containers:
    python init_clickhouse.py
"""

import os
import sys
from pathlib import Path
from clickhouse_driver import Client

# Configuration
CLICKHOUSE_HOST = os.environ.get("CLICKHOUSE_HOST", "localhost")
# Use native TCP port (9000) for clickhouse-driver, not HTTP port (8123)
CLICKHOUSE_PORT = int(os.environ.get("CLICKHOUSE_PORT", 9000))
CLICKHOUSE_DB = "default"

# SQL files in order
SQL_FILES = [
    "sql_schema/01_ticks_local.sql",
    "sql_schema/02_ticks_kafka.sql",
    "sql_schema/04_ticks_buffer.sql",  # Buffer must be created before the MV
    "sql_schema/03_kafka_to_buffer_mv.sql",
    "sql_schema/05_ticks_all.sql",
    "sql_schema/06_ticks_dedup.sql",
    "sql_schema/07_trades_1m_agg.sql",
    "sql_schema/08_trades_1m_mv.sql",
    "sql_schema/09_local_to_dedup_mv.sql",
]


def read_sql_file(filepath: str) -> str:
    """Read SQL file content."""
    path = Path(filepath)
    if not path.exists():
        raise FileNotFoundError(f"SQL file not found: {filepath}")
    return path.read_text(encoding="utf-8")


def execute_sql(client: Client, sql: str, description: str):
    """Execute SQL and handle errors."""
    print(f"\n[INFO] {description}...")
    try:
        # Remove comments and split by semicolon
        lines = sql.split('\n')
        cleaned_lines = []
        for line in lines:
            # Remove full-line comments
            stripped = line.strip()
            if stripped and not stripped.startswith("--"):
                # Remove inline comments (everything after --)
                if "--" in line:
                    comment_pos = line.find("--")
                    cleaned_lines.append(line[:comment_pos].rstrip())
                else:
                    cleaned_lines.append(line)
        
        # Join and split by semicolon
        full_sql = " ".join(cleaned_lines)
        statements = [s.strip() for s in full_sql.split(";") if s.strip() and s.strip() != ""]
        
        for i, statement in enumerate(statements, 1):
            if statement:
                # Execute each statement
                client.execute(statement)
                if len(statements) > 1:
                    print(f"  [OK] Statement {i}/{len(statements)} executed")
        
        print(f"  [SUCCESS] {description}")
        return True
    except Exception as e:
        print(f"  [FAILED] {description} - {e}")
        # Print the problematic SQL for debugging
        if "ON CLUSTER" in sql:
            print(f"  Note: This statement uses ON CLUSTER - make sure cluster is configured correctly")
        return False


def main():
    """Main initialization function."""
    print("=" * 60)
    print("ClickHouse Schema Initialization")
    print("=" * 60)
    print(f"Connecting to ClickHouse at {CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}...")
    
    try:
        client = Client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DB,
            user='default',
            password=''  # Empty password for default user
        )
        
        # Test connection
        result = client.execute("SELECT 1")
        print("[OK] Connected to ClickHouse!")
        
    except Exception as e:
        print(f"[ERROR] Failed to connect to ClickHouse: {e}")
        print("\nMake sure Docker containers are running:")
        print("  docker-compose up -d")
        print("\nNote: Using native TCP port 9000 (not HTTP port 8123)")
        sys.exit(1)
    
    # Get the project root directory
    project_root = Path(__file__).parent
    
    # Execute SQL files in order
    success_count = 0
    failed_files = []
    
    for sql_file in SQL_FILES:
        filepath = project_root / sql_file
        if not filepath.exists():
            print(f"\n⚠️  Warning: {sql_file} not found, skipping...")
            continue
        
        sql_content = read_sql_file(filepath)
        description = f"Creating {Path(sql_file).stem}"
        
        if execute_sql(client, sql_content, description):
            success_count += 1
        else:
            failed_files.append(sql_file)
    
    # Summary
    print("\n" + "=" * 60)
    print("Initialization Summary")
    print("=" * 60)
    print(f"[OK] Successfully executed: {success_count}/{len(SQL_FILES)}")
    
    if failed_files:
        print(f"[ERROR] Failed files: {len(failed_files)}")
        for f in failed_files:
            print(f"   - {f}")
        sys.exit(1)
    else:
        print("\n[SUCCESS] All tables and views created successfully!")
        print("\nNext steps:")
        print("1. Start the data producer: cd data_producer && python producer.py")
        print("2. Start the API: cd api && uvicorn main:app --reload")
        print("3. Start the dashboard: cd dashboard && streamlit run streamlit_app.py")


if __name__ == "__main__":
    main()

