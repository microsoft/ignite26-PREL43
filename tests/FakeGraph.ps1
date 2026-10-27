# ---------------------------------------------------------------------------------------------
# In-memory Microsoft 365 tenant for tests. Dot-source AFTER src/common/Graph.ps1: it replaces
# Connect-Graph, Get-GraphRoles, Invoke-Graph, Get-GraphAll and Get-GraphBytes with versions that
# serve the endpoints the Skillable scripts call. It enforces the Graph rules that matter here:
# Teams import refuses future timestamps, transactionId de-duplicates events, one TAP per user,
# 409 on duplicate team members, 404s for unknown objects.
# ---------------------------------------------------------------------------------------------

$script:AllRoles = @('User.ReadWrite.All', 'Mail.ReadWrite', 'Calendars.ReadWrite', 'MailboxSettings.ReadWrite', 'Files.ReadWrite.All',
    'Teamwork.Migrate.All', 'Group.ReadWrite.All', 'TeamMember.ReadWrite.All', 'ChannelMessage.Read.All',
    'UserAuthenticationMethod.ReadWrite.All', 'Policy.ReadWrite.AuthenticationMethod', 'RoleManagement.ReadWrite.Directory', 'Application.Read.All',
    'Organization.Read.All')

function New-FakeId { return [guid]::NewGuid().ToString() }

function New-FakeTenant {
    param([int]$LicensedUsers = 9, [string[]]$Roles = $script:AllRoles, [switch]$NoLearnerMailbox,
        # The Office 365 admin without a licence or mailbox (as in a fresh Skillable tenant), and free E7 seats.
        [switch]$AdminUnlicensed, [int]$FreeSeats = 0)
    $t = @{
        Domain = 'lab.test'; Roles = $Roles; Users = [ordered]@{}; Mail = @{}; Events = @{}; Groups = [ordered]@{}
        Drives = @{}; UserDrive = @{}; Tap = @{}; TapPolicy = $null; RoleAssignments = @(); Calls = 0; FailNext = $null
        Skus = @(@{ skuId = 'e7-sku'; skuPartNumber = 'Microsoft_365_E7'; seats = 0
                servicePlans = @(@{ servicePlanName = 'EXCHANGE_S_ENTERPRISE' }, @{ servicePlanName = 'M365_COPILOT_APPS' }) })
    }
    $script:FakeTenant = $t
    $sku = @(@{ skuId = 'e7-sku' })
    $learner = Add-FakeUser -Upn 'labuser@lab.test' -Name 'Asha Kumar' -Given 'Asha' -Surname 'Kumar' -Licences $sku -Mailbox:(-not $NoLearnerMailbox)
    $names = 'AlexW', 'MeganB', 'NestorW', 'PattiF', 'LeeG', 'LidiaH', 'JohannaL', 'DiegoS', 'IsaiahL', 'LynneR', 'GradyA'
    for ($i = 0; $i -lt $LicensedUsers; $i++) {
        [void](Add-FakeUser -Upn "$($names[$i])@lab.test" -Name $names[$i] -Given $names[$i] -Surname 'Fictional' -Licences $sku -Mailbox)
    }
    [void](Add-FakeUser -Upn 'admin@lab.test' -Name 'MOD Administrator' -Given 'MOD' -Surname 'Administrator' -Licences $(if ($AdminUnlicensed) { @() } else { $sku }) -Mailbox:(-not $AdminUnlicensed))
    $t.Skus[0].seats = @($t.Users.Values | Where-Object { @($_.assignedLicenses).Count }).Count + $FreeSeats
    return $learner
}

function Add-FakeUser {
    param([string]$Upn, [string]$Name, [string]$Given, [string]$Surname, $Licences = @(), [switch]$Mailbox, [bool]$Enabled = $true)
    $id = New-FakeId
    $u = @{ id = $id; userPrincipalName = $Upn; displayName = $Name; givenName = $Given; surname = $Surname; userType = 'Member'
        accountEnabled = $Enabled; assignedLicenses = @($Licences | Where-Object { $_ }); employeeId = $null; companyName = $null; mailbox = [bool]$Mailbox; manager = $null; photo = $false
        usageLocation = $(if (@($Licences | Where-Object { $_ }).Count) { 'IN' } else { $null }) }
    $script:FakeTenant.Users[$id] = $u
    $script:FakeTenant.Mail[$id] = @{ inbox = [System.Collections.Generic.List[object]]::new(); drafts = [System.Collections.Generic.List[object]]::new(); sentitems = [System.Collections.Generic.List[object]]::new() }
    $script:FakeTenant.Events[$id] = [System.Collections.Generic.List[object]]::new()
    return $u
}

function Find-FakeUser([string]$Key) {
    $k = [uri]::UnescapeDataString($Key)
    if ($k -match "^\(appId='") { return $null }
    if ($script:FakeTenant.Users.Contains($k)) { return $script:FakeTenant.Users[$k] }
    foreach ($u in $script:FakeTenant.Users.Values) { if ($u.userPrincipalName -ieq $k) { return $u } }
    return $null
}

function Get-FakeUserDrive([string]$UserId) {
    $t = $script:FakeTenant
    if (-not $t.UserDrive.ContainsKey($UserId)) {
        $d = New-FakeId; $t.Drives[$d] = @{ id = $d; root = (New-FakeId); items = [System.Collections.Generic.List[object]]::new() }
        $t.UserDrive[$UserId] = $d
    }
    return $t.Drives[$t.UserDrive[$UserId]]
}

function Add-FakeDriveItem {
    param($Drive, [string]$ParentId, [string]$Name, [byte[]]$Content, [switch]$Folder)
    $existing = $Drive.items | Where-Object { $_.parentId -eq $ParentId -and $_.name -eq $Name } | Select-Object -First 1
    if ($existing) {
        if (-not $Folder) { $existing.content = $Content; $existing.size = $Content.Length; $existing.lastModifiedDateTime = (Get-Date).ToUniversalTime().ToString('o') }
        return $existing
    }
    $it = @{ id = (New-FakeId); name = $Name; parentId = $ParentId; lastModifiedDateTime = (Get-Date).ToUniversalTime().ToString('o')
        parentReference = @{ driveId = $Drive.id; id = $ParentId } }
    if ($Folder) { $it.folder = @{ childCount = 0 } } else { $it.file = @{}; $it.content = $Content; $it.size = $Content.Length }
    $Drive.items.Add($it)
    return $it
}

function Get-FakeQuery([string]$Query) {
    $q = @{}
    foreach ($pair in ($Query -split '&')) {
        if (-not $pair) { continue }
        $kv = $pair -split '=', 2
        $q[[uri]::UnescapeDataString($kv[0])] = if ($kv.Count -gt 1) { [uri]::UnescapeDataString($kv[1]) } else { '' }
    }
    return $q
}

function Throw-Fake([int]$Status, [string]$Message) { throw [GraphError]::new("FAKE -> $Status $Message", $Status, "fake$Status") }

function ConvertTo-FakeUtc($DateTime, [string]$TimeZone) {
    $dt = [datetime]::Parse($DateTime, [Globalization.CultureInfo]::InvariantCulture)
    if ($TimeZone -and $TimeZone -ne 'UTC') { return [TimeZoneInfo]::ConvertTimeToUtc([datetime]::SpecifyKind($dt, 'Unspecified'), (Get-EventTimeZone $TimeZone)) }
    return [datetime]::SpecifyKind($dt, 'Utc')
}

function Connect-Graph { param($TenantId, $ClientId, $ClientSecret) $script:GraphAuth = @{ Token = 'fake' } }
function Get-GraphToken { return 'fake' }
function Get-GraphRoles { return @($script:FakeTenant.Roles) }

function Get-GraphAll {
    param([Parameter(Mandatory)][string]$Path, [hashtable]$Headers, [int]$Limit = 0)
    $r = Invoke-Graph -Path $Path -Headers $Headers
    $v = @($r.value)
    if ($Limit -gt 0 -and $v.Count -gt $Limit) { $v = $v[0..($Limit - 1)] }
    return $v
}

function Get-GraphBytes {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -notmatch '^/drives/([^/]+)/items/([^/]+)/content$') { Throw-Fake 400 "bytes $Path" }
    $it = $script:FakeTenant.Drives[$Matches[1]].items | Where-Object { $_.id -eq $Matches[2] }
    return , [byte[]]$it.content
}

function Invoke-Graph {
    param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, $Body, [byte[]]$Bytes, [string]$ContentType,
        [hashtable]$Headers, [switch]$Ok404, [switch]$Raw, [int]$MaxRetries = 8)
    $t = $script:FakeTenant
    $t.Calls++
    if ($t.FailNext -and $Path -match $t.FailNext) { $t.FailNext = $null; Throw-Fake 503 'injected failure' }
    if ($Body -is [string]) { $Body = $Body | ConvertFrom-Json -AsHashtable }
    $path, $query = $Path -split '\?', 2
    $q = Get-FakeQuery $query
    try { return (Invoke-FakeRoute -Method $Method -Path $path -Q $q -Body $Body -Bytes $Bytes -Raw:$Raw) }
    catch [GraphError] { if ($_.Exception.Status -eq 404 -and $Ok404) { return $null } throw }
}

function Invoke-FakeRoute {
    param([string]$Method, [string]$Path, [hashtable]$Q, $Body, [byte[]]$Bytes, [switch]$Raw)
    $t = $script:FakeTenant
    $now = (Get-Date).ToUniversalTime()
    switch -Regex ("$Method $Path") {
        '^GET /organization$' { return @{ value = @(@{ verifiedDomains = @(@{ name = $t.Domain; isDefault = $true }) }) } }

        # ---------------- licences
        '^GET /subscribedSkus$' {
            return @{ value = @($t.Skus | ForEach-Object {
                        $id = $_.skuId
                        $used = @($t.Users.Values | Where-Object { @($_.assignedLicenses | Where-Object { $_.skuId -eq $id }).Count }).Count
                        @{ skuId = $id; skuPartNumber = $_.skuPartNumber; servicePlans = $_.servicePlans; prepaidUnits = @{ enabled = $_.seats }; consumedUnits = $used } }) }
        }
        '^POST /users/([^/]+)/assignLicense$' {
            $u = Find-FakeUser $Matches[1]; if (-not $u) { Throw-Fake 404 'user' }
            $remove = @($Body.removeLicenses)
            $add = @($Body.addLicenses | Where-Object { $_ })
            if ($add -and -not $u.usageLocation) { Throw-Fake 400 'License assignment failed because service plans require a usage location.' }
            foreach ($a in $add) {
                $s = $t.Skus | Where-Object skuId -eq $a.skuId
                $used = @($t.Users.Values | Where-Object { @($_.assignedLicenses | Where-Object { $_.skuId -eq $a.skuId }).Count }).Count
                if ($used -ge $s.seats) { Throw-Fake 400 'License assignment cannot be done because there are not enough licenses available.' }
            }
            $u.assignedLicenses = @(@($u.assignedLicenses | Where-Object { $remove -notcontains $_.skuId }) + @($add | ForEach-Object { @{ skuId = $_.skuId } }))
            if ($add) { $u.mailbox = $true }   # a licensed user gets a mailbox (immediately, in the fake)
            return $u.Clone()
        }

        # ---------------- users
        '^GET /users$' { return @{ value = @($t.Users.Values | ForEach-Object { $_.Clone() }) } }
        '^POST /users$' {
            if (Find-FakeUser $Body.userPrincipalName) { Throw-Fake 400 'Another object with the same value for property userPrincipalName already exists.' }
            $u = Add-FakeUser -Upn $Body.userPrincipalName -Name $Body.displayName -Given $Body.givenName -Surname $Body.surname -Enabled ([bool]$Body.accountEnabled)
            foreach ($k in 'jobTitle', 'department', 'officeLocation', 'companyName', 'employeeId') { if ($Body.ContainsKey($k)) { $u[$k] = $Body[$k] } }
            return $u.Clone()
        }
        "^GET /servicePrincipals\(appId='([^']+)'\)$" { return @{ id = 'sp-' + $Matches[1] } }
        '^GET /users/([^/]+)$' { $u = Find-FakeUser $Matches[1]; if (-not $u) { Throw-Fake 404 'user' } return $u.Clone() }
        '^PATCH /users/([^/]+)$' { $u = Find-FakeUser $Matches[1]; if (-not $u) { Throw-Fake 404 'user' } foreach ($k in $Body.Keys) { $u[$k] = $Body[$k] } return @{} }
        '^PUT /users/([^/]+)/manager/\$ref$' { $u = Find-FakeUser $Matches[1]; $u.manager = ($Body.'@odata.id' -split '/')[-1]; return @{} }
        '^PUT /users/([^/]+)/photo/\$value$' { $u = Find-FakeUser $Matches[1]; if (-not $u.mailbox) { Throw-Fake 404 'mailbox' } $u.photo = $true; return @{} }
        '^GET /users/([^/]+)/mailboxSettings$' { $u = Find-FakeUser $Matches[1]; if (-not $u -or -not $u.mailbox) { Throw-Fake 404 'MailboxNotEnabledForRESTAPI' } return @{ timeZone = $u.timeZone } }
        '^PATCH /users/([^/]+)/mailboxSettings$' { $u = Find-FakeUser $Matches[1]; $u.timeZone = $Body.timeZone; return @{} }

        # ---------------- mail
        '^GET /users/([^/]+)/messages$' {
            $u = Find-FakeUser $Matches[1]
            if ($Q['$filter'] -match "internetMessageId eq '(.+)'$") {
                $want = $Matches[1].Replace("''", "'")
                return @{ value = @($t.Mail[$u.id].Values | ForEach-Object { $_ } | Where-Object { $_.internetMessageId -eq $want }) }
            }
            return @{ value = @($t.Mail[$u.id].Values | ForEach-Object { $_ }) }
        }
        '^POST /users/([^/]+)/mailFolders/([^/]+)/messages$' {
            $u = Find-FakeUser $Matches[1]; $folder = $Matches[2]
            if (-not $u.mailbox) { Throw-Fake 404 'mailbox' }
            $props = @{}; foreach ($p in @($Body.singleValueExtendedProperties)) { if ($p) { $props[$p.id] = $p.value } }
            $m = @{ id = (New-FakeId); '@odata.type' = '#microsoft.graph.message'; subject = $Body.subject; body = $Body.body
                bodyPreview = ([regex]::Replace("$($Body.body.content)", '<[^>]+>', ' ')).Substring(0, [math]::Min(200, ([regex]::Replace("$($Body.body.content)", '<[^>]+>', ' ')).Length))
                isRead = ($props['Integer 0x0E07'] -eq '1'); isDraft = ($folder -eq 'drafts' -and -not $props['Integer 0x0E07'])
                internetMessageId = $props['String 0x1035']; conversationId = $(if ($props['String 0x0070']) { 'conv-' + $props['String 0x0070'] } else { New-FakeId })
                receivedDateTime = $(if ($props['SystemTime 0x0E06']) { $props['SystemTime 0x0E06'] } else { $now.ToString('o') }); from = $Body.from }
            $t.Mail[$u.id][$folder].Add($m)
            return @{ id = $m.id }
        }
        '^PATCH /users/([^/]+)/messages/([^/]+)$' {
            $u = Find-FakeUser $Matches[1]; $mid = $Matches[2]
            foreach ($f in $t.Mail[$u.id].Values) { foreach ($m in $f) { if ($m.id -eq $mid) { foreach ($k in $Body.Keys) { $m[$k] = $Body[$k] } } } }
            return @{}
        }
        '^DELETE /users/([^/]+)/messages/([^/]+)$' {
            $u = Find-FakeUser $Matches[1]; $mid = $Matches[2]; $found = $false
            foreach ($f in $t.Mail[$u.id].Values) { $hit = $f | Where-Object { $_.id -eq $mid }; if ($hit) { [void]$f.Remove($hit); $found = $true } }
            if (-not $found) { Throw-Fake 404 'message' }
            return @{}
        }
        '^GET /users/([^/]+)/mailFolders/([^/]+)/messages$' {
            $u = Find-FakeUser $Matches[1]
            return @{ value = @($t.Mail[$u.id][$Matches[2]] | Sort-Object { $_.receivedDateTime } -Descending | ForEach-Object { $_.Clone() }) }
        }

        # ---------------- calendar
        '^POST /users/([^/]+)/calendar/events$' {
            $org = Find-FakeUser $Matches[1]
            if (-not $org.mailbox) { Throw-Fake 404 'organiser mailbox' }
            $dup = $t.Events[$org.id] | Where-Object { $Body.transactionId -and $_.transactionId -eq $Body.transactionId } | Select-Object -First 1
            if ($dup) { return @{ id = $dup.id; iCalUId = $dup.iCalUId } }
            $ical = 'ical-' + (New-FakeId)
            $s = ConvertTo-FakeUtc $Body.start.dateTime $Body.start.timeZone; $e = ConvertTo-FakeUtc $Body.end.dateTime $Body.end.timeZone
            $ev = @{ id = (New-FakeId); iCalUId = $ical; subject = $Body.subject; transactionId = $Body.transactionId; startUtc = $s; endUtc = $e; isCancelled = $false; responseStatus = @{ response = 'organizer' } }
            $t.Events[$org.id].Add($ev)
            foreach ($a in @($Body.attendees)) {
                $att = Find-FakeUser $a.emailAddress.address
                if ($att -and $att.mailbox) {
                    $t.Events[$att.id].Add(@{ id = (New-FakeId); iCalUId = $ical; subject = $Body.subject; startUtc = $s; endUtc = $e; isCancelled = $false; responseStatus = @{ response = 'notResponded' } })
                    $t.Mail[$att.id].inbox.Add(@{ id = (New-FakeId); '@odata.type' = '#microsoft.graph.eventMessageRequest'; subject = $Body.subject; body = @{ content = '' }; bodyPreview = ''; receivedDateTime = $now.ToString('o'); conversationId = (New-FakeId) })
                }
            }
            return @{ id = $ev.id; iCalUId = $ical }
        }
        '^GET /users/([^/]+)/events$' {
            $u = Find-FakeUser $Matches[1]
            if ($Q['$filter'] -match "iCalUId eq '(.+)'$") { return @{ value = @($t.Events[$u.id] | Where-Object { $_.iCalUId -eq $Matches[1] }) } }
            return @{ value = @($t.Events[$u.id]) }
        }
        '^POST /users/([^/]+)/events/([^/]+)/accept$' {
            $u = Find-FakeUser $Matches[1]; $ev = $t.Events[$u.id] | Where-Object { $_.id -eq $Matches[2] }
            if (-not $ev) { Throw-Fake 404 'event' } $ev.responseStatus = @{ response = 'accepted' }; return @{}
        }
        '^GET /users/([^/]+)/calendarView$' {
            $u = Find-FakeUser $Matches[1]
            $s = [datetime]::Parse($Q['startDateTime'], [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal')
            $e = [datetime]::Parse($Q['endDateTime'], [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal')
            $v = @($t.Events[$u.id] | Where-Object { $_.startUtc -lt $e -and $_.endUtc -gt $s } | ForEach-Object {
                    @{ id = $_.id; subject = $_.subject; isCancelled = $_.isCancelled
                        start = @{ dateTime = $_.startUtc.ToString('yyyy-MM-ddTHH:mm:ss.0000000'); timeZone = 'UTC' }
                        end = @{ dateTime = $_.endUtc.ToString('yyyy-MM-ddTHH:mm:ss.0000000'); timeZone = 'UTC' } } })
            return @{ value = $v }
        }

        # ---------------- groups and teams
        '^GET /groups$' {
            $want = if ($Q['$filter'] -match "displayName eq '(.+)'$") { $Matches[1].Replace("''", "'") } else { $null }
            return @{ value = @($t.Groups.Values | Where-Object { -not $want -or $_.displayName -eq $want } | ForEach-Object { @{ id = $_.id; displayName = $_.displayName } }) }
        }
        '^GET /groups/([^/]+)/extensions/([^/]+)$' {
            $g = $t.Groups[$Matches[1]]; if (-not $g -or -not $g.extensions.ContainsKey($Matches[2])) { Throw-Fake 404 'extension' } return $g.extensions[$Matches[2]]
        }
        '^POST /groups/([^/]+)/extensions$' { $t.Groups[$Matches[1]].extensions[$Body.extensionName] = $Body; return $Body }
        '^DELETE /groups/([^/]+)$' { if (-not $t.Groups.Contains($Matches[1])) { Throw-Fake 404 'group' } $t.Groups.Remove($Matches[1]); return @{} }
        '^POST /teams$' {
            $id = New-FakeId; $op = New-FakeId
            $general = @{ id = (New-FakeId); displayName = 'General'; messages = [System.Collections.Generic.List[object]]::new(); migrated = $false }
            $t.Groups[$id] = @{ id = $id; displayName = $Body.displayName; visibility = $Body.visibility; extensions = @{}; channels = [System.Collections.Generic.List[object]]::new()
                members = [System.Collections.Generic.List[object]]::new(); migrated = $false; drive = $null; migrationMode = $Body.'@microsoft.graph.teamCreationMode' }
            $t.Groups[$id].channels.Add($general)
            return [pscustomobject]@{ Status = 202; Headers = @{ Location = @("/teams('$id')/operations('$op')") }; Content = '' }
        }
        '^GET /teams/([^/]+)/operations/([^/]+)$' { return @{ status = 'succeeded' } }
        '^GET /teams/([^/]+)$' { if (-not $t.Groups.Contains($Matches[1])) { Throw-Fake 404 'team' } return @{ id = $Matches[1] } }
        '^POST /teams/([^/]+)/channels$' {
            $ch = @{ id = '19:' + (New-FakeId); displayName = $Body.displayName; messages = [System.Collections.Generic.List[object]]::new(); migrated = $false }
            $t.Groups[$Matches[1]].channels.Add($ch); return @{ id = $ch.id }
        }
        '^GET /teams/([^/]+)/channels$' { return @{ value = @($t.Groups[$Matches[1]].channels | ForEach-Object { @{ id = $_.id; displayName = $_.displayName } }) } }
        '^POST /teams/([^/]+)/channels/([^/]+)/messages$' {
            $g = $t.Groups[$Matches[1]]; $ch = $g.channels | Where-Object { $_.id -eq $Matches[2] }
            if ($ch.migrated) { Throw-Fake 403 'channel is not in migration mode' }
            if ([datetime]::Parse($Body.createdDateTime, [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal') -gt $now) { Throw-Fake 400 'createdDateTime cannot be in the future' }
            if (-not (Find-FakeUser $Body.from.user.id)) { Throw-Fake 400 'from user not found' }
            $m = @{ id = (New-FakeId); body = $Body.body; from = $Body.from; replies = [System.Collections.Generic.List[object]]::new() }
            $ch.messages.Add($m); return @{ id = $m.id }
        }
        '^POST /teams/([^/]+)/channels/([^/]+)/messages/([^/]+)/replies$' {
            $g = $t.Groups[$Matches[1]]; $ch = $g.channels | Where-Object { $_.id -eq $Matches[2] }; $p = $ch.messages | Where-Object { $_.id -eq $Matches[3] }
            if ([datetime]::Parse($Body.createdDateTime, [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal') -gt $now) { Throw-Fake 400 'createdDateTime cannot be in the future' }
            $r = @{ id = (New-FakeId); body = $Body.body; from = $Body.from }; $p.replies.Add($r); return @{ id = $r.id }
        }
        '^POST /teams/([^/]+)/channels/([^/]+)/completeMigration$' {
            $ch = $t.Groups[$Matches[1]].channels | Where-Object { $_.id -eq $Matches[2] }
            if ($ch.migrated) { Throw-Fake 400 'Channel is not in migration mode' } $ch.migrated = $true; return @{}
        }
        '^POST /teams/([^/]+)/completeMigration$' {
            $g = $t.Groups[$Matches[1]]
            if ($g.migrated) { Throw-Fake 400 'Team is not in migration mode' }
            if ($g.channels | Where-Object { -not $_.migrated }) { Throw-Fake 400 'channels still in migration' }
            $g.migrated = $true; return @{}
        }
        '^POST /teams/([^/]+)/members$' {
            $g = $t.Groups[$Matches[1]]
            if (-not $g.migrated) { Throw-Fake 400 'team still in migration mode' }
            $uid = [regex]::Match($Body.'user@odata.bind', "users\('([^']+)'\)").Groups[1].Value
            if ($g.members | Where-Object { $_.id -eq $uid }) { Throw-Fake 409 'member exists' }
            $g.members.Add(@{ id = $uid; roles = $Body.roles }); return @{}
        }
        '^GET /teams/([^/]+)/channels/([^/]+)/messages$' {
            $ch = $t.Groups[$Matches[1]].channels | Where-Object { $_.id -eq $Matches[2] }
            return @{ value = @($ch.messages | ForEach-Object { @{ id = $_.id; body = $_.body; replies = @($_.replies) } }) }
        }
        '^GET /teams/([^/]+)/channels/([^/]+)/filesFolder$' {
            $g = $t.Groups[$Matches[1]]
            if (-not $g.migrated) { Throw-Fake 404 'files folder not ready' }
            if (-not $g.drive) { $d = New-FakeId; $t.Drives[$d] = @{ id = $d; root = (New-FakeId); items = [System.Collections.Generic.List[object]]::new() }; $g.drive = $d }
            $drive = $t.Drives[$g.drive]
            $ch = $g.channels | Where-Object { $_.id -eq $Matches[2] }
            $folder = Add-FakeDriveItem -Drive $drive -ParentId $drive.root -Name $ch.displayName -Folder
            return @{ id = $folder.id; name = $folder.name; parentReference = @{ driveId = $drive.id } }
        }

        # ---------------- drives
        '^GET /drives/([^/]+)/items/([^/:]+):/([^/:]+)$' {
            $d = $t.Drives[$Matches[1]]; $name = [uri]::UnescapeDataString($Matches[3])
            $it = $d.items | Where-Object { $_.parentId -eq $Matches[2] -and $_.name -eq $name } | Select-Object -First 1
            if (-not $it) { Throw-Fake 404 'item' } return $it
        }
        '^POST /drives/([^/]+)/items/([^/]+)/children$' {
            $d = $t.Drives[$Matches[1]]
            if ($d.items | Where-Object { $_.parentId -eq $Matches[2] -and $_.name -eq $Body.name }) { Throw-Fake 409 'nameAlreadyExists' }
            return (Add-FakeDriveItem -Drive $d -ParentId $Matches[2] -Name $Body.name -Folder)
        }
        '^PUT /drives/([^/]+)/items/([^/:]+):/([^/:]+):/content$' {
            $d = $t.Drives[$Matches[1]]
            return (Add-FakeDriveItem -Drive $d -ParentId $Matches[2] -Name ([uri]::UnescapeDataString($Matches[3])) -Content $Bytes)
        }
        '^GET /drives/([^/]+)/items/([^/]+)/children$' {
            $d = $t.Drives[$Matches[1]]; return @{ value = @($d.items | Where-Object { $_.parentId -eq $Matches[2] }) }
        }
        '^GET /users/([^/]+)/drive$' {
            $u = Find-FakeUser $Matches[1]; if (-not $u -or @($u.assignedLicenses).Count -eq 0) { Throw-Fake 404 'drive' }
            $d = Get-FakeUserDrive $u.id; return @{ id = $d.id }
        }
        '^GET /drives/([^/]+)/root/delta$' {
            $d = $t.Drives[$Matches[1]]; return @{ value = @($d.items | ForEach-Object { $c = $_.Clone(); $c.Remove('content'); $c }) }
        }

        # ---------------- authentication methods
        '^PATCH /policies/authenticationMethodsPolicy/authenticationMethodConfigurations/temporaryAccessPass$' { $t.TapPolicy = $Body; return @{} }
        '^GET /roleManagement/directory/roleAssignments$' { return @{ value = @($t.RoleAssignments) } }
        '^POST /roleManagement/directory/roleAssignments$' { $t.RoleAssignments += $Body; return @{} }
        '^GET /users/([^/]+)/authentication/temporaryAccessPassMethods$' { $u = Find-FakeUser $Matches[1]; return @{ value = @($t.Tap[$u.id] | Where-Object { $_ }) } }
        '^DELETE /users/([^/]+)/authentication/temporaryAccessPassMethods/([^/]+)$' { $u = Find-FakeUser $Matches[1]; $t.Tap.Remove($u.id); return @{} }
        '^POST /users/([^/]+)/authentication/temporaryAccessPassMethods$' {
            if (-not $t.TapPolicy) { Throw-Fake 400 'TAP policy disabled' }
            $u = Find-FakeUser $Matches[1]; if ($t.Tap[$u.id]) { Throw-Fake 400 'user already has a TAP' }
            $t.Tap[$u.id] = @{ id = (New-FakeId); temporaryAccessPass = 'Tap!' + (Get-Random -Maximum 99999) }
            return $t.Tap[$u.id]
        }
        default { Throw-Fake 501 "fake Graph has no route for $Method $Path" }
    }
}

# ---------------- learner work, as Cowork would leave it

function New-FakeDocx([string]$Text) {
    $ms = [IO.MemoryStream]::new()
    $z = [IO.Compression.ZipArchive]::new($ms, [IO.Compression.ZipArchiveMode]::Create, $true)
    $e = $z.CreateEntry('word/document.xml'); $w = [IO.StreamWriter]::new($e.Open())
    $w.Write("<w:document><w:body><w:p><w:r><w:t>$([Security.SecurityElement]::Escape($Text))</w:t></w:r></w:p></w:body></w:document>"); $w.Dispose()
    $z.Dispose(); return , $ms.ToArray()
}

function New-FakeXlsx([string[]]$Cells) {
    $ms = [IO.MemoryStream]::new()
    $z = [IO.Compression.ZipArchive]::new($ms, [IO.Compression.ZipArchiveMode]::Create, $true)
    $e = $z.CreateEntry('xl/sharedStrings.xml'); $w = [IO.StreamWriter]::new($e.Open())
    $w.Write('<sst>' + (($Cells | ForEach-Object { "<si><t>$([Security.SecurityElement]::Escape($_))</t></si>" }) -join '') + '</sst>'); $w.Dispose()
    $z.Dispose(); return , $ms.ToArray()
}

function Add-FakeLearnerWork {
    <# Everything a learner who completes M1-M5 leaves behind (enough for 100 points). #>
    param($Learner, [datetime]$EventDayUtc)
    $t = $script:FakeTenant; $id = $Learner.id
    $t.Mail[$id].drafts.Add(@{ id = (New-FakeId); subject = 'RE: Helix sensor modules'; body = @{ content = 'Thanks Felix. Sent by Copilot Cowork' }; bodyPreview = ''; receivedDateTime = (Get-Date).ToUniversalTime().ToString('o') })
    $t.Mail[$id].inbox.Add(@{ id = (New-FakeId); '@odata.type' = '#microsoft.graph.message'; subject = 'Helix launch briefing - Thursday'; body = @{ content = 'Today' }; bodyPreview = ''; receivedDateTime = (Get-Date).ToUniversalTime().ToString('o') })
    foreach ($s in 'Helix messaging review', 'Helix launch checklist') {
        $start = $EventDayUtc.AddDays(1).AddHours(10)
        $t.Events[$id].Add(@{ id = (New-FakeId); iCalUId = (New-FakeId); subject = $s; startUtc = $start; endUtc = $start.AddMinutes(30); isCancelled = $false; responseStatus = @{ response = 'organizer' } })
    }
    $d = Get-FakeUserDrive $id
    $cowork = Add-FakeDriveItem -Drive $d -ParentId $d.root -Name 'Cowork' -Folder
    $skills = Add-FakeDriveItem -Drive $d -ParentId $cowork.id -Name 'skills' -Folder
    $lsr = Add-FakeDriveItem -Drive $d -ParentId $skills.id -Name 'launch-status-report' -Folder
    [void](Add-FakeDriveItem -Drive $d -ParentId $lsr.id -Name 'SKILL.md' -Content ([Text.Encoding]::UTF8.GetBytes('# Launch Status Report')))
    $mp = Add-FakeDriveItem -Drive $d -ParentId $skills.id -Name 'helix-meeting-prep' -Folder
    [void](Add-FakeDriveItem -Drive $d -ParentId $mp.id -Name 'brief-template.docx' -Content (New-FakeDocx 'Meeting brief template'))
    [void](Add-FakeDriveItem -Drive $d -ParentId $cowork.id -Name 'Helix-Risk-Register.xlsx' -Content (New-FakeXlsx @('Risk', 'Owner', 'Source evidence', 'UNCONFIRMED')))
    [void](Add-FakeDriveItem -Drive $d -ParentId $cowork.id -Name 'Helix-Status-2026-11-18.docx' -Content (New-FakeDocx 'Status: amber'))
    [void](Add-FakeDriveItem -Drive $d -ParentId $cowork.id -Name 'Skill-Inventory.docx' -Content (New-FakeDocx 'Skills'))
}
