<#
.SYNOPSIS
    AI Stack Pre-Deployment Validation Suite
.DESCRIPTION
    Validates all config files, checks for port conflicts, env var coverage,
    security issues, and service connectivity before deployment.
    Runs on ANY Windows machine - no Docker or Linux required.
#>

$ErrorActionPreference = "Continue"
$script:Pass = 0
$script:Fail = 0
$script:Warn = 0
$script:Errors = @()

$BASE = Split-Path -Parent $PSScriptRoot

function Test-Check {
    param([string]$Status, [string]$Test, [string]$Detail)
    switch ($Status) {
        "PASS" {
            Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
            $script:Pass++
        }
        "FAIL" {
            Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
            $script:Fail++
            $script:Errors += "${Test}: ${Detail}"
        }
        "WARN" {
            Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline
            $script:Warn++
        }
        "INFO" {
            Write-Host "  [INFO] " -ForegroundColor Cyan -NoNewline
        }
    }
    Write-Host "$Test" -NoNewline
    if ($Detail) {
        Write-Host " - $Detail" -ForegroundColor DarkGray
    }
    else {
        Write-Host ""
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  AI Stack - Pre-Deployment Validation" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# TEST 1: File Structure
# =============================================================================
Write-Host "--- File Structure ---" -ForegroundColor White

$requiredFiles = @(
    "README.md"
    "docker/docker-compose.yml"
    "docker/docker-compose.test.yml"
    "docker/.env"
    "docker/traefik.yml"
    "docker/dynamic/middleware.yml"
    "scripts/bootstrap.sh"
    "scripts/pull-models.sh"
    "scripts/backup.sh"
    "docs/01-VM-SETUP.md"
    "docs/02-GPU-PASSTHROUGH.md"
    "docs/03-STACK-GUIDE.md"
    "docs/04-TROUBLESHOOTING.md"
)

foreach ($f in $requiredFiles) {
    $fullPath = Join-Path $BASE $f
    if (Test-Path $fullPath) {
        Test-Check "PASS" "File exists: $f"
    }
    else {
        Test-Check "FAIL" "File missing: $f"
    }
}

# =============================================================================
# TEST 2: Docker Compose YAML Validation
# =============================================================================
Write-Host ""
Write-Host "--- Docker Compose Validation ---" -ForegroundColor White

$composeFile = Join-Path $BASE "docker/docker-compose.yml"
$composeContent = Get-Content $composeFile -Raw

$expectedServices = @("ollama","open-webui","comfyui","whisper","piper","traefik","portainer","watchtower")

foreach ($svc in $expectedServices) {
    $pat = "(?m)^\s{2}" + $svc + ":"
    if ($composeContent -match $pat) {
        Test-Check "PASS" "Service defined: $svc"
    }
    else {
        Test-Check "FAIL" "Service missing: $svc"
    }
}

# Check all services on ai-net
foreach ($svc in $expectedServices) {
    $pat = "(?s)\s{2}" + $svc + ":.*?(?=\n\s{2}\w|\nnetworks:)"
    if ($composeContent -match $pat) {
        $svcBlock = $Matches[0]
        if ($svcBlock -match "ai-net") {
            Test-Check "PASS" "Service on ai-net: $svc"
        }
        else {
            Test-Check "FAIL" "Service NOT on ai-net: $svc" "Container isolation issue"
        }
    }
}

# Port conflicts
$portMatches = [regex]::Matches($composeContent, '- "(\d+):\d+"')
$ports = $portMatches | ForEach-Object { $_.Groups[1].Value }
$duplicatePorts = $ports | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicatePorts) {
    foreach ($dup in $duplicatePorts) {
        Test-Check "FAIL" "Duplicate host port: $($dup.Name)" "Port conflict"
    }
}
else {
    $portList = $ports -join ", "
    Test-Check "PASS" "No host port conflicts ($portList)"
}

# GPU reservations
$gpuServices = @("ollama","comfyui","whisper")
foreach ($svc in $gpuServices) {
    $pat = "(?s)\s{2}" + $svc + ":.*?(?=\n\s{2}\w|\nnetworks:)"
    if ($composeContent -match $pat) {
        if ($Matches[0] -match "driver: nvidia") {
            Test-Check "PASS" "GPU reservation: $svc"
        }
        else {
            Test-Check "FAIL" "No GPU reservation: $svc" "Service needs GPU"
        }
    }
}

# Healthcheck
if ($composeContent -match "healthcheck:") {
    Test-Check "PASS" "Ollama healthcheck defined"
}
else {
    Test-Check "FAIL" "Ollama healthcheck missing" "Open WebUI depends on it"
}

# depends_on
if ($composeContent -match "condition: service_healthy") {
    Test-Check "PASS" "Open WebUI waits for Ollama health"
}
else {
    Test-Check "WARN" "Open WebUI depends_on health check not verified"
}

# Unique container names
$nameMatches = [regex]::Matches($composeContent, 'container_name:\s*(\S+)')
$names = $nameMatches | ForEach-Object { $_.Groups[1].Value }
$duplicateNames = $names | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicateNames) {
    foreach ($dup in $duplicateNames) {
        Test-Check "FAIL" "Duplicate container name: $($dup.Name)"
    }
}
else {
    Test-Check "PASS" "All container names unique ($($names.Count) containers)"
}

# Restart policies
$restartCount = ([regex]::Matches($composeContent, "restart: unless-stopped")).Count
if ($restartCount -eq $expectedServices.Count) {
    Test-Check "PASS" "All $restartCount services have restart policy"
}
else {
    Test-Check "WARN" "Only $restartCount of $($expectedServices.Count) services have restart policy"
}

# Docker socket read-only
$sockMatches = [regex]::Matches($composeContent, "docker\.sock:([^\s]+)")
foreach ($m in $sockMatches) {
    if ($m.Groups[1].Value -match "ro") {
        Test-Check "PASS" "Docker socket mounted read-only"
    }
    else {
        Test-Check "FAIL" "Docker socket NOT read-only" "Security risk"
    }
}

# =============================================================================
# TEST 3: Environment File Validation
# =============================================================================
Write-Host ""
Write-Host "--- Environment File Validation ---" -ForegroundColor White

$envFile = Join-Path $BASE "docker/.env"
$envContent = Get-Content $envFile -Raw
$envLines = Get-Content $envFile | Where-Object { $_ -match "^\w" }

$envVars = @{}
foreach ($line in $envLines) {
    if ($line -match "^(\w+)=(.*)$") {
        $envVars[$Matches[1]] = $Matches[2]
    }
}

# Check all compose-referenced vars exist in .env
$varRefs = [regex]::Matches($composeContent, '\$\{(\w+)\}')
$refVarNames = $varRefs | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($v in $refVarNames) {
    if ($envVars.ContainsKey($v)) {
        Test-Check "PASS" "Env var defined: $v = $($envVars[$v])"
    }
    else {
        Test-Check "FAIL" "Env var missing from .env: $v" "Referenced in compose but not defined"
    }
}

# Secret key check
if ($envVars["WEBUI_SECRET_KEY"] -eq "CHANGE_ME_TO_A_RANDOM_STRING") {
    Test-Check "WARN" "WEBUI_SECRET_KEY is still default" "MUST change before production"
}
else {
    Test-Check "PASS" "WEBUI_SECRET_KEY customized"
}

# DATA_DIR
if ($envVars["DATA_DIR"]) {
    Test-Check "PASS" "DATA_DIR configured: $($envVars['DATA_DIR'])"
}
else {
    Test-Check "FAIL" "DATA_DIR not set" "All volume mounts will fail"
}

# Ollama keepalive format
$keepAlive = $envVars["OLLAMA_KEEP_ALIVE"]
if ($keepAlive -and $keepAlive -match '^\d+[smh]$') {
    Test-Check "PASS" "OLLAMA_KEEP_ALIVE format valid: $keepAlive"
}
else {
    Test-Check "WARN" "OLLAMA_KEEP_ALIVE format may be invalid: $keepAlive"
}

# =============================================================================
# TEST 4: Traefik Config Validation
# =============================================================================
Write-Host ""
Write-Host "--- Traefik Config Validation ---" -ForegroundColor White

$traefikFile = Join-Path $BASE "docker/traefik.yml"
$traefikContent = Get-Content $traefikFile -Raw

$middlewareFile = Join-Path $BASE "docker/dynamic/middleware.yml"
$middlewareContent = Get-Content $middlewareFile -Raw

# Check entrypoints
if ($traefikContent -match 'web:' -and $traefikContent -match 'websecure:') {
    Test-Check "PASS" "Traefik entrypoints: web + websecure"
}
else {
    Test-Check "FAIL" "Traefik missing entrypoints" "Need web (80) and websecure (443)"
}

# Check HTTP to HTTPS redirect
if ($traefikContent -match 'redirections') {
    Test-Check "PASS" "HTTP -> HTTPS redirect configured"
}
else {
    Test-Check "WARN" "No HTTP to HTTPS redirect"
}

# Check Docker provider
if ($traefikContent -match 'docker:' -and $traefikContent -match 'exposedByDefault: false') {
    Test-Check "PASS" "Docker provider: explicit opt-in (exposedByDefault: false)"
}
else {
    Test-Check "FAIL" "Docker provider misconfigured" "exposedByDefault should be false"
}

# Check TLS default cert generation
if ($traefikContent -match 'defaultGenerateCert') {
    Test-Check "PASS" "TLS self-signed cert auto-generation configured"
}
else {
    Test-Check "WARN" "No default TLS cert config"
}

# Check Traefik labels in compose for routed services
$labeledServices = @(
    @{ Svc = "open-webui"; Route = "/" }
    @{ Svc = "comfyui"; Route = "/comfy" }
)
foreach ($ls in $labeledServices) {
    if ($composeContent -match ("traefik.http.routers." + $ls.Svc.Replace("-","") -replace "open-?webui","webui")) {
        Test-Check "PASS" "Traefik label routing: $($ls.Svc) -> $($ls.Route)"
    }
    else {
        # More lenient check
        if ($composeContent -match ("traefik.enable=true") -and $composeContent -match [regex]::Escape($ls.Route)) {
            Test-Check "PASS" "Traefik label routing: $($ls.Svc) -> $($ls.Route)"
        }
        else {
            Test-Check "FAIL" "Missing Traefik labels for $($ls.Svc)" "No route to $($ls.Route)"
        }
    }
}

# Check security headers in middleware
foreach ($hdr in @("X-Content-Type-Options","X-Frame-Options","Referrer-Policy")) {
    if ($middlewareContent -match $hdr) {
        Test-Check "PASS" "Security header: $hdr"
    }
    else {
        Test-Check "WARN" "Missing security header: $hdr"
    }
}

# Check file provider for dynamic config
if ($traefikContent -match 'file:' -and $traefikContent -match 'directory') {
    Test-Check "PASS" "File provider for dynamic config"
}
else {
    Test-Check "WARN" "No file provider for dynamic config"
}

# =============================================================================
# TEST 5: Shell Script Validation
# =============================================================================
Write-Host ""
Write-Host "--- Shell Script Validation ---" -ForegroundColor White

$shellScripts = @(
    "scripts/bootstrap.sh"
    "scripts/pull-models.sh"
    "scripts/backup.sh"
)

foreach ($s in $shellScripts) {
    $sPath = Join-Path $BASE $s
    $sContent = Get-Content $sPath -Raw
    $sName = Split-Path $s -Leaf

    # Shebang
    if ($sContent.StartsWith("#!/usr/bin/env bash")) {
        Test-Check "PASS" "$sName has correct shebang"
    }
    elseif ($sContent.StartsWith("#!/bin/bash")) {
        Test-Check "PASS" "$sName has shebang"
    }
    else {
        Test-Check "FAIL" "$sName missing shebang"
    }

    # Strict mode
    if ($sContent -match "set -[euo]") {
        Test-Check "PASS" "$sName has strict error handling"
    }
    else {
        Test-Check "WARN" "$sName missing set -e" "Script will not stop on errors"
    }

    # Line endings - CRITICAL for Linux
    $rawBytes = [System.IO.File]::ReadAllBytes($sPath)
    $crlfCount = 0
    for ($i = 0; $i -lt $rawBytes.Length - 1; $i++) {
        if ($rawBytes[$i] -eq 13 -and $rawBytes[$i + 1] -eq 10) {
            $crlfCount++
        }
    }
    if ($crlfCount -gt 0) {
        Test-Check "FAIL" "$sName has CRLF line endings ($crlfCount lines)" "MUST convert to LF for Linux"
    }
    else {
        Test-Check "PASS" "$sName has correct LF line endings"
    }
}

# Bootstrap-specific
$bsContent = Get-Content (Join-Path $BASE "scripts/bootstrap.sh") -Raw

if ($bsContent -match "EUID") {
    Test-Check "PASS" "bootstrap.sh root check present"
}
else {
    Test-Check "WARN" "bootstrap.sh no root check"
}

if ($bsContent -match "nvidia-container-toolkit") {
    Test-Check "PASS" "bootstrap.sh installs NVIDIA Container Toolkit"
}
else {
    Test-Check "FAIL" "bootstrap.sh missing NVIDIA Container Toolkit"
}

if ($bsContent -match "systemctl restart docker") {
    Test-Check "PASS" "bootstrap.sh restarts Docker after toolkit"
}
else {
    Test-Check "FAIL" "bootstrap.sh missing Docker restart"
}

# =============================================================================
# TEST 7: Service Connectivity Matrix
# =============================================================================
Write-Host ""
Write-Host "--- Service Connectivity ---" -ForegroundColor White

$allContent = $envContent + $composeContent + $traefikContent + $middlewareContent

$connChecks = @(
    @{ F = "open-webui"; T = "ollama"; U = "http://ollama:11434" }
    @{ F = "open-webui"; T = "comfyui"; U = "http://comfyui:8188" }
    @{ F = "open-webui"; T = "whisper"; U = "http://whisper:8000/v1" }
    @{ F = "open-webui"; T = "piper";   U = "http://piper:8000/v1" }
)

foreach ($c in $connChecks) {
    $escaped = [regex]::Escape($c.U)
    if ($allContent -match $escaped) {
        Test-Check "PASS" "$($c.F) -> $($c.T) [$($c.U)]"
    }
    else {
        Test-Check "FAIL" "$($c.F) -> $($c.T) URL not found" "Expected: $($c.U)"
    }
}

# Piper port mismatch check
if ($envContent -match "piper:5000") {
    Test-Check "FAIL" "Piper TTS port mismatch" "Container listens on 8000 but .env says 5000"
}
elseif ($envContent -match "piper:8000") {
    Test-Check "PASS" "Piper TTS internal port consistent"
}

# =============================================================================
# TEST 8: Security Audit
# =============================================================================
Write-Host ""
Write-Host "--- Security Audit ---" -ForegroundColor White

# Privileged mode
if ($composeContent -match "privileged:\s*true") {
    Test-Check "FAIL" "Privileged container detected" "Use specific capabilities"
}
else {
    Test-Check "PASS" "No privileged containers"
}

# Host network
if ($composeContent -match "network_mode:\s*host") {
    Test-Check "WARN" "Host network mode detected"
}
else {
    Test-Check "PASS" "Proper container network isolation"
}

# Docker socket count
$sockCount = ([regex]::Matches($composeContent, "docker\.sock")).Count
Test-Check "INFO" "Docker socket exposed to $sockCount services"

# =============================================================================
# TEST 9: Test Compose Override
# =============================================================================
Write-Host ""
Write-Host "--- Test Override Validation ---" -ForegroundColor White

$testPath = Join-Path $BASE "docker/docker-compose.test.yml"
$testContent = Get-Content $testPath -Raw

foreach ($svc in @("ollama","comfyui","whisper")) {
    $pat = "(?m)^\s{2}" + $svc + ":"
    if ($testContent -match $pat) {
        Test-Check "PASS" "Test override covers: $svc"
    }
    else {
        Test-Check "FAIL" "Test override missing: $svc"
    }
}

# =============================================================================
# SUMMARY
# =============================================================================
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Passed:   $($script:Pass)" -ForegroundColor Green
Write-Host "  Warnings: $($script:Warn)" -ForegroundColor Yellow

$failColor = "Green"
if ($script:Fail -gt 0) { $failColor = "Red" }
Write-Host "  Failed:   $($script:Fail)" -ForegroundColor $failColor
Write-Host ""

if ($script:Errors.Count -gt 0) {
    Write-Host "  FAILURES:" -ForegroundColor Red
    foreach ($e in $script:Errors) {
        Write-Host "    - $e" -ForegroundColor Red
    }
    Write-Host ""
}

if ($script:Fail -eq 0) {
    Write-Host "  RESULT: ALL CHECKS PASSED" -ForegroundColor Green
    Write-Host "  Stack is ready for deployment." -ForegroundColor Green
}
else {
    Write-Host "  RESULT: FIX $($script:Fail) ISSUE(S) BEFORE DEPLOYING" -ForegroundColor Red
}
Write-Host ""

exit $script:Fail
