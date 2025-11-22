# ClickHouse Trade Warehouse - Shutdown Script
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Stopping ClickHouse Trade Warehouse" -ForegroundColor Yellow
Write-Host "============================================`n" -ForegroundColor Cyan

# Step 1: Stop Python processes (API, Dashboard, Producer)
Write-Host "Step 1: Stopping Python services..." -ForegroundColor Yellow
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "✅ All Python services stopped" -ForegroundColor Green

# Step 2: Stop Docker containers
Write-Host "`nStep 2: Stopping Docker containers..." -ForegroundColor Yellow
docker-compose down
Write-Host "✅ Docker containers stopped" -ForegroundColor Green

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  ✅ SHUTDOWN COMPLETE" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Cyan
Write-Host "💡 Tip: Data is preserved in Docker volumes." -ForegroundColor Gray
Write-Host "    Run START_PROJECT.ps1 to resume.`n" -ForegroundColor Gray
