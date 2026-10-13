<#
.SYNOPSIS
  Creates (or updates) the app registration the Hydration Kit runs as.

.DESCRIPTION
  Run once per tenant by a tenant administrator. The script:
    1. creates the "VectorSense Hydration Kit" app registration (single tenant),
    2. attaches the public certificate (no client secrets),
    3. requests and grants admin consent for the Microsoft Graph application
       permissions listed in app-permissions.json,
    4. assigns the User Administrator and License Administrator directory roles.
  It is idempotent: re-running updates the same app.

  It does not enable Cowork, create the seat group, link the Copilot Credits
  billing policy, configure the mail sink or the Temporary Access Pass policy.
  Those stay with the tenant owner (see docs/operator-guide.md, section 3).

.PARAMETER TenantId
  Directory (tenant) ID.

.PARAMETER CertificatePath
  Path to the PUBLIC certificate (.cer or .crt). Keep the private key in the key vault.

.EXAMPLE
  ./setup-app-registration.ps1 -TenantId 00000000-0000-0000-0000-000000000000 -CertificatePath ./vs-hydration.cer

.NOTES
  Requires the Microsoft.Graph PowerShell SDK:  Install-Module Microsoft.Graph -Scope CurrentUser
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $CertificatePath,
    [string] $ConfigPath = (Join-Path $PSScriptRoot 'app-permissions.json')
)

$ErrorActionPreference = 'Stop'
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$graphAppId = '00000003-0000-0000-c000-000000000000'

Connect-MgGraph -TenantId $TenantId -NoWelcome -Scopes @(
    'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'RoleManagement.ReadWrite.Directory')

# Resolve Microsoft Graph application permissions by name.
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
$roles = foreach ($name in $config.graphApplicationPermissions) {
    $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $name -and $_.AllowedMemberTypes -contains 'Application' }
    if (-not $role) { throw "Microsoft Graph application permission '$name' not found." }
    $role
}

# Certificate credential.
$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new((Resolve-Path $CertificatePath).Path)
$keyCredential = @{
    Type        = 'AsymmetricX509Cert'
    Usage       = 'Verify'
    Key         = $cert.RawData
    DisplayName = "vs-hydration $($cert.Thumbprint)"
}
$requiredAccess = @(@{
    ResourceAppId  = $graphAppId
    ResourceAccess = @($roles | ForEach-Object { @{ Id = $_.Id; Type = 'Role' } })
})

# App registration.
$app = Get-MgApplication -Filter "displayName eq '$($config.displayName)'" | Select-Object -First 1
if ($app) {
    Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $requiredAccess -KeyCredentials @($keyCredential)
    Write-Host "Updated app registration $($app.AppId)"
} else {
    $app = New-MgApplication -DisplayName $config.displayName -SignInAudience 'AzureADMyOrg' `
        -RequiredResourceAccess $requiredAccess -KeyCredentials @($keyCredential)
    Write-Host "Created app registration $($app.AppId)"
}

# Service principal and admin consent (app role assignments).
$sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'"
if (-not $sp) { $sp = New-MgServicePrincipal -AppId $app.AppId }
$granted = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All
foreach ($role in $roles) {
    if (-not ($granted | Where-Object { $_.AppRoleId -eq $role.Id })) {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id `
            -ResourceId $graphSp.Id -AppRoleId $role.Id | Out-Null
        Write-Host "  granted $($role.Value)"
    }
}

# Directory roles, nothing broader.
foreach ($roleName in $config.directoryRoles) {
    $def = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$roleName'"
    $has = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($sp.Id)' and roleDefinitionId eq '$($def.Id)'"
    if (-not $has) {
        New-MgRoleManagementDirectoryRoleAssignment -PrincipalId $sp.Id -RoleDefinitionId $def.Id -DirectoryScopeId '/' | Out-Null
        Write-Host "  assigned directory role $roleName"
    }
}

Write-Host ''
Write-Host 'Put these values in tenant.yaml:'
Write-Host "  tenant.id:      $TenantId"
Write-Host "  auth.client_id: $($app.AppId)"
Write-Host "  auth.certificate_path: <mounted PEM with private key and certificate, thumbprint $($cert.Thumbprint)>"
