<#
.SYNOPSIS
  Grants the cloud credential's app the Microsoft Graph application permissions the lab needs, in ONE
  tenant, signed in interactively as that tenant's admin. For testing only: every Skillable launch gets a
  fresh tenant, so the lasting fix is Skillable adding these permissions to the credential template.

.DESCRIPTION
  Needs the Microsoft.Graph.Applications module (installed for the current user if missing). The admin
  signs in through the normal Microsoft sign-in window; no password goes into this script. Permissions
  the app already has are skipped. New tokens carry the permissions after a few minutes.

.EXAMPLE
  ./tools/Grant-GraphPermissions.ps1 -TenantId <tenant id> -ClientId <ClientId of the cloud credential>
#>
param(
    [Parameter(Mandatory)][string]$TenantId,
    # The app behind the lab's cloud credential (Studio > lab profile > Cloud tab, or the ClientId in Lab Access).
    [Parameter(Mandatory)][string]$ClientId,
    # Only if our TAP scripts (skillable/optional) replace the lab's own TAP action.
    [switch]$IncludeTap
)
$ErrorActionPreference = 'Stop'
$needed = @('User.ReadWrite.All', 'Mail.ReadWrite', 'Calendars.ReadWrite', 'MailboxSettings.ReadWrite', 'Files.ReadWrite.All',
    'Teamwork.Migrate.All', 'Group.ReadWrite.All', 'TeamMember.ReadWrite.All', 'ChannelMessage.Read.All', 'Organization.Read.All')
if ($IncludeTap) { $needed += @('UserAuthenticationMethod.ReadWrite.All', 'Policy.ReadWrite.AuthenticationMethod') }

if (-not (Get-Module -ListAvailable Microsoft.Graph.Applications)) {
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Applications
Connect-MgGraph -TenantId $TenantId -Scopes 'Application.Read.All', 'AppRoleAssignment.ReadWrite.All' -NoWelcome

$graph = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$sp = Get-MgServicePrincipal -Filter "appId eq '$ClientId'"
if (-not $sp) { throw "No app with client ID $ClientId in tenant $TenantId. Check the ClientId of the lab's cloud credential." }
Write-Host "App: $($sp.DisplayName) ($ClientId)"

$have = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All | Where-Object ResourceId -eq $graph.Id | ForEach-Object AppRoleId)
foreach ($perm in $needed) {
    $role = $graph.AppRoles | Where-Object { $_.Value -eq $perm -and $_.AllowedMemberTypes -contains 'Application' }
    if (-not $role) { Write-Warning "$perm is not a Graph application permission in this tenant; skipped."; continue }
    if ($have -contains $role.Id) { Write-Host "  already granted  $perm"; continue }
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $graph.Id -AppRoleId $role.Id | Out-Null
    Write-Host "  granted          $perm" -ForegroundColor Green
}
Disconnect-MgGraph | Out-Null
Write-Host 'Done. Wait about 5 minutes before running the life cycle action again (new tokens pick up the permissions).'
