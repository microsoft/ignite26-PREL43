# Optional: TapPolicy - only if the lab's own TAP action is replaced. Execute in Cloud Platform, PowerShell 7.
$ErrorActionPreference = 'Stop'
$TenantId     = '@lab.CloudCredential(WWLM365E7).TenantId'
$ClientId     = '@lab.CloudCredential(WWLM365E7).ClientId'
$ClientSecret = '@lab.CloudCredential(WWLM365E7).ClientSecret'
$LearnerUpn   = '@lab.Variable(LearnerUpn)'
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
function Invoke-Graph {
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
$script:PrivilegedAuthAdminRoleId = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13'   # constant in every tenant
function Invoke-TapPolicy {
param(
[Parameter(Mandatory)][string]$TenantId,
[Parameter(Mandatory)][string]$ClientId,
[Parameter(Mandatory)][string]$ClientSecret,
[int]$LifetimeMinutes = 480,
[switch]$AssignPrivilegedAuthAdmin
)
Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
$roleCreated = $false
if ($AssignPrivilegedAuthAdmin) {
$spId = (Invoke-Graph -Path "/servicePrincipals(appId='$ClientId')?`$select=id").id
$has = @((Invoke-Graph -Path "/roleManagement/directory/roleAssignments?`$filter=principalId eq '$spId' and roleDefinitionId eq '$script:PrivilegedAuthAdminRoleId'").value)
if (-not $has) {
Invoke-Graph -Method POST -Path '/roleManagement/directory/roleAssignments' -Body @{
principalId = $spId; roleDefinitionId = $script:PrivilegedAuthAdminRoleId; directoryScopeId = '/'
} | Out-Null
$roleCreated = $true
}
}
Invoke-Graph -Method PATCH -Path '/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/temporaryAccessPass' -Body @{
'@odata.type'            = '#microsoft.graph.temporaryAccessPassAuthenticationMethodConfiguration'
state                    = 'enabled'
isUsableOnce             = $false
defaultLength            = 8
defaultLifetimeInMinutes = $LifetimeMinutes
minimumLifetimeInMinutes = 60
maximumLifetimeInMinutes = $LifetimeMinutes
includeTargets           = @(@{ targetType = 'group'; id = 'all_users'; isRegistrationRequired = $false })
} | Out-Null
if ($roleCreated) { Start-Sleep -Seconds 30 }   # a new role assignment takes a moment to apply
}
# ===== Run =====
Invoke-TapPolicy -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret