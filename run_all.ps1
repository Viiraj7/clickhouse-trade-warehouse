# PowerShell script to run the entire cold path pipeline
# Run: .\run_all.ps1

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Starting Cold Path Pipeline" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 1: Check Docker
Write-Host "`n[1/5] Checking Docker containers..." -ForegroundColor Yellow
$containers = docker-compose ps --format json | ConvertFrom-Json
$healthy = ($containers | Where-Object { $_.Health -eq "healthy" }).Count
$total = $containers.Count

if ($healthy -lt $total) {
    Write-Host "  Warning: Not all containers are healthy" -ForegroundColor Yellow
    Write-Host "  Run: docker-compose up -d" -ForegroundColor Yellow
} else {
    Write-Host "  [OK] All containers are healthy" -ForegroundColor Green
}

# Step 2: Initialize Schema (if needed)
Write-Host "`n[2/5] Initializing ClickHouse schema..." -ForegroundColor Yellow
Write-Host "  Run: .\init_clickhouse_windows.ps1" -ForegroundColor Cyan
Write-Host "  (Press Enter to skip or run manually)" -ForegroundColor Gray
$null = Read-Host

# Step 3: Start Producer
Write-Host "`n[3/5] Starting data producer..." -ForegroundColor Yellow
Write-Host "  Starting in new window..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD\data_producer'; python producer.py"

Start-Sleep -Seconds 3

# Step 4: Start API
Write-Host "`n[4/5] Starting API server..." -ForegroundColor Yellow
Write-Host "  Starting in new window..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD\api'; python -m uvicorn main:app --reload"

Start-Sleep -Seconds 5

# Step 5: Start Dashboard
Write-Host "`n[5/5] Starting Streamlit dashboard..." -ForegroundColor Yellow
Write-Host "  Starting in new window..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD\dashboard'; streamlit run streamlit_app.py"

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "All services started!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "`nAccess points:" -ForegroundColor Yellow
Write-Host "  - Dashboard: http://localhost:8501" -ForegroundColor Cyan
Write-Host "  - API: http://localhost:8000" -ForegroundColor Cyan
Write-Host "  - API Docs: http://localhost:8000/docs" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. Wait 5-10 minutes for data to accumulate" -ForegroundColor Gray
Write-Host "  2. Open dashboard and run benchmarks" -ForegroundColor Gray
Write-Host "  3. Run test_queries.py to test all queries" -ForegroundColor Gray
Write-Host "`nPress any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

