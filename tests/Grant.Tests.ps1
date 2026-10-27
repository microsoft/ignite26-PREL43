# The Grant step: grants the cloud credential's app missing Graph permissions as the tenant admin.
# Sign-in, token roles and the admin's Graph calls are mocked; nothing leaves the machine.
BeforeAll {
    $src = Join-Path $PSScriptRoot '..' 'src'
    . (Join-Path $src 'common/Graph.ps1')
    . (Join-Path $src 'lifecycle/Preflight.ps1')
    . (Join-Path $src 'lifecycle/Grant.ps1')
    $script:AllRoles = @('User.ReadWrite.All', 'Mail.ReadWrite', 'Calendars.ReadWrite', 'MailboxSettings.ReadWrite', 'Files.ReadWrite.All',
        'Teamwork.Migrate.All', 'Group.ReadWrite.All', 'TeamMember.ReadWrite.All', 'ChannelMessage.Read.All', 'Organization.Read.All')
    $script:Cred = @{ TenantId = 't'; ClientId = 'app-1'; ClientSecret = 's' }
    # Admin's view of the tenant: Graph's app roles, the credential's service principal, its assignments.
    function Invoke-FakeAdminGraph($Method, $Uri, $Body) {
        if ($Uri -match "appId eq '00000003") {
            return @{ value = @(@{ id = 'graph-sp'; appRoles = @($script:AllRoles + 'UserAuthenticationMethod.ReadWrite.All' | ForEach-Object { @{ id = "role-$_"; value = $_; allowedMemberTypes = @('Application') } }) }) }
        }
        if ($Uri -match "appId eq 'app-1'") { return @{ value = @(@{ id = 'app-sp'; displayName = 'ScoringApp' }) } }
        if ($Uri -match '/appRoleAssignments$' -and $Method -eq 'GET') { return @{ value = @($script:Roles | ForEach-Object { @{ resourceId = 'graph-sp'; appRoleId = "role-$_" } }) } }
        if ($Uri -match '/appRoleAssignments$' -and $Method -eq 'POST') {
            $script:Posted += ($Body | ConvertFrom-Json).appRoleId -replace '^role-', ''
            return @{}
        }
        throw "unexpected $Method $Uri"
    }
}

Describe 'Grant step' {
    BeforeEach {
        $script:Posted = @()
        Mock Connect-Graph { }
        Mock Get-GraphToken { 'app-token' }
        Mock Get-GraphRoles { $script:Roles }
        Mock Start-Sleep { }
    }
    It 'does nothing (and needs no admin) when the credential already has every permission' {
        $script:Roles = $script:AllRoles
        Mock Invoke-RestMethod { throw 'no admin calls expected' }
        $out = Invoke-PermissionGrant @Cred
        "$out" | Should -Match 'already granted'
        Should -Invoke Invoke-RestMethod -Times 0
    }
    It 'stops with the missing list when no admin sign-in is configured (token left unfilled)' {
        $script:Roles = @('User.ReadWrite.All')
        { Invoke-PermissionGrant @Cred -AdminUser 'admin@x.onmicrosoft.com' -AdminPassword '@lab.CloudCredential(X).Password' } |
            Should -Throw '*lacks Mail.ReadWrite*no tenant admin sign-in*'
    }
    It 'grants only the missing permissions, then waits until the app token has them' {
        $script:Roles = @('User.ReadWrite.All', 'Files.ReadWrite.All', 'Group.ReadWrite.All', 'TeamMember.ReadWrite.All')
        Mock Invoke-RestMethod {
            if ($Uri -match '/oauth2/token$') { return @{ access_token = 'admin-token' } }
            $r = Invoke-FakeAdminGraph $Method $Uri $Body
            if ($Method -eq 'POST') { $script:Roles = @($script:Roles) + $script:Posted[-1] }
            return $r
        }
        $out = Invoke-PermissionGrant @Cred -AdminUser 'admin@x.onmicrosoft.com' -AdminPassword 'pw'
        $script:Posted | Sort-Object | Should -Be (@('Calendars.ReadWrite', 'ChannelMessage.Read.All', 'Mail.ReadWrite', 'MailboxSettings.ReadWrite', 'Organization.Read.All', 'Teamwork.Migrate.All') | Sort-Object)
        "$out" | Should -Match 'Permissions active'
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -match '/oauth2/token$' -and $Body.username -eq 'admin@x.onmicrosoft.com' -and $Body.grant_type -eq 'password' }
    }
    It 'does not ask for TAP permissions unless -IncludeTap' {
        $script:Roles = $script:AllRoles
        Get-MissingPermissions | Should -BeNullOrEmpty
        Get-MissingPermissions -IncludeTap | Should -Contain 'UserAuthenticationMethod.ReadWrite.All'
    }
    It 'says plainly when the admin account needs MFA' {
        $script:Roles = @('User.ReadWrite.All')
        Mock Invoke-RestMethod { throw [System.Exception]::new('AADSTS50076: Due to a configuration change made by your administrator, you must use multi-factor authentication') }
        { Invoke-PermissionGrant @Cred -AdminUser 'admin@x.onmicrosoft.com' -AdminPassword 'pw' } | Should -Throw '*requires MFA*'
    }
    It 'gives up with a clear message if the permissions never reach the token' {
        $script:Roles = @('User.ReadWrite.All', 'Files.ReadWrite.All', 'Group.ReadWrite.All', 'TeamMember.ReadWrite.All')
        Mock Invoke-RestMethod { if ($Uri -match '/oauth2/token$') { return @{ access_token = 'admin-token' } }; Invoke-FakeAdminGraph $Method $Uri $Body }
        { Invoke-PermissionGrant @Cred -AdminUser 'admin@x.onmicrosoft.com' -AdminPassword 'pw' -WaitSeconds -1 } | Should -Throw '*still lacks*'
    }
}
