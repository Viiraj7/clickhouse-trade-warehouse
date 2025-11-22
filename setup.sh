#!/bin/bash
# ============================================================================
# Comprehensive Setup Script for ClickHouse Trade Analytics Warehouse
# ============================================================================
# This script will:
# 1. Check prerequisites (Docker, Python)
# 2. Create .env file from .env.example
# 3. Start Docker infrastructure (ClickHouse + Kafka)
# 4. Wait for services to be ready
# 5. Initialize ClickHouse schema
# 6. Install Python dependencies for all services
# 7. Verify the setup
# ============================================================================

set -e  # Exit on error

echo ""
echo "============================================================================"
echo "  ClickHouse Trade Analytics Warehouse - Setup Script"
echo "============================================================================"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Check Prerequisites
echo "[1/8] Checking prerequisites..."
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: Docker is not installed or not in PATH.${NC}"
    echo "Please install Docker from https://docs.docker.com/get-docker/"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Docker found: $(docker --version)"

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}ERROR: docker-compose is not installed or not in PATH.${NC}"
    echo "Please install docker-compose from https://docs.docker.com/compose/install/"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} docker-compose found: $(docker-compose --version)"

# Check Python
if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    echo -e "${RED}ERROR: Python is not installed or not in PATH.${NC}"
    echo "Please install Python 3.8+ from https://www.python.org/downloads/"
    exit 1
fi

# Use python3 if available, otherwise python
if command -v python3 &> /dev/null; then
    PYTHON_CMD=python3
    PIP_CMD=pip3
else
    PYTHON_CMD=python
    PIP_CMD=pip
fi

echo -e "  ${GREEN}✓${NC} Python found: $($PYTHON_CMD --version)"

# Check pip
if ! command -v $PIP_CMD &> /dev/null; then
    echo -e "${RED}ERROR: pip is not installed or not in PATH.${NC}"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} pip found: $($PIP_CMD --version)"
echo ""

# Step 2: Create .env file
echo "[2/8] Creating .env file from template..."
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "  ${GREEN}✓${NC} .env file created"
else
    echo -e "  ${GREEN}✓${NC} .env file already exists"
fi
echo ""

# Step 3: Stop any existing containers
echo "[3/8] Stopping any existing containers..."
docker-compose down 2>/dev/null || true
echo -e "  ${GREEN}✓${NC} Cleanup complete"
echo ""

# Step 4: Start Docker Infrastructure
echo "[4/8] Starting Docker infrastructure (ClickHouse + Kafka)..."
echo "  This may take 1-2 minutes on first run (pulling images)..."
echo ""
if ! docker-compose up -d; then
    echo -e "${RED}ERROR: Failed to start Docker containers.${NC}"
    echo "Please check Docker is running: docker ps"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Docker containers started"
echo ""

# Step 5: Wait for services to be ready
echo "[5/8] Waiting for services to be ready..."
echo "  Waiting for ClickHouse (up to 90 seconds)..."

# Wait for ClickHouse to be ready
CLICKHOUSE_READY=0
for i in {1..45}; do
    if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
        CLICKHOUSE_READY=1
        break
    fi
    sleep 2
done

if [ $CLICKHOUSE_READY -eq 0 ]; then
    echo -e "  ${YELLOW}WARNING: ClickHouse may not be fully ready. Continuing anyway...${NC}"
else
    echo -e "  ${GREEN}✓${NC} ClickHouse is ready"
fi

echo "  Waiting for Kafka (additional 10 seconds)..."
sleep 10
echo -e "  ${GREEN}✓${NC} Services should be ready"
echo ""

# Step 6: Initialize ClickHouse Schema
echo "[6/8] Initializing ClickHouse schema..."

# Wait a bit more for ClickHouse to be fully initialized
sleep 5

echo "  Creating cluster configuration..."
# Run init_cluster.sql
if docker exec clickhouse-01 clickhouse-client --multiquery < config/clickhouse/init_cluster.sql 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Cluster initialized"
else
    echo -e "  ${YELLOW}WARNING: Failed to initialize cluster. Continuing anyway...${NC}"
fi

echo "  Creating analytics tables..."
# Create database
docker exec clickhouse-01 clickhouse-client -q "CREATE DATABASE IF NOT EXISTS default" 2>/dev/null || true

# Run each SQL file individually
for sql_file in sql_schema/*.sql; do
    if [ "$(basename "$sql_file")" != "all.sql" ]; then
        echo "    - Creating $(basename "$sql_file")..."
        if docker exec -i clickhouse-01 clickhouse-client --multiquery < "$sql_file" 2>/dev/null; then
            echo -e "      ${GREEN}✓${NC} Success"
        else
            echo -e "      ${YELLOW}⚠${NC} May have failed (could be expected if table exists)"
        fi
    fi
done
echo -e "  ${GREEN}✓${NC} Schema initialization complete"
echo ""

# Step 7: Install Python Dependencies
echo "[7/8] Installing Python dependencies..."
echo ""

# Create a virtual environment (optional but recommended)
# echo "  Creating virtual environment..."
# $PYTHON_CMD -m venv venv
# source venv/bin/activate

echo "  Installing data_producer dependencies..."
cd data_producer
if $PIP_CMD install -r requirements.txt > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} data_producer dependencies installed"
else
    echo -e "  ${YELLOW}WARNING: Some data_producer dependencies may have failed to install${NC}"
fi
cd ..

echo "  Installing API dependencies..."
cd api
if $PIP_CMD install -r requirements.txt > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} API dependencies installed"
else
    echo -e "  ${YELLOW}WARNING: Some API dependencies may have failed to install${NC}"
fi
cd ..

echo "  Installing dashboard dependencies..."
cd dashboard
if $PIP_CMD install -r requirements.txt > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} dashboard dependencies installed"
else
    echo -e "  ${YELLOW}WARNING: Some dashboard dependencies may have failed to install${NC}"
fi
cd ..
echo ""

# Step 8: Verify Setup
echo "[8/8] Verifying setup..."
echo ""
echo "Docker Containers Status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(NAMES|clickhouse|kafka)"
echo ""

echo "============================================================================"
echo "  Setup Complete!"
echo "============================================================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Start the Data Producer (generates sample trade data):"
echo "   cd data_producer"
echo "   $PYTHON_CMD producer.py"
echo ""
echo "2. Start the API Server (in a new terminal):"
echo "   cd api"
echo "   uvicorn main:app --reload"
echo ""
echo "3. Start the Dashboard (in a new terminal):"
echo "   cd dashboard"
echo "   streamlit run streamlit_app.py"
echo ""
echo "4. Access the dashboard:"
echo "   Open http://localhost:8501 in your browser"
echo ""
echo "5. Access the API docs:"
echo "   Open http://localhost:8000/docs in your browser"
echo ""
echo "Services:"
echo "  - ClickHouse HTTP: http://localhost:8123"
echo "  - ClickHouse Native: localhost:9000"
echo "  - Kafka: localhost:29092"
echo "  - API Server: http://localhost:8000"
echo "  - Dashboard: http://localhost:8501"
echo ""
echo "============================================================================"
echo ""
