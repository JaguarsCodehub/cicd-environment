param (
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment,
    [switch]$Status,
    [switch]$TearDown,
    [switch]$Rebuild
)

$ErrorActionPreference = "Stop"

function Show-Header {
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host "   CI/CD MULTI-ENVIRONMENT ORCHESTRATION CLI     " -ForegroundColor Cyan
    Write-Host "=================================================`n" -ForegroundColor Cyan
}

function Check-EnvStatus {
    param([string]$Name, [int]$Port)
    $url = "http://localhost:$Port/health"
    try {
        $res = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 2 -ErrorAction Stop
        $info = Invoke-RestMethod -Uri "http://localhost:$Port/api/v1/info" -Method Get -TimeoutSec 2 -ErrorAction Stop
        Write-Host "[$Name] (Port $Port): " -NoNewline
        Write-Host "HEALTHY" -ForegroundColor Green -NoNewline
        Write-Host " | Env: $($info.environment) | Commit: $($info.commitSha) | DB: $($info.databaseHost) ($($info.databaseStatus))"
    } catch {
        Write-Host "[$Name] (Port $Port): " -NoNewline
        Write-Host "OFFLINE / UNREACHABLE" -ForegroundColor DarkGray
    }
}

Show-Header

if ($Status) {
    Write-Host "Inspecting Environment Status across all tiers:`n" -ForegroundColor Yellow
    Check-EnvStatus -Name "Development" -Port 3001
    Check-EnvStatus -Name "Staging    " -Port 3002
    Check-EnvStatus -Name "Production " -Port 3000
    Write-Host ""
    exit 0
}

if ($TearDown) {
    Write-Host "[TEARDOWN] Stopping all environment containers and tearing down volumes..." -ForegroundColor Yellow
    docker compose --profile dev --profile staging --profile prod down -v
    Write-Host "[TEARDOWN] All environments stopped successfully.`n" -ForegroundColor Green
    exit 0
}

if (-not $Environment) {
    Write-Host "Usage: .\scripts\deploy-env.ps1 -Environment <dev|staging|prod> [-Rebuild]" -ForegroundColor Red
    Write-Host "       .\scripts\deploy-env.ps1 -Status"
    Write-Host "       .\scripts\deploy-env.ps1 -TearDown"
    exit 1
}

# Mapping environment details
$ports = @{
    "dev" = 3001
    "staging" = 3002
    "prod" = 3000
}
$targetPort = $ports[$Environment]

# Production manual approval gate simulation
if ($Environment -eq "prod") {
    Write-Host "=================================================" -ForegroundColor Magenta
    Write-Host " [GATE] PRODUCTION ENVIRONMENT APPROVAL REQUIRED  " -ForegroundColor Magenta
    Write-Host "=================================================" -ForegroundColor Magenta
    Write-Host "Target: Production (:3000)"
    Write-Host "Branch: main"
    Write-Host "Verification: Requires explicit operator authorization." -ForegroundColor Yellow
    
    $confirmation = Read-Host "Approve and promote to PRODUCTION? (type 'yes' to proceed)"
    if ($confirmation -ne "yes") {
        Write-Host "`n[GATE DENIED] Production deployment cancelled by reviewer.`n" -ForegroundColor Red
        exit 1
    }
    Write-Host "`n[GATE APPROVED] Authorized by operator. Commencing rollout...`n" -ForegroundColor Green
}

Write-Host "[DEPLOY] Deploying tier '$Environment' on port $targetPort..." -ForegroundColor Cyan

$buildArg = if ($Rebuild) { "--build" } else { "" }

docker compose --profile $Environment up -d $buildArg

Write-Host "`n[WAIT] Waiting for container health probe readiness..." -ForegroundColor Yellow
$healthy = $false
$maxAttempts = 15

for ($i = 1; $i -le $maxAttempts; $i++) {
    Start-Sleep -Seconds 2
    try {
        $res = Invoke-RestMethod -Uri "http://localhost:$targetPort/health" -Method Get -TimeoutSec 2 -ErrorAction Stop
        if ($res.status -eq "healthy") {
            $healthy = $true
            break
        }
    } catch {
        Write-Host "  Attempt $i/$maxAttempts: Waiting for http://localhost:$targetPort/health..."
    }
}

if (-not $healthy) {
    Write-Host "`n[ERROR] Healthcheck timed out on port $targetPort" -ForegroundColor Red
    docker compose --profile $Environment logs --tail 50
    exit 1
}

Write-Host "`n[SUCCESS] Tier '$Environment' is online and healthy on http://localhost:$targetPort!`n" -ForegroundColor Green

# Automated post-deployment smoke test
Write-Host "[VERIFY] Running automated post-deployment smoke verification suite..." -ForegroundColor Cyan
node scripts/smoke-test.js "http://localhost:$targetPort"
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ROLLBACK WARNING] Post-deployment verification failed!" -ForegroundColor Red
    exit 1
}

Write-Host "`n>>> Deployment completed and verified successfully for [$Environment] <<<\n" -ForegroundColor Green
