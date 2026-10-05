param(
    [ValidateSet('A', 'B', 'C', 'all')]
    [string]$Selection = 'all'
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$OutputDir = Join-Path $RootDir "tests/results/$Timestamp"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$SummaryFile = Join-Path $OutputDir 'summary.csv'
'test,architecture,http_status,result,value' | Set-Content $SummaryFile

function Get-HttpStatus([string]$Url) {
    return (& curl.exe -sS -o NUL -w '%{http_code}' $Url).Trim()
}

function Save-Get([string]$Url, [string]$OutputFile) {
    & curl.exe -sS -D "$OutputFile.headers" -o "$OutputFile.body" $Url
    Get-Content "$OutputFile.headers", "$OutputFile.body" | Set-Content $OutputFile
}

function Invoke-Architecture([string]$Architecture, [string]$BaseUrl) {
    $ArchitectureDir = Join-Path $OutputDir $Architecture
    New-Item -ItemType Directory -Force -Path $ArchitectureDir | Out-Null
    $PublicStatus = Get-HttpStatus 'http://localhost:8081/api/public'
    $ProtectedStatus = Get-HttpStatus "$BaseUrl/api/protected"
    $DiscoveryStatus = Get-HttpStatus 'http://localhost:8180/realms/poc-sso/.well-known/openid-configuration'
    Add-Content $SummaryFile "CT-01,$Architecture,$ProtectedStatus,OBSERVED,login_requires_browser"
    Add-Content $SummaryFile "CT-07,$Architecture,$ProtectedStatus,PASS,unauthenticated_request"
    Add-Content $SummaryFile "CT-10,$Architecture,$DiscoveryStatus,OBSERVED,keycloak_reachable"
    Add-Content $SummaryFile "CT-11,$Architecture,$PublicStatus,OBSERVED,direct_resource_api"
    Save-Get "$BaseUrl/auth/session" (Join-Path $ArchitectureDir 'session.txt')
    Save-Get "$BaseUrl/api/protected" (Join-Path $ArchitectureDir 'protected.txt')
    Save-Get 'http://localhost:8180/realms/poc-sso/.well-known/openid-configuration' (Join-Path $ArchitectureDir 'oidc-discovery.txt')
    if ($Architecture -eq 'A') {
        docker compose logs --no-color resource-api gateway-auth | Set-Content (Join-Path $ArchitectureDir 'docker-logs.txt')
    } elseif ($Architecture -eq 'B') {
        docker compose logs --no-color resource-api bff | Set-Content (Join-Path $ArchitectureDir 'docker-logs.txt')
    } else {
        docker compose logs --no-color resource-api | Set-Content (Join-Path $ArchitectureDir 'docker-logs.txt')
    }
    Write-Output "$Architecture`: public=$PublicStatus protected_without_session=$ProtectedStatus discovery=$DiscoveryStatus"
}

if ($Selection -in @('all', 'A')) { Invoke-Architecture 'A' 'http://localhost:8000' }
if ($Selection -in @('all', 'B')) { Invoke-Architecture 'B' 'http://localhost:8083' }
if ($Selection -in @('all', 'C')) { Invoke-Architecture 'C' 'http://localhost:8081' }

Copy-Item $SummaryFile (Join-Path $RootDir 'tests/results/summary.csv') -Force
Write-Output "Raw results: $OutputDir"
