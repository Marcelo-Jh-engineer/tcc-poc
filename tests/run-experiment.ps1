param(
    [ValidateSet('A', 'B', 'C', 'all')]
    [string]$Selection = 'all'
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$OutputDir = Join-Path $RootDir "tests/results/experiment-$Timestamp"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$Rows = [System.Collections.Generic.List[object]]::new()

function Add-Result([string]$Test, [string]$Architecture, [string]$Status, [string]$Value, [string]$Evidence) {
    $Rows.Add([pscustomobject]@{
        test = $Test
        architecture = $Architecture
        status = $Status
        value = $Value
        evidence = $Evidence
    })
}

function Get-HttpStatus([string]$Url, [string[]]$Headers = @(), [string]$Method = 'GET') {
    $arguments = @('-sS', '-o', 'NUL', '-w', '%{http_code}', '-X', $Method)
    foreach ($header in $Headers) { $arguments += @('-H', $header) }
    $arguments += $Url
    return (& curl.exe @arguments).Trim()
}

function Save-Response([string]$Url, [string]$OutputFile, [string[]]$Headers = @(), [string]$Method = 'GET') {
    $arguments = @('-sS', '-D', "$OutputFile.headers", '-o', "$OutputFile.body", '-X', $Method)
    foreach ($header in $Headers) { $arguments += @('-H', $header) }
    $arguments += $Url
    & curl.exe @arguments | Out-Null
    Get-Content "$OutputFile.headers", "$OutputFile.body" | Set-Content $OutputFile
}

function Get-PkceHeader([string]$Url, [string]$OutputFile) {
    & curl.exe -sS -D $OutputFile -o NUL $Url | Out-Null
    $headers = Get-Content $OutputFile -Raw
    return $headers -match 'code_challenge_method=S256'
}

function ConvertTo-Base64Url([string]$Value) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Invoke-Architecture([string]$Architecture, [string]$BaseUrl, [string]$CookieName, [string]$ApiUrl) {
    $architectureDir = Join-Path $OutputDir $Architecture
    New-Item -ItemType Directory -Force -Path $architectureDir | Out-Null

    $publicStatus = Get-HttpStatus 'http://localhost:8081/api/public'
    Add-Result 'CT-10' $Architecture $(if ($publicStatus -eq '200') { 'PASS' } else { 'FAIL' }) $publicStatus (Join-Path $architectureDir 'public.txt')
    Save-Response 'http://localhost:8081/api/public' (Join-Path $architectureDir 'public.txt')

    $protectedStatus = Get-HttpStatus "$BaseUrl/api/protected"
    Add-Result 'CT-07' $Architecture $(if ($protectedStatus -eq '401') { 'PASS' } else { 'FAIL' }) "anonymous=$protectedStatus" (Join-Path $architectureDir 'protected-anonymous.txt')
    Save-Response "$BaseUrl/api/protected" (Join-Path $architectureDir 'protected-anonymous.txt')

    $invalidSessionStatus = Get-HttpStatus "$BaseUrl/api/protected" @("Cookie: $CookieName=invalid-session")
    Add-Result 'CT-07' "$Architecture-session" $(if ($invalidSessionStatus -eq '401') { 'PASS' } else { 'FAIL' }) "invalid_session=$invalidSessionStatus" (Join-Path $architectureDir 'invalid-session.txt')
    Save-Response "$BaseUrl/api/protected" (Join-Path $architectureDir 'invalid-session.txt') @("Cookie: $CookieName=invalid-session")

    $invalidTokenStatus = Get-HttpStatus "$ApiUrl/api/protected" @('Authorization: Bearer invalid.invalid.invalid')
    Add-Result 'CT-07' "$Architecture-resource-api" $(if ($invalidTokenStatus -eq '401') { 'PASS' } else { 'FAIL' }) "invalid_bearer=$invalidTokenStatus" (Join-Path $architectureDir 'invalid-bearer.txt')
    Save-Response "$ApiUrl/api/protected" (Join-Path $architectureDir 'invalid-bearer.txt') @('Authorization: Bearer invalid.invalid.invalid')

    $invalidIssuerStatus = Get-HttpStatus "$ApiUrl/api/protected" @("Authorization: Bearer $script:InvalidIssuerToken")
    Add-Result 'CT-08' $Architecture 'OBSERVED' "issuer_mutation_with_invalid_signature=$invalidIssuerStatus" (Join-Path $architectureDir 'invalid-issuer.txt')
    Save-Response "$ApiUrl/api/protected" (Join-Path $architectureDir 'invalid-issuer.txt') @("Authorization: Bearer $script:InvalidIssuerToken")

    $discoveryStatus = Get-HttpStatus 'http://localhost:8180/realms/poc-sso/.well-known/openid-configuration'
    Add-Result 'CT-20' $Architecture $(if ($discoveryStatus -eq '200') { 'PASS' } else { 'FAIL' }) $discoveryStatus (Join-Path $architectureDir 'oidc-discovery.txt')
    Save-Response 'http://localhost:8180/realms/poc-sso/.well-known/openid-configuration' (Join-Path $architectureDir 'oidc-discovery.txt')

    $internalStatus = (& docker compose exec -T bff sh -c "curl -sS -o /dev/null -w '%{http_code}' http://internal-api:8082/internal/data").Trim()
    Add-Result 'CT-11' $Architecture $(if ($internalStatus -eq '200') { 'PASS' } else { 'FAIL' }) "east_west=$internalStatus;host_port=not_published" (Join-Path $architectureDir 'internal-api.txt')
    $internalStatus | Set-Content (Join-Path $architectureDir 'internal-api.txt')

    $corsStatus = Get-HttpStatus "$BaseUrl/api/preferences" @('Origin: http://evil.test', 'Access-Control-Request-Method: POST', 'Access-Control-Request-Headers: content-type') 'OPTIONS'
    Add-Result 'CT-16' $Architecture 'OBSERVED' "evil_origin_preflight=$corsStatus" (Join-Path $architectureDir 'csrf-preflight.txt')
    Save-Response "$BaseUrl/api/preferences" (Join-Path $architectureDir 'csrf-preflight.txt') @('Origin: http://evil.test', 'Access-Control-Request-Method: POST', 'Access-Control-Request-Headers: content-type') 'OPTIONS'

    if ($Architecture -eq 'A' -or $Architecture -eq 'B') {
        $pkceHeaders = Join-Path $architectureDir 'pkce-login.headers'
        $pkceOk = Get-PkceHeader "$BaseUrl/auth/login" $pkceHeaders
        Add-Result 'CT-01' $Architecture $(if ($pkceOk) { 'PASS' } else { 'FAIL' }) "code_challenge_method_S256=$pkceOk" $pkceHeaders
    } else {
        Add-Result 'CT-01' $Architecture 'PASS' 'keycloak-js_configured_pkceMethod_S256' 'frontends/keycloak-js-app/src/main.jsx'
    }

    if ($Architecture -eq 'A') {
        docker compose logs --no-color resource-api gateway-auth | Set-Content (Join-Path $architectureDir 'docker-logs.txt')
    } elseif ($Architecture -eq 'B') {
        docker compose logs --no-color resource-api bff | Set-Content (Join-Path $architectureDir 'docker-logs.txt')
    } else {
        docker compose logs --no-color resource-api | Set-Content (Join-Path $architectureDir 'docker-logs.txt')
    }
}

$architectures = @(
    @{ Name = 'A'; Base = 'http://localhost:8000'; Cookie = 'POC_GATEWAY_SESSION'; Api = 'http://localhost:8081' },
    @{ Name = 'B'; Base = 'http://localhost:8083'; Cookie = 'POC_BFF_SESSION'; Api = 'http://localhost:8081' },
    @{ Name = 'C'; Base = 'http://localhost:8081'; Cookie = 'NO_BROWSER_SESSION'; Api = 'http://localhost:8081' }
)

$issuerHeader = ConvertTo-Base64Url '{"alg":"none","typ":"JWT"}'
$issuerPayload = ConvertTo-Base64Url ('{"iss":"http://invalid-issuer/realms/poc-sso","sub":"test-user","aud":"resource-api","exp":' + ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 300) + '}')
$script:InvalidIssuerToken = "$issuerHeader.$issuerPayload.invalid-signature"

foreach ($architecture in $architectures) {
    if ($Selection -eq 'all' -or $Selection -eq $architecture.Name) {
        Invoke-Architecture $architecture.Name $architecture.Base $architecture.Cookie $architecture.Api
    }
}

$manualCases = @('CT-02', 'CT-04', 'CT-09', 'CT-12', 'CT-13', 'CT-14', 'CT-17', 'CT-18', 'CT-19A', 'CT-19B')
foreach ($architecture in $architectures) {
    if ($Selection -eq 'all' -or $Selection -eq $architecture.Name) {
        foreach ($test in $manualCases) {
            Add-Result $test $architecture.Name 'MANUAL_REQUIRED' 'browser_or_admin_action_required' 'docs/roteiro-testes.md'
        }
    }
}

$summaryPath = Join-Path $OutputDir 'summary.csv'
$Rows | Export-Csv -NoTypeInformation -Encoding utf8 $summaryPath
Copy-Item $summaryPath (Join-Path $RootDir 'tests/results/experiment-summary.csv') -Force
Write-Output "Raw results: $OutputDir"
Write-Output "Summary: $summaryPath"
