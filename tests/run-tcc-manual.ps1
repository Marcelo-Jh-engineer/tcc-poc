param(
    [ValidateSet('A', 'B', 'C', 'all')]
    [string]$Selection = 'all'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$OutputDir = Join-Path $RootDir "tests/results/tcc-manual-$Timestamp"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$Rows = [System.Collections.Generic.List[object]]::new()
$Realm = 'poc-sso'
$UserName = 'user@test.local'
$UserPassword = 'user'
$AdminName = 'admin@test.local'
$AdminPassword = 'admin'
$OriginalRealm = $null

function Add-Result([string]$Test, [string]$Architecture, [string]$Status, [string]$Value) {
    $Rows.Add([pscustomobject]@{
        test = $Test
        architecture = $Architecture
        status = $Status
        value = $Value
    })
}

function New-HttpClient {
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    return [pscustomobject]@{
        Handler = $handler
        Client = [System.Net.Http.HttpClient]::new($handler)
        Cookies = @{}
    }
}

function Invoke-Http($Context, [string]$Method, [string]$Url, [System.Net.Http.HttpContent]$Content = $null, [hashtable]$Headers = @{}) {
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Url)
    foreach ($key in $Headers.Keys) { $request.Headers.TryAddWithoutValidation($key, [string]$Headers[$key]) | Out-Null }
    if ($Context.Cookies.Count -gt 0) {
        $cookieHeader = ($Context.Cookies.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '
        $request.Headers.TryAddWithoutValidation('Cookie', $cookieHeader) | Out-Null
    }
    if ($null -ne $Content) { $request.Content = $Content }
    $response = $Context.Client.SendAsync($request).GetAwaiter().GetResult()
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $location = if ($null -ne $response.Headers.Location) { $response.Headers.Location.ToString() } else { '' }
    $rawHeaders = $response.Headers.ToString() + $response.Content.Headers.ToString()
    foreach ($cookieMatch in [regex]::Matches($rawHeaders, '(?im)^Set-Cookie:\s*([^\r\n]+)')) {
        $cookieParts = $cookieMatch.Groups[1].Value.Split(';')
        $cookiePair = $cookieParts[0].Split('=', 2)
        if ($cookiePair.Count -ne 2) { continue }
        if ($cookieMatch.Groups[1].Value -match '(?i)Max-Age=0|expires=Thu, 01 Jan 1970') {
            $Context.Cookies.Remove($cookiePair[0]) | Out-Null
        } else {
            $Context.Cookies[$cookiePair[0]] = $cookiePair[1]
        }
    }
    return [pscustomobject]@{
        Status = [int]$response.StatusCode
        Body = $body
        Location = $location
        Headers = $response.Headers
    }
}

function New-FormContent([hashtable]$Fields) {
    $pairs = [System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]]::new()
    foreach ($key in $Fields.Keys) { $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new($key, [string]$Fields[$key])) }
    return [System.Net.Http.FormUrlEncodedContent]::new($pairs)
}

function New-JsonContent([object]$Value) {
    return [System.Net.Http.StringContent]::new(($Value | ConvertTo-Json -Compress -Depth 10), [Text.Encoding]::UTF8, 'application/json')
}

function Get-Form($Html) {
    $formMatch = [regex]::Match($Html, '<form[^>]+action="([^"]+)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $formMatch.Success) { throw 'login form not found' }
    $action = [System.Net.WebUtility]::HtmlDecode($formMatch.Groups[1].Value)
    $fields = @{}
    foreach ($inputMatch in [regex]::Matches($Html, '<input[^>]*>', [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $input = $inputMatch.Value
        $nameMatch = [regex]::Match($input, 'name="([^"]+)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $nameMatch.Success) { continue }
        $valueMatch = [regex]::Match($input, 'value="([^"]*)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $fields[$nameMatch.Groups[1].Value] = if ($valueMatch.Success) { [System.Net.WebUtility]::HtmlDecode($valueMatch.Groups[1].Value) } else { '' }
    }
    return [pscustomobject]@{ Action = $action; Fields = $fields }
}

function Resolve-Location([string]$Base, [string]$Location) {
    return ([Uri]::new([Uri]$Base, $Location)).AbsoluteUri
}

function Login-Server([string]$BaseUrl, [string]$Username, [string]$Password) {
    $context = New-HttpClient
    $start = Invoke-Http $context 'GET' "$BaseUrl/auth/login"
    if ($start.Status -notin @(301, 302, 303, 307, 308)) { throw "login start status $($start.Status)" }
    $loginPage = Invoke-Http $context 'GET' (Resolve-Location $BaseUrl $start.Location)
    $form = Get-Form $loginPage.Body
    $form.Fields['username'] = $Username
    $form.Fields['password'] = $Password
    $posted = Invoke-Http $context 'POST' $form.Action (New-FormContent $form.Fields)
    if ($posted.Status -notin @(301, 302, 303, 307, 308)) { throw "login post status $($posted.Status): $($posted.Body.Substring(0, [Math]::Min(120, $posted.Body.Length)))" }
    $callback = Invoke-Http $context 'GET' (Resolve-Location $BaseUrl $posted.Location)
    if ($callback.Status -notin @(301, 302, 303, 307, 308)) { throw "callback status $($callback.Status)" }
    return [pscustomobject]@{ Context = $context; BaseUrl = $BaseUrl }
}

function Get-Api($Session, [string]$Path, [string]$Method = 'GET', [System.Net.Http.HttpContent]$Content = $null, [hashtable]$Headers = @{}) {
    return Invoke-Http $Session.Context $Method "$($Session.BaseUrl)/api/$Path" $Content $Headers
}

function Get-Base64Url([byte[]]$Bytes) {
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-CodeVerifier {
    $bytes = [byte[]]::new(32)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return Get-Base64Url $bytes
}

function Get-CodeChallenge([string]$Verifier) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($Verifier))
    $sha.Dispose()
    return Get-Base64Url $hash
}

function Get-QueryValue([string]$Url, [string]$Name) {
    $match = [regex]::Match($Url, "(?:[?&])$Name=([^&]+)")
    if (-not $match.Success) { return '' }
    return [Uri]::UnescapeDataString($match.Groups[1].Value)
}

function Login-Spa([string]$Username, [string]$Password) {
    $context = New-HttpClient
    $verifier = New-CodeVerifier
    $authUrl = "http://localhost:8180/realms/$Realm/protocol/openid-connect/auth?client_id=spa-client&response_type=code&scope=openid%20profile%20email&redirect_uri=http%3A%2F%2Flocalhost%3A3003%2F&state=manual-$([guid]::NewGuid())&code_challenge=$(Get-CodeChallenge $verifier)&code_challenge_method=S256"
    $page = Invoke-Http $context 'GET' $authUrl
    $form = Get-Form $page.Body
    $form.Fields['username'] = $Username
    $form.Fields['password'] = $Password
    $posted = Invoke-Http $context 'POST' $form.Action (New-FormContent $form.Fields)
    $code = Get-QueryValue $posted.Location 'code'
    if ([string]::IsNullOrWhiteSpace($code)) { throw 'authorization code not returned' }
    $tokenResponse = Invoke-Http $context 'POST' "http://localhost:8180/realms/$Realm/protocol/openid-connect/token" (New-FormContent @{
        grant_type = 'authorization_code'
        client_id = 'spa-client'
        code = $code
        redirect_uri = 'http://localhost:3003/'
        code_verifier = $verifier
    })
    if ($tokenResponse.Status -ne 200) { throw "spa token status $($tokenResponse.Status)" }
    $token = $tokenResponse.Body | ConvertFrom-Json
    return [pscustomobject]@{ Context = $context; BaseUrl = 'http://localhost:8081'; AccessToken = $token.access_token; RefreshToken = $token.refresh_token; ExpiresIn = [int]$token.expires_in }
}

function Get-TokenApi($Session, [string]$Path, [string]$Method = 'GET', [System.Net.Http.HttpContent]$Content = $null) {
    return Invoke-Http $Session.Context $Method "$($Session.BaseUrl)/api/$Path" $Content @{ Authorization = "Bearer $($Session.AccessToken)" }
}

function Get-AdminToken {
    $context = New-HttpClient
    $response = Invoke-Http $context 'POST' "http://localhost:8180/realms/master/protocol/openid-connect/token" (New-FormContent @{
        grant_type = 'password'
        client_id = 'admin-cli'
        username = 'admin'
        password = 'admin'
    })
    if ($response.Status -ne 200) { throw "admin token status $($response.Status)" }
    return [pscustomobject]@{ Context = $context; AccessToken = ($response.Body | ConvertFrom-Json).access_token }
}

function Get-AdminHttp($Admin, [string]$Method, [string]$Url, [object]$Body = $null) {
    $content = if ($null -ne $Body) { New-JsonContent $Body } else { $null }
    return Invoke-Http $Admin.Context $Method $Url $content @{ Authorization = "Bearer $($Admin.AccessToken)" }
}

function Get-Realm($Admin) {
    return (Get-AdminHttp $Admin 'GET' "http://localhost:8180/admin/realms/$Realm").Body | ConvertFrom-Json
}

function Set-AccessTokenLifespan($Admin, [int]$Seconds) {
    $headers = @{ Authorization = "Bearer $($Admin.AccessToken)" }
    try {
        $realmData = Invoke-RestMethod -Uri "http://localhost:8180/admin/realms/$Realm" -Headers $headers
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw }
        $freshAdmin = Get-AdminToken
        $Admin.Context = $freshAdmin.Context
        $Admin.AccessToken = $freshAdmin.AccessToken
        $headers = @{ Authorization = "Bearer $($Admin.AccessToken)" }
        $realmData = Invoke-RestMethod -Uri "http://localhost:8180/admin/realms/$Realm" -Headers $headers
    }
    if ($null -eq $realmData.PSObject.Properties['accessTokenLifespan']) {
        $realmData | Add-Member -NotePropertyName accessTokenLifespan -NotePropertyValue $Seconds
    } else {
        $realmData.accessTokenLifespan = $Seconds
    }
    try {
        Invoke-RestMethod -Uri "http://localhost:8180/admin/realms/$Realm" -Method Put -Headers $headers -ContentType 'application/json' -Body ($realmData | ConvertTo-Json -Depth 30) | Out-Null
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -ne 401) { throw }
        $freshAdmin = Get-AdminToken
        $Admin.Context = $freshAdmin.Context
        $Admin.AccessToken = $freshAdmin.AccessToken
        $headers = @{ Authorization = "Bearer $($Admin.AccessToken)" }
        Invoke-RestMethod -Uri "http://localhost:8180/admin/realms/$Realm" -Method Put -Headers $headers -ContentType 'application/json' -Body ($realmData | ConvertTo-Json -Depth 30) | Out-Null
    }
}

function Get-UserId($Admin, [string]$Username) {
    $response = Get-AdminHttp $Admin 'GET' "http://localhost:8180/admin/realms/$Realm/users?username=$([Uri]::EscapeDataString($Username))"
    return (($response.Body | ConvertFrom-Json)[0].id)
}

function Get-Role($Admin, [string]$RoleName) {
    return (Get-AdminHttp $Admin 'GET' "http://localhost:8180/admin/realms/$Realm/roles/$RoleName").Body | ConvertFrom-Json
}

function Set-AdminRole($Admin, [string]$Username, [bool]$Enabled) {
    $freshAdmin = Get-AdminToken
    $Admin.Context = $freshAdmin.Context
    $Admin.AccessToken = $freshAdmin.AccessToken
    $userId = Get-UserId $Admin $Username
    $role = Get-Role $Admin 'admin'
    $url = "http://localhost:8180/admin/realms/$Realm/users/$userId/role-mappings/realm"
    $headers = @{ Authorization = "Bearer $($Admin.AccessToken)" }
    $method = if ($Enabled) { 'Post' } else { 'Delete' }
    Invoke-RestMethod -Uri $url -Method $method -Headers $headers -ContentType 'application/json' -Body (ConvertTo-Json -InputObject @($role) -Depth 10) | Out-Null
}

function Test-AuthenticatedFlows {
    $serverSessions = @{}
    foreach ($item in @(@{ Name = 'A'; Base = 'http://localhost:8000' }, @{ Name = 'B'; Base = 'http://localhost:8083' })) {
        if ($Selection -ne 'all' -and $Selection -ne $item.Name) { continue }
        try {
            $session = Login-Server $item.Base $UserName $UserPassword
            $serverSessions[$item.Name] = $session
            $protected = Get-Api $session 'protected'
            Add-Result 'CT-01' $item.Name $(if ($protected.Status -eq 200) { 'PASS' } else { 'FAIL' }) "protected=$($protected.Status)"
            $admin = Get-Api $session 'admin'
            Add-Result 'CT-01' "$($item.Name)-authorization" $(if ($admin.Status -eq 403) { 'PASS' } else { 'FAIL' }) "user_admin=$($admin.Status)"
            $products = Get-Api $session 'products'
            Add-Result 'CT-04' $item.Name 'EVIDENCE_REVIEW_REQUIRED' 'browser_storage_requires_DevTools'
            Add-Result 'CT-17' $item.Name 'EVIDENCE_REVIEW_REQUIRED' 'refresh_visibility_requires_DevTools'
            Add-Result 'CT-01' "$($item.Name)-catalog" $(if ($products.Status -eq 200) { 'PASS' } else { 'FAIL' }) "products=$($products.Status)"
        } catch {
            Add-Result 'CT-01' $item.Name 'ERROR' ("login_flow_failed: " + $_.Exception.Message)
        }
    }
    if ($Selection -eq 'all' -or $Selection -eq 'C') {
        try {
            $spa = Login-Spa $UserName $UserPassword
            $protected = Get-TokenApi $spa 'protected'
            Add-Result 'CT-01' 'C' $(if ($protected.Status -eq 200) { 'PASS' } else { 'FAIL' }) "protected=$($protected.Status)"
            Add-Result 'CT-04' 'C' 'EVIDENCE_REVIEW_REQUIRED' 'Bearer_visible_in_browser_context'
            Add-Result 'CT-09' 'C' 'EVIDENCE_REVIEW_REQUIRED' 'JavaScript_exfiltration_requires_DevTools'
            Add-Result 'CT-17' 'C' 'EVIDENCE_REVIEW_REQUIRED' 'refresh_visibility_requires_DevTools'
        } catch {
            Add-Result 'CT-01' 'C' 'ERROR' ("login_flow_failed: " + $_.Exception.Message)
        }
    }
    return $serverSessions
}

try {
    $Admin = Get-AdminToken
    $OriginalRealm = Get-Realm $Admin
    $sessions = Test-AuthenticatedFlows

    foreach ($item in @(@{ Name = 'A'; Base = 'http://localhost:8000' }, @{ Name = 'B'; Base = 'http://localhost:8083' })) {
        if (-not $sessions.ContainsKey($item.Name)) { continue }
        $session = $sessions[$item.Name]
        $logout = Invoke-Http $session.Context 'GET' "$($item.Base)/auth/logout"
        $afterLogout = Get-Api $session 'protected'
        Add-Result 'CT-12' $item.Name $(if ($logout.Status -in @(301, 302, 303) -and $afterLogout.Status -eq 401) { 'PASS' } else { 'FAIL' }) "logout=$($logout.Status);protected_after=$($afterLogout.Status)"
        Add-Result 'CT-13' $item.Name $(if ($afterLogout.Status -eq 401) { 'PASS' } else { 'FAIL' }) "replay_after_logout=$($afterLogout.Status)"
    }

    if ($Selection -eq 'all' -or $Selection -eq 'C') {
        $spaReplay = Login-Spa $UserName $UserPassword
        $beforeLogout = Get-TokenApi $spaReplay 'protected'
        $logout = Invoke-Http $spaReplay.Context 'GET' "http://localhost:8180/realms/$Realm/protocol/openid-connect/logout?client_id=spa-client&post_logout_redirect_uri=http%3A%2F%2Flocalhost%3A3003%2F"
        $afterLogout = Get-TokenApi $spaReplay 'protected'
        Add-Result 'CT-12' 'C' $(if ($logout.Status -in @(200, 302, 303)) { 'PASS' } else { 'OBSERVED' }) "logout=$($logout.Status);before=$($beforeLogout.Status)"
        Add-Result 'CT-13' 'C' 'OBSERVED' "replay_after_logout=$($afterLogout.Status);token_ttl_seconds=$($spaReplay.ExpiresIn)"
        Add-Result 'CT-19A' 'C' 'EVIDENCE_REVIEW_REQUIRED' 'token_obtained_by_controlled_client'
        Add-Result 'CT-19B' 'C' $(if ($afterLogout.Status -eq 200) { 'OBSERVED' } else { 'PASS' }) "replay_status=$($afterLogout.Status)"
    }

    foreach ($item in @(@{ Name = 'A'; Base = 'http://localhost:8000' }, @{ Name = 'B'; Base = 'http://localhost:8083' })) {
        if (-not $sessions.ContainsKey($item.Name)) { continue }
        $post = Get-Api $sessions[$item.Name] 'preferences' 'POST' (New-JsonContent @{ theme = 'dark' }) @{ Origin = 'http://evil.test' }
        Add-Result 'CT-16' $item.Name 'OBSERVED' "cross_origin_post=$($post.Status)"
    }
    if ($Selection -eq 'all' -or $Selection -eq 'C') {
        $spaCsrf = Login-Spa $UserName $UserPassword
        $post = Get-TokenApi $spaCsrf 'preferences' 'POST' (New-JsonContent @{ theme = 'dark' })
        Add-Result 'CT-16' 'C' 'OBSERVED' "bearer_post=$($post.Status)"
    }

    Set-AccessTokenLifespan $Admin 30
    foreach ($item in @(@{ Name = 'A'; Base = 'http://localhost:8000' }, @{ Name = 'B'; Base = 'http://localhost:8083' })) {
        if ($Selection -ne 'all' -and $Selection -ne $item.Name) { continue }
        $short = Login-Server $item.Base $UserName $UserPassword
        Start-Sleep -Seconds 35
        $renewed = Invoke-Http $short.Context 'GET' "$($item.Base)/auth/session"
        Add-Result 'CT-02' $item.Name $(if ($renewed.Status -eq 200 -and $renewed.Body -match '"authenticated":true') { 'PASS' } else { 'FAIL' }) "session_after_ttl=$($renewed.Status);authenticated=$($renewed.Body -match '"authenticated":true')"
    }
    if ($Selection -eq 'all' -or $Selection -eq 'C') {
        $spaShort = Login-Spa $UserName $UserPassword
        Start-Sleep -Seconds 35
        $refreshResponse = Invoke-Http $spaShort.Context 'POST' "http://localhost:8180/realms/$Realm/protocol/openid-connect/token" (New-FormContent @{ grant_type = 'refresh_token'; client_id = 'spa-client'; refresh_token = $spaShort.RefreshToken })
        Add-Result 'CT-02' 'C' $(if ($refreshResponse.Status -eq 200) { 'PASS' } else { 'FAIL' }) "refresh_after_ttl=$($refreshResponse.Status)"
    }

    Set-AccessTokenLifespan $Admin 300

    foreach ($item in @(@{ Name = 'A'; Base = 'http://localhost:8000' }, @{ Name = 'B'; Base = 'http://localhost:8083' })) {
        if ($Selection -ne 'all' -and $Selection -ne $item.Name) { continue }
        $fresh = Login-Server $item.Base $UserName $UserPassword
        docker compose stop keycloak | Out-Null
        try {
            $existing = Get-Api $fresh 'protected'
            $newLogin = Invoke-Http (New-HttpClient) 'GET' "$($item.Base)/auth/login"
            $newLoginStatus = $newLogin.Status
            try { $newLoginStatus = (Invoke-Http (New-HttpClient) 'GET' (Resolve-Location $item.Base $newLogin.Location)).Status } catch { $newLoginStatus = 0 }
            Add-Result 'CT-14' $item.Name 'OBSERVED' "existing_session=$($existing.Status);new_login=$newLoginStatus"
        } finally {
            docker compose start keycloak | Out-Null
            for ($attempt = 0; $attempt -lt 30; $attempt++) {
                try {
                    $ready = Invoke-WebRequest -Uri 'http://localhost:8180/health/ready' -UseBasicParsing -TimeoutSec 2
                    if ($ready.StatusCode -eq 200) { break }
                } catch { }
                Start-Sleep -Seconds 2
            }
        }
    }

    $adminSessions = @{}
    foreach ($item in @(@{ Name = 'A'; Base = 'http://localhost:8000' }, @{ Name = 'B'; Base = 'http://localhost:8083' })) {
        if ($Selection -ne 'all' -and $Selection -ne $item.Name) { continue }
        $adminSessions[$item.Name] = Login-Server $item.Base $AdminName $AdminPassword
        $before = Get-Api $adminSessions[$item.Name] 'admin'
        Set-AdminRole $Admin $AdminName $false
        $after = Get-Api $adminSessions[$item.Name] 'admin'
        Add-Result 'CT-18' $item.Name 'OBSERVED' "before=$($before.Status);after_role_removal=$($after.Status)"
        Set-AdminRole $Admin $AdminName $true
    }
} catch {
    Add-Result 'RUNNER' 'all' 'ERROR' ("manual_protocol_runner_failed: " + $_.Exception.Message)
} finally {
    if ($null -ne $OriginalRealm) { try { Set-AccessTokenLifespan $Admin 300 } catch { } }
    $Rows | Export-Csv -NoTypeInformation -Encoding utf8 (Join-Path $OutputDir 'summary.csv')
    Copy-Item (Join-Path $OutputDir 'summary.csv') (Join-Path $RootDir 'tests/results/tcc-manual-summary.csv') -Force
    $Rows | Group-Object status | Sort-Object Name | ForEach-Object { Write-Output ("{0}: {1}" -f $_.Name, $_.Count) }
    Write-Output "Raw results: $OutputDir"
}
