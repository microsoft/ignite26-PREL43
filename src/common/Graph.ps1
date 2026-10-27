# ---------------------------------------------------------------------------------------------
# Microsoft Graph client: app-only token from the Skillable cloud credential, retries on
# throttling (429) and transient errors (5xx) honouring Retry-After, paging, token roles.
# Targets PowerShell 7.1+ (Skillable "Execute Script in Cloud Platform").
# ---------------------------------------------------------------------------------------------

$script:GraphRoot = 'https://graph.microsoft.com/v1.0'
$script:GraphAuth = $null
$script:GraphRetryBudgetSeconds = 600   # Check my work scripts lower this so learners never wait long

class GraphError : System.Exception {
    [int]$Status
    [string]$Code
    GraphError([string]$message, [int]$status, [string]$code) : base($message) {
        $this.Status = $status
        $this.Code = $code
    }
}

function Connect-Graph {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret
    )
    $script:GraphAuth = @{ TenantId = $TenantId; ClientId = $ClientId; ClientSecret = $ClientSecret; Token = $null; Expires = [datetime]::MinValue }
    [void](Get-GraphToken -Force)
}

function Get-GraphToken {
    param([switch]$Force)
    $a = $script:GraphAuth
    if (-not $a) { throw 'Connect-Graph has not been called.' }
    if (-not $Force -and $a.Token -and (Get-Date).ToUniversalTime() -lt $a.Expires.AddMinutes(-5)) { return $a.Token }
    $body = @{
        client_id     = $a.ClientId
        client_secret = $a.ClientSecret
        scope         = 'https://graph.microsoft.com/.default'
        grant_type    = 'client_credentials'
    }
    $r = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($a.TenantId)/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded'
    $a.Token = $r.access_token
    $a.Expires = (Get-Date).ToUniversalTime().AddSeconds([int]$r.expires_in)
    return $a.Token
}

function Get-GraphRoles {
    <# Application permissions present in the current token (the "roles" claim). #>
    $payload = (Get-GraphToken).Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    return @($claims.roles)
}

function Invoke-Graph {
    <#
      Calls Microsoft Graph. Returns the parsed JSON as hashtables, $null for 404 when -Ok404,
      or the raw response object when -Raw (status, headers, content).
    #>
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Path,
        $Body,
        [byte[]]$Bytes,
        [string]$ContentType,
        [hashtable]$Headers,
        [switch]$Ok404,
        [switch]$Raw,
        [int]$MaxRetries = 8
    )
    $uri = if ($Path -match '^https?://') { $Path } else { "$script:GraphRoot$Path" }
    $refreshed = $false
    $started = Get-Date
    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        $h = @{ Authorization = "Bearer $(Get-GraphToken)" }
        if ($Headers) { foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] } }
        # -SkipHttpErrorCheck (PowerShell 7.0+) returns 4xx/5xx responses instead of throwing.
        $p = @{ Method = $Method; Uri = $uri; Headers = $h; SkipHttpErrorCheck = $true }
        if ($null -ne $Bytes) {
            $p.Body = $Bytes
            $p.ContentType = if ($ContentType) { $ContentType } else { 'application/octet-stream' }
        }
        elseif ($null -ne $Body) {
            $p.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 30 -Compress }
            $p.ContentType = if ($ContentType) { $ContentType } else { 'application/json; charset=utf-8' }
        }
        try {
            $resp = Invoke-WebRequest @p -UseBasicParsing
        }
        catch {
            $netError = $_.Exception -is [System.Net.Http.HttpRequestException] -or $_.Exception -is [System.Threading.Tasks.TaskCanceledException] -or $_.Exception -is [System.IO.IOException] -or $_.Exception -is [System.Net.WebException]
            if (-not $netError -or $attempt -eq $MaxRetries -or ((Get-Date) - $started).TotalSeconds -gt $script:GraphRetryBudgetSeconds) {
                throw [GraphError]::new("$Method $Path : $($_.Exception.GetType().Name): $($_.Exception.Message)", 0, 'network')
            }
            Start-Sleep -Seconds ([math]::Min(60, [math]::Pow(2, $attempt)))
            continue
        }
        $status = [int]$resp.StatusCode
        $rh = $resp.Headers
        if ($status -eq 401 -and -not $refreshed) { [void](Get-GraphToken -Force); $refreshed = $true; $attempt--; continue }
        if ($status -in 429, 500, 502, 503, 504 -and $attempt -lt $MaxRetries -and ((Get-Date) - $started).TotalSeconds -lt $script:GraphRetryBudgetSeconds) {
            $wait = 0
            if ($rh -and $rh['Retry-After']) { [void][int]::TryParse("$($rh['Retry-After'] | Select-Object -First 1)", [ref]$wait) }
            if ($wait -le 0) { $wait = [math]::Min(60, [math]::Pow(2, $attempt)) }
            Start-Sleep -Seconds ($wait + (Get-Random -Minimum 0 -Maximum 2))
            continue
        }
        if ($status -eq 404 -and $Ok404) { return $null }
        if ($status -ge 400) {
            $code = ''; $msg = "$($resp.Content)"
            try { $e = ($resp.Content | ConvertFrom-Json).error; $code = $e.code; $msg = "$($e.code): $($e.message)" } catch { }
            throw [GraphError]::new("$Method $Path -> $status $msg", $status, $code)
        }
        if ($Raw) { return [pscustomobject]@{ Status = $status; Headers = $rh; Content = $resp.Content } }
        if ($status -eq 204 -or -not $resp.Content) { return @{} }
        $ctype = "$($rh['Content-Type'] | Select-Object -First 1)"
        if ($ctype -match 'json') {
            $text = if ($resp.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($resp.Content) } else { $resp.Content }
            return ($text | ConvertFrom-Json -AsHashtable -Depth 50)
        }
        return $resp.Content
    }
    throw [GraphError]::new("$Method $Path : retries exhausted", 0, 'retries')
}

function Get-GraphAll {
    <# GET with paging (@odata.nextLink). #>
    param([Parameter(Mandatory)][string]$Path, [hashtable]$Headers, [int]$Limit = 0)
    $out = [System.Collections.Generic.List[object]]::new()
    $page = Invoke-Graph -Path $Path -Headers $Headers
    while ($true) {
        foreach ($v in @($page.value)) { if ($null -ne $v) { $out.Add($v) } }
        $next = $page.'@odata.nextLink'
        if (-not $next -or ($Limit -gt 0 -and $out.Count -ge $Limit)) { break }
        $page = Invoke-Graph -Path $next -Headers $Headers
    }
    if ($Limit -gt 0 -and $out.Count -gt $Limit) { return $out.GetRange(0, $Limit).ToArray() }
    return $out.ToArray()
}

function Get-GraphBytes {
    <# Downloads a binary resource (file content) as a byte array. #>
    param([Parameter(Mandatory)][string]$Path)
    $tmp = [IO.Path]::GetTempFileName()
    try {
        for ($attempt = 0; $attempt -le 5; $attempt++) {
            try {
                Invoke-WebRequest -Uri "$script:GraphRoot$Path" -Headers @{ Authorization = "Bearer $(Get-GraphToken)" } -OutFile $tmp -UseBasicParsing
                return [IO.File]::ReadAllBytes($tmp)
            }
            catch {
                if ($attempt -eq 5) { throw }
                Start-Sleep -Seconds ([math]::Pow(2, $attempt))
            }
        }
    }
    finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

function ConvertTo-ODataLiteral([string]$Value) { return $Value.Replace("'", "''") }

function Test-GraphRoles {
    <#
      Each requirement is an array of acceptable roles (any one satisfies it).
      Returns the requirements that are not met, as readable strings.
    #>
    param([Parameter(Mandatory)][object[]]$Required)
    $have = Get-GraphRoles
    $missing = @()
    foreach ($req in $Required) {
        $any = @($req)
        if (-not ($any | Where-Object { $have -contains $_ })) { $missing += ($any -join ' or ') }
    }
    return $missing
}
