param(
    [ValidateSet('A', 'B', 'C', 'all')]
    [string]$Selection = 'all'
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$EvidenceDir = Join-Path $RootDir 'docs/results'
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$OutputDir = Join-Path $RootDir "tests/results/manual-$Timestamp"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$Evidence = @(
    @{ Case = 'CT-01'; Architecture = 'A'; Files = @('client-info-A.png'); Observation = 'PKCE S256 do gateway-client' },
    @{ Case = 'CT-01'; Architecture = 'B'; Files = @('client-info-b.png'); Observation = 'PKCE S256 do bff-client' },
    @{ Case = 'CT-01'; Architecture = 'C'; Files = @('client-info-c.png'); Observation = 'PKCE S256 do spa-client' },
    @{ Case = 'CT-04'; Architecture = 'A'; Files = @('cookie-A-console.png', 'cookie-A-memory.png', 'tokens-a-b.png'); Observation = 'Cookie HttpOnly e storage sem token' },
    @{ Case = 'CT-04'; Architecture = 'B'; Files = @('cookie-B-console.png', 'cookie-B-memory.png', 'tokens-a-b.png'); Observation = 'Cookie HttpOnly e storage sem token' },
    @{ Case = 'CT-04'; Architecture = 'C'; Files = @('token-c-bearer.png'); Observation = 'Bearer enviado pelo navegador ao resource server' },
    @{ Case = 'CT-09'; Architecture = 'A'; Files = @('cookie-A-console.png'); Observation = 'document.cookie nao revela a sessao' },
    @{ Case = 'CT-09'; Architecture = 'B'; Files = @('cookie-B-console.png'); Observation = 'document.cookie nao revela a sessao' },
    @{ Case = 'CT-09'; Architecture = 'C'; Files = @('token-c-bearer.png'); Observation = 'Bearer observavel na requisicao do navegador' },
    @{ Case = 'CT-11'; Architecture = 'B'; Files = @('produtos-listagem-requisicao-token.png'); Observation = 'Frontend envia cookie ao BFF; BFF intermedeia o resource server' },
    @{ Case = 'CT-17'; Architecture = 'A'; Files = @('cookie-A-console.png', 'cookie-A-memory.png'); Observation = 'Nao ha refresh token visivel nas capturas' },
    @{ Case = 'CT-17'; Architecture = 'B'; Files = @('cookie-B-console.png', 'cookie-B-memory.png'); Observation = 'Nao ha refresh token visivel nas capturas' },
    @{ Case = 'CT-17'; Architecture = 'C'; Files = @('tokens-c.png', 'tokens-c-client-keycloak-info.png'); Observation = 'Fluxo OIDC do SPA visivel no navegador; revisar token e storage' }
)

$ManualCases = @('CT-02', 'CT-12', 'CT-13', 'CT-14', 'CT-16', 'CT-18', 'CT-19A', 'CT-19B')
$Rows = [System.Collections.Generic.List[object]]::new()

foreach ($item in $Evidence) {
    if ($Selection -ne 'all' -and $Selection -ne $item.Architecture) { continue }

    $missing = @($item.Files | Where-Object { -not (Test-Path (Join-Path $EvidenceDir $_)) })
    $present = @($item.Files | Where-Object { Test-Path (Join-Path $EvidenceDir $_) })
    $status = if ($missing.Count -eq 0) { 'EVIDENCE_PRESENT_REVIEW_REQUIRED' } else { 'EVIDENCE_MISSING' }
    $Rows.Add([pscustomobject]@{
        test = $item.Case
        architecture = $item.Architecture
        status = $status
        observation = $item.Observation
        files = ($present -join ';')
        missing = ($missing -join ';')
    })
}

foreach ($architecture in @('A', 'B', 'C')) {
    if ($Selection -ne 'all' -and $Selection -ne $architecture) { continue }
    foreach ($test in $ManualCases) {
        $Rows.Add([pscustomobject]@{
            test = $test
            architecture = $architecture
            status = 'MANUAL_NOT_EXECUTED'
            observation = 'Executar no navegador ou no painel administrativo conforme o roteiro'
            files = ''
            missing = 'docs/roteiro-testes.md'
        })
    }
}

$CsvPath = Join-Path $OutputDir 'manual-evidence.csv'
$Rows | Export-Csv -NoTypeInformation -Encoding utf8 $CsvPath
Copy-Item $CsvPath (Join-Path $RootDir 'tests/results/manual-evidence-summary.csv') -Force

$Rows | Group-Object status | Sort-Object Name | ForEach-Object {
    Write-Output ("{0}: {1}" -f $_.Name, $_.Count)
}
Write-Output "Evidence source: $EvidenceDir"
Write-Output "Report: $CsvPath"
