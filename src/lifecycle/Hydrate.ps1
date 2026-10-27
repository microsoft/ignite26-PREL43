# ---------------------------------------------------------------------------------------------
# Life cycle action: Hydrate Helix workspace (Post-Build, blocking).
#
# Builds the Zava Helix launch story in this lab's tenant for the learner account:
#   personas -> learner profile -> Teams (migration import) -> channel files -> mail -> calendar
#
# Every phase checks the tenant before writing, so a re-run (Skillable retries uncaught errors)
# finishes the job without duplicates. Nothing is written outside the hydration window
# (D-1 09:30 .. end of D in the event time zone), because Teams import refuses future posts.
# Ported from the Cowork-Lab glc_hydrate engine (ops/tenant.py, ops/seats.py).
# ---------------------------------------------------------------------------------------------

$script:HydrateRoles = @(
    @('User.ReadWrite.All', 'Directory.ReadWrite.All'),
    @('Mail.ReadWrite'),
    @('Calendars.ReadWrite'),
    @('MailboxSettings.ReadWrite'),
    @('Files.ReadWrite.All', 'Sites.ReadWrite.All'),
    @('Teamwork.Migrate.All'),
    @('Group.ReadWrite.All', 'Directory.ReadWrite.All'),
    @('TeamMember.ReadWrite.All')
)
$script:Company = 'Zava Corporation'
$script:TeamExtension = 'com.vectorsense.helixHydration'
$script:Phase = 'start'
$script:Deadline = $null

function Write-Step([string]$Message) { Write-Verbose ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message) }

function Assert-Deadline {
    if ($script:Deadline -and (Get-Date) -gt $script:Deadline) { throw "Ran past the script's time budget during '$script:Phase'." }
}

function Wait-Until {
    <# Polls $Probe until it returns $true; throws "<What> not ready" after $Seconds. #>
    param([string]$What, [scriptblock]$Probe, [int]$Seconds = 300, [int]$Every = 10)
    $until = (Get-Date).AddSeconds($Seconds)
    while ($true) {
        if (& $Probe) { return }
        Assert-Deadline
        if ((Get-Date) -gt $until) { throw "$What not ready after $Seconds seconds." }
        Start-Sleep -Seconds $Every
    }
}

function New-RandomPassword {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%+-=?'.ToCharArray()
    do { $p = -join (1..24 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] }) }
    until ($p -cmatch '[A-Z]' -and $p -cmatch '[a-z]' -and $p -match '\d')
    return $p
}

# ------------------------------------------------------------------------------- pre-flight

function Assert-HydrationWindow($Timeline, $Pack) {
    $now = Get-EventNow $Timeline
    $start = (Get-TimelineLocal $Timeline $Pack.manifest.latest_content).AddMinutes(30)
    $end = $Timeline.Day.AddDays(1)
    if ($now -lt $start) {
        throw ("Outside the hydration window: event day {0:yyyy-MM-dd} can be hydrated from {1:yyyy-MM-dd HH:mm} ({2}); it is now {3:yyyy-MM-dd HH:mm}. Pre-build later or fix EventDate." -f $Timeline.Day, $start, $Timeline.TzName, $now)
    }
    if ($now -ge $end) { throw ("Outside the hydration window: event day {0:yyyy-MM-dd} has passed. Fix EventDate." -f $Timeline.Day) }
}

function Get-DefaultDomain {
    $org = Invoke-Graph -Path '/organization?$select=verifiedDomains'
    $d = @($org.value[0].verifiedDomains) | Where-Object { $_.isDefault } | Select-Object -First 1
    if (-not $d) { throw 'Could not read the tenant default domain.' }
    return $d.name
}

function Get-TenantUsers {
    return Get-GraphAll -Path ('/users?$top=999&$select=id,userPrincipalName,displayName,givenName,surname,userType,accountEnabled,assignedLicenses,employeeId,companyName,usageLocation')
}

function Test-MailboxReady([string]$UserId) {
    try { return $null -ne (Invoke-Graph -Path "/users/$UserId/mailboxSettings" -Ok404) }
    catch { if (-not $_.Exception.PSObject.Properties['Status']) { throw };  if ($_.Exception.Status -in 400, 403) { return $false } throw }
}

function Get-OrganiserKeys($Pack) {
    return @($Pack.calendar.events | ForEach-Object { $_.organiser } | Sort-Object -Unique)
}

# ------------------------------------------------------------------------------- personas

function Get-PersonaProfile($Pack, $Person) {
    return @{
        displayName    = (Get-PackDisplayName $Person)
        givenName      = $Person.given
        surname        = $Person.surname
        jobTitle       = $Person.title
        department     = $Person.department
        officeLocation = $Person.office
        companyName    = $script:Company
        employeeId     = "helix:$($Person.key)"
    }
}

function Sync-Personas {
    <#
      Meeting organisers need mailboxes, so they are mapped onto the tenant's licensed fictional
      users (profile renamed, UPN unchanged). The rest of the Helix cast are created as unlicensed,
      sign-in-disabled accounts. Returns key -> @{id; upn; name}. Idempotent via employeeId "helix:<key>".
    #>
    param($Pack, $Learner, [string]$Domain)
    $script:Phase = 'personas'
    $users = Get-TenantUsers
    $map = @{}
    foreach ($u in $users) {
        # helix:learner marks the learner (Learner.ps1), not a persona.
        if ("$($u.employeeId)" -match '^helix:(.+)$' -and $Matches[1] -ne 'learner') { $map[$Matches[1]] = @{ id = $u.id; upn = $u.userPrincipalName; name = $u.displayName } }
    }

    # Organisers on licensed hosts.
    $organisers = Get-OrganiserKeys $Pack
    $needed = @($organisers | Where-Object { -not $map.ContainsKey($_) })
    if ($needed) {
        $hosts = @($users | Where-Object {
                $_.userType -eq 'Member' -and $_.accountEnabled -and @($_.assignedLicenses).Count -gt 0 -and
                $_.id -ne $Learner.id -and -not ("$($_.employeeId)" -like 'helix:*') -and
                $_.userPrincipalName -notmatch '#EXT#' -and $_.userPrincipalName -notmatch '^(admin|administrator)@' -and
                "$($_.displayName)" -notmatch 'admin'
            } | Sort-Object userPrincipalName)
        $ready = @($hosts | Where-Object { Test-MailboxReady $_.id })
        if ($ready.Count -lt $needed.Count) {
            throw "Needs $($needed.Count) more licensed users with mailboxes for the meeting organisers ($($needed -join ', ')); found $($ready.Count)."
        }
        for ($i = 0; $i -lt $needed.Count; $i++) {
            $key = $needed[$i]; $u = $ready[$i]
            $profile = Get-PersonaProfile $Pack (Get-PackPerson $Pack $key)
            Invoke-Graph -Method PATCH -Path "/users/$($u.id)" -Body $profile | Out-Null
            $map[$key] = @{ id = $u.id; upn = $u.userPrincipalName; name = $profile.displayName }
            Write-Step "organiser $key -> $($u.userPrincipalName)"
        }
    }

    # Everyone else: unlicensed accounts.
    foreach ($p in $Pack.people.internal) {
        Assert-Deadline
        if ($map.ContainsKey($p.key)) { continue }
        $upn = "$($p.mail)@$Domain"
        $profile = Get-PersonaProfile $Pack ($p + @{ kind = 'internal' })
        $existing = Invoke-Graph -Path "/users/$([uri]::EscapeDataString($upn))?`$select=id,userPrincipalName" -Ok404
        if ($existing) {
            Invoke-Graph -Method PATCH -Path "/users/$($existing.id)" -Body $profile | Out-Null
            $id = $existing.id
        }
        else {
            $body = $profile + @{
                accountEnabled = $false; userPrincipalName = $upn; mailNickname = $p.mail.Replace('.', '')
                passwordProfile = @{ forceChangePasswordNextSignIn = $true; password = (New-RandomPassword) }
            }
            $id = (Invoke-Graph -Method POST -Path '/users' -Body $body).id
        }
        $map[$p.key] = @{ id = $id; upn = $upn; name = $profile.displayName }
    }

    # Reviewer account for Milestone 5 skill sharing.
    $r = $Pack.people.reviewer
    $rupn = "helix.reviewer@$Domain"
    $rprofile = @{ displayName = "$($r.given) $($r.surname)"; givenName = $r.given; surname = $r.surname; jobTitle = $r.title
        department = $r.department; companyName = $script:Company; employeeId = 'helix:reviewer' }
    if (-not $map.ContainsKey('reviewer')) {
        $existing = Invoke-Graph -Path "/users/$([uri]::EscapeDataString($rupn))?`$select=id" -Ok404
        $rid = if ($existing) { $existing.id } else {
            (Invoke-Graph -Method POST -Path '/users' -Body ($rprofile + @{ accountEnabled = $false; userPrincipalName = $rupn; mailNickname = 'helixreviewer'
                        passwordProfile = @{ forceChangePasswordNextSignIn = $true; password = (New-RandomPassword) } })).id }
        $map['reviewer'] = @{ id = $rid; upn = $rupn; name = $rprofile.displayName }
    }

    # Reporting lines.
    foreach ($p in $Pack.people.internal) {
        if ($p.manager -and $map.ContainsKey($p.manager)) {
            try { Invoke-Graph -Method PUT -Path "/users/$($map[$p.key].id)/manager/`$ref" -Body @{ '@odata.id' = "$script:GraphRoot/users/$($map[$p.manager].id)" } | Out-Null }
            catch { Write-Step "manager for $($p.key): $($_.Exception.Message)" }
        }
    }

    # Photos for the organisers (they have mailboxes). Best effort.
    foreach ($key in $organisers) {
        $png = Get-PackPhoto $Pack $key
        if (-not $png) { continue }
        try { Invoke-Graph -Method PUT -Path "/users/$($map[$key].id)/photo/`$value" -Bytes $png -ContentType 'image/png' | Out-Null }
        catch { Write-Step "photo for ${key}: $($_.Exception.Message)" }
    }
    return $map
}

# ------------------------------------------------------------------------------- learner

function Set-LearnerProfile {
    param($Pack, $Learner, $Map, [string]$TimeZoneName, [string]$Locale)
    $script:Phase = 'learner profile'
    # A learner licensed during this launch (the admin) can take a while to get a mailbox.
    Wait-Until -What 'Learner mailbox' -Seconds 1500 -Every 20 -Probe { Test-MailboxReady $Learner.id }
    $settings = @{ timeZone = $TimeZoneName }
    if ($Locale) { $settings.language = @{ locale = $Locale } }
    Invoke-Graph -Method PATCH -Path "/users/$($Learner.id)/mailboxSettings" -Body $settings | Out-Null
    $seat = $Pack.people.seat
    Invoke-Graph -Method PATCH -Path "/users/$($Learner.id)" -Body @{ jobTitle = $seat.title; department = $seat.department; officeLocation = $seat.office; companyName = $script:Company } | Out-Null
    if ($seat.manager -and $Map.ContainsKey($seat.manager)) {
        Invoke-Graph -Method PUT -Path "/users/$($Learner.id)/manager/`$ref" -Body @{ '@odata.id' = "$script:GraphRoot/users/$($Map[$seat.manager].id)" } | Out-Null
    }
}

# ------------------------------------------------------------------------------- people helpers

function Get-Address($Ctx, [string]$Key) {
    if ($Key -eq 'learner') { return @{ name = $Ctx.Learner; address = $Ctx.LearnerEmail } }
    $p = Get-PackPerson $Ctx.Pack $Key
    if ($p.kind -eq 'external') { return @{ name = (Get-PackDisplayName $p); address = $p.email } }
    return @{ name = (Get-PackDisplayName $p); address = $Ctx.Map[$Key].upn }
}

function Get-Recipients($Ctx, $Keys) { return @(@($Keys) | Where-Object { $_ } | ForEach-Object { @{ emailAddress = (Get-Address $Ctx $_) } }) }

function Get-UserRef($Ctx, [string]$Key) {
    if ($Key -eq 'learner') { return @{ user = @{ id = $Ctx.LearnerId; displayName = $Ctx.Learner; userIdentityType = 'aadUser' } } }
    $p = Get-PackPerson $Ctx.Pack $Key
    return @{ user = @{ id = $Ctx.Map[$Key].id; displayName = (Get-PackDisplayName $p); userIdentityType = 'aadUser' } }
}

# ------------------------------------------------------------------------------- Teams

function Get-TeamsBody($Ctx, [string]$Text) {
    $parts = [regex]::Split($Text.Trim(), '\{\{\s*mention:learner\s*\}\}')
    $out = ConvertTo-HtmlText (Format-HelixText -Text $parts[0] -Context $Ctx)
    $mentions = @()
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $out += "<at id=`"$($i - 1)`">$(ConvertTo-HtmlText $Ctx.Learner)</at>" + (ConvertTo-HtmlText (Format-HelixText -Text $parts[$i] -Context $Ctx))
        $mentions += @{ id = $i - 1; mentionText = $Ctx.Learner; mentioned = (Get-UserRef $Ctx 'learner') }
    }
    return @{ html = $out.Replace("`n", '<br>'); mentions = $mentions }
}

function New-MigrationTeam([string]$Name, [string]$Description, [string]$CreatedIso) {
    $r = Invoke-Graph -Method POST -Path '/teams' -Raw -Body @{
        '@microsoft.graph.teamCreationMode' = 'migration'
        'template@odata.bind'               = "$script:GraphRoot/teamsTemplates('standard')"
        displayName                         = $Name
        description                         = $Description
        visibility                          = 'private'   # Graph defaults to Public: every user (and Copilot) would see it
        createdDateTime                     = $CreatedIso
    }
    $loc = "$($r.Headers['Location'])" + "$($r.Headers['Content-Location'])"
    if ($loc -notmatch "teams\('([^']+)'\)") { throw "Team creation returned no team id (Location: $loc)." }
    $teamId = $Matches[1]
    $op = if ($loc -match "operations\('([^']+)'\)") { $Matches[1] } else { $null }
    for ($i = 0; $i -lt 40; $i++) {
        if ($op) {
            $st = Invoke-Graph -Path "/teams/$teamId/operations/$op" -Ok404
            if ($st.status -eq 'succeeded') { return $teamId }
            if ($st.status -eq 'failed') { throw "Team creation failed: $($st.error | ConvertTo-Json -Compress)" }
        }
        elseif (Invoke-Graph -Path "/teams/$teamId" -Ok404) { return $teamId }
        Start-Sleep -Seconds ([math]::Min(10, 2 + $i))
    }
    throw "Team $teamId still provisioning."
}

function Get-HelixTeam($Pack) {
    <#
      Returns @{teamId; channelId} for a fully imported team, or $null. A team left half-imported
      by an interrupted run (no completion marker) is deleted so it can be rebuilt cleanly.
    #>
    $name = ConvertTo-ODataLiteral $Pack.teams.team.display_name
    $groups = @((Invoke-Graph -Path "/groups?`$filter=displayName eq '$name'&`$select=id,displayName").value)
    foreach ($g in $groups) {
        $ext = Invoke-Graph -Path "/groups/$($g.id)/extensions/$script:TeamExtension" -Ok404
        if ($ext -and $ext.postsComplete -and $ext.channelId) { return @{ teamId = $g.id; channelId = $ext.channelId } }
        Write-Step "removing half-imported team $($g.id)"
        Invoke-Graph -Method DELETE -Path "/groups/$($g.id)" -Ok404 | Out-Null
    }
    return $null
}

function Sync-Team($Ctx) {
    $script:Phase = 'teams'
    $pack = $Ctx.Pack; $tl = $Ctx.Timeline
    $existing = Get-HelixTeam $pack
    if ($existing) { $teamId = $existing.teamId; $channelId = $existing.channelId }
    else {
        $team = $pack.teams.team; $ch = $team.channels[0]
        $teamId = New-MigrationTeam $team.display_name $team.description (Get-TimelineUtcIso $tl $team.created)
        Write-Step "team $teamId created"
        $channelId = (Invoke-Graph -Method POST -Path "/teams/$teamId/channels" -Body @{
                '@microsoft.graph.channelCreationMode' = 'migration'
                displayName = $ch.name; description = $ch.description; membershipType = 'standard'
                createdDateTime = (Get-TimelineUtcIso $tl $ch.created)
            }).id
        $script:Phase = 'teams posts'
        foreach ($p in $pack.teams.posts) {
            Assert-Deadline
            $b = Get-TeamsBody $Ctx $p.body
            $msg = @{ createdDateTime = (Get-TimelineUtcIso $tl $p.sent); from = (Get-UserRef $Ctx $p.from); body = @{ contentType = 'html'; content = $b.html } }
            if ($b.mentions) { $msg.mentions = $b.mentions }
            $parentId = (Invoke-Graph -Method POST -Path "/teams/$teamId/channels/$channelId/messages" -Body $msg).id
            foreach ($r in @($p.replies)) {
                if (-not $r) { continue }
                $rb = Get-TeamsBody $Ctx $r.body
                Invoke-Graph -Method POST -Path "/teams/$teamId/channels/$channelId/messages/$parentId/replies" -Body @{
                    createdDateTime = (Get-TimelineUtcIso $tl $r.sent); from = (Get-UserRef $Ctx $r.from); body = @{ contentType = 'html'; content = $rb.html }
                } | Out-Null
            }
        }
        $script:Phase = 'teams complete migration'
        foreach ($c in (Get-GraphAll -Path "/teams/$teamId/channels?`$select=id")) {
            try { Invoke-Graph -Method POST -Path "/teams/$teamId/channels/$($c.id)/completeMigration" | Out-Null }
            catch { if (-not $_.Exception.PSObject.Properties['Status']) { throw };  if (-not ($_.Exception.Status -eq 400 -and $_.Exception.Message -match 'migration')) { throw } }
        }
        try { Invoke-Graph -Method POST -Path "/teams/$teamId/completeMigration" | Out-Null }
        catch { if (-not $_.Exception.PSObject.Properties['Status']) { throw };  if (-not ($_.Exception.Status -eq 400 -and $_.Exception.Message -match 'migration')) { throw } }
        Invoke-Graph -Method POST -Path "/groups/$teamId/extensions" -Body @{
            '@odata.type' = 'microsoft.graph.openTypeExtension'; extensionName = $script:TeamExtension
            postsComplete = $true; channelId = $channelId; datapack = $pack.manifest.version
        } | Out-Null
    }

    $script:Phase = 'teams members'
    try {
        Invoke-Graph -Method POST -Path "/teams/$teamId/members" -Body @{
            '@odata.type' = '#microsoft.graph.aadUserConversationMember'; roles = @('owner')
            'user@odata.bind' = "$script:GraphRoot/users('$($Ctx.LearnerId)')"
        } | Out-Null
    }
    catch { if (-not $_.Exception.PSObject.Properties['Status']) { throw };  if ($_.Exception.Status -ne 409) { throw } }
    return @{ teamId = $teamId; channelId = $channelId }
}

function Sync-ChannelFiles($Ctx, $Team) {
    $script:Phase = 'channel files'
    $folder = $null
    Wait-Until -What 'Channel files folder' -Seconds 300 -Every 10 -Probe {
        try { $script:FilesFolder = Invoke-Graph -Path "/teams/$($Team.teamId)/channels/$($Team.channelId)/filesFolder"; return $true }
        catch { if (-not $_.Exception.PSObject.Properties['Status']) { throw };  if ($_.Exception.Status -in 400, 403, 404) { return $false } throw }
    }
    $folder = $script:FilesFolder
    $driveId = $folder.parentReference.driveId
    $parents = @{ '' = $folder.id }
    foreach ($entry in (Get-PackFileLayout $Ctx.Pack)) {
        Assert-Deadline
        $sub = "$($entry[0])"; $name = $entry[1]
        if (-not $parents.ContainsKey($sub)) {
            $found = Invoke-Graph -Path "/drives/$driveId/items/$($folder.id):/$([uri]::EscapeDataString($sub))" -Ok404
            $parents[$sub] = if ($found) { $found.id } else {
                (Invoke-Graph -Method POST -Path "/drives/$driveId/items/$($folder.id)/children" -Body @{ name = $sub; folder = @{}; '@microsoft.graph.conflictBehavior' = 'fail' }).id }
        }
        $data = Format-OfficeFile -Name $name -Data (Get-PackFile $Ctx.Pack $name) -Context $Ctx
        Invoke-Graph -Method PUT -Path "/drives/$driveId/items/$($parents[$sub]):/$([uri]::EscapeDataString($name)):/content" -Bytes $data | Out-Null
    }
}

# ------------------------------------------------------------------------------- mail

function Get-FileTimeUtc([datetime]$Utc) { return [long]($Utc.Ticks - [datetime]::new(1601, 1, 1, 0, 0, 0, [DateTimeKind]::Utc).Ticks) }

function Get-BigEndianBytes([uint64]$Value, [int]$Count) {
    $b = [BitConverter]::GetBytes($Value)
    if ([BitConverter]::IsLittleEndian) { [array]::Reverse($b) }
    return $b[(8 - $Count)..7]
}

function Get-Uuid5Bytes([string]$Name) {
    <# RFC 4122 v5 UUID in the URL namespace, as 16 big-endian bytes (Python uuid5(...).bytes). #>
    $ns = [byte[]](0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8)
    $hash = [Security.Cryptography.SHA1]::Create().ComputeHash($ns + [Text.Encoding]::UTF8.GetBytes($Name))
    $u = $hash[0..15]
    $u[6] = ($u[6] -band 0x0F) -bor 0x50
    $u[8] = ($u[8] -band 0x3F) -bor 0x80
    return [byte[]]$u
}

function Get-ConversationIndex {
    <#
      PidTagConversationIndex (MS-OXOMSG 2.2.1.3): a thread starter gets a 22-byte header
      (reserved byte, 5 bytes of FILETIME, a GUID); each reply appends a 5-byte block.
    #>
    param([byte[]]$Parent, [datetime]$First, [datetime]$Current, [string]$Seed, [int]$Seq)
    if (-not $Parent) {
        return [byte[]](@([byte]1) + (Get-BigEndianBytes ([uint64](Get-FileTimeUtc $First)) 8)[0..4] + (Get-Uuid5Bytes $Seed))
    }
    $baseBytes = [byte[]]($Parent[1..5] + @([byte]0, [byte]0, [byte]0))
    if ([BitConverter]::IsLittleEndian) { [array]::Reverse($baseBytes) }
    $base = [BitConverter]::ToInt64($baseBytes, 0)
    $delta = [math]::Max([long]0, (Get-FileTimeUtc $Current) - $base)
    if ($delta -lt [long][math]::Pow(2, 49)) { $val = ($delta -shr 18) -band 0x7FFFFFFF; $code = 0 }
    else { $val = ($delta -shr 23) -band 0x7FFFFFFF; $code = 1 }
    $block = Get-BigEndianBytes ([uint64](([uint64]$code -shl 31) -bor [uint64]$val)) 4
    return [byte[]]($Parent + $block + @([byte]((((($Seq * 7) % 16)) -shl 4) -bor ($Seq % 16))))
}

function Sync-Mail($Ctx) {
    $script:Phase = 'mail'
    $tl = $Ctx.Timeline
    $local = $Ctx.LearnerEmail.Split('@')[0]
    $sha = [Security.Cryptography.SHA1]::Create()
    $suffix = (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Ctx.LearnerEmail)) | ForEach-Object { $_.ToString('x2') })).Substring(0, 8)
    $threads = @{}
    $msgs = @($Ctx.Pack.mail.messages | Sort-Object { Get-TimelineUtc $tl $_.sent })
    foreach ($m in $msgs) {
        Assert-Deadline
        $msgid = "<$($m.id).$local.$suffix@helix.zava.example>"
        $sentIso = Get-TimelineUtcIso $tl $m.sent
        $props = @(
            @{ id = 'Integer 0x0E07'; value = '1' },          # not a draft
            @{ id = 'SystemTime 0x0039'; value = $sentIso },  # sent
            @{ id = 'SystemTime 0x0E06'; value = $sentIso },  # received
            @{ id = 'String 0x1035'; value = $msgid }         # Message-ID
        )
        $conv = $m.conversation
        if ($conv) {
            if (-not $threads.ContainsKey($conv)) { $threads[$conv] = [System.Collections.Generic.List[object]]::new() }
            $chain = $threads[$conv]
            $topic = [regex]::Replace($m.subject, '^(RE|FW):\s*', '', 'IgnoreCase')
            $sent = Get-TimelineUtc $tl $m.sent
            $first = if ($chain.Count) { Get-TimelineUtc $tl $chain[0].sent } else { $sent }
            $parent = if ($chain.Count) { $chain[$chain.Count - 1].index } else { $null }
            $idx = Get-ConversationIndex -Parent $parent -First $first -Current $sent -Seed "$($Ctx.LearnerEmail)/$conv" -Seq $chain.Count
            $props += @{ id = 'String 0x0070'; value = $topic }
            $props += @{ id = 'Binary 0x0071'; value = [Convert]::ToBase64String($idx) }
            if ($chain.Count) {
                $props += @{ id = 'String 0x1042'; value = $chain[$chain.Count - 1].msgid }
                $props += @{ id = 'String 0x1039'; value = (($chain | ForEach-Object { $_.msgid }) -join ' ') }
            }
            $chain.Add(@{ sent = $m.sent; msgid = $msgid; index = $idx })
        }
        $exists = Invoke-Graph -Path "/users/$($Ctx.LearnerId)/messages?`$filter=internetMessageId eq '$(ConvertTo-ODataLiteral $msgid)'&`$select=id"
        if (@($exists.value).Count -gt 0) { continue }
        $from = Get-Address $Ctx $m.from
        $body = @{
            subject                      = (Format-HelixText -Text $m.subject -Context $Ctx)
            body                         = @{ contentType = 'HTML'; content = (ConvertTo-ParagraphHtml (Format-HelixText -Text $m.body -Context $Ctx)) }
            from                         = @{ emailAddress = $from }
            sender                       = @{ emailAddress = $from }
            toRecipients                 = @(Get-Recipients $Ctx $m.to)
            ccRecipients                 = @(Get-Recipients $Ctx $m.cc)
            importance                   = $(if ($m.importance) { $m.importance } else { 'normal' })
            singleValueExtendedProperties = $props
        }
        if ($m.flag) { $body.flag = @{ flagStatus = 'flagged' } }
        $id = (Invoke-Graph -Method POST -Path "/users/$($Ctx.LearnerId)/mailFolders/inbox/messages" -Body $body).id
        if ($m.ContainsKey('read') -and -not $m.read) {
            Invoke-Graph -Method PATCH -Path "/users/$($Ctx.LearnerId)/messages/$id" -Body @{ isRead = $false } | Out-Null
        }
    }
}

# ------------------------------------------------------------------------------- calendar

function Sync-Calendar($Ctx) {
    $script:Phase = 'calendar'
    $tl = $Ctx.Timeline
    foreach ($e in $Ctx.Pack.calendar.events) {
        Assert-Deadline
        $org = $Ctx.Map[$e.organiser].id
        $attendees = @($e.attendees | ForEach-Object { @{ emailAddress = (Get-Address $Ctx $_); type = 'required' } })
        $created = Invoke-Graph -Method POST -Path "/users/$org/calendar/events" -Body @{
            subject     = $e.subject
            body        = @{ contentType = 'text'; content = "$($e.body)" }
            start       = @{ dateTime = (Get-TimelineLocalIso $tl $e.start); timeZone = $tl.TzName }
            end         = @{ dateTime = (Get-TimelineLocalIso $tl $e.end); timeZone = $tl.TzName }
            attendees   = $attendees
            allowNewTimeProposals = $false
            isReminderOn = $false
            transactionId = "helix-$($Ctx.LearnerEmail)-$($e.id)"   # Graph de-duplicates re-runs on this id
        }
        $ical = ConvertTo-ODataLiteral $created.iCalUId
        $script:SeatEvent = $null
        Wait-Until -What "Invitation $($e.id) in the learner calendar" -Seconds 240 -Every 8 -Probe {
            $v = @((Invoke-Graph -Path "/users/$($Ctx.LearnerId)/events?`$filter=iCalUId eq '$ical'&`$select=id,subject,responseStatus").value)
            if ($v.Count) { $script:SeatEvent = $v[0]; return $true }
            return $false
        }
        if ($script:SeatEvent.responseStatus.response -ne 'accepted') {
            Invoke-Graph -Method POST -Path "/users/$($Ctx.LearnerId)/events/$($script:SeatEvent.id)/accept" -Body @{ sendResponse = $false } | Out-Null
        }
    }
    # Remove the meeting-request messages the invitations left in the Inbox.
    $script:Phase = 'invitation cleanup'
    foreach ($m in (Get-GraphAll -Path "/users/$($Ctx.LearnerId)/mailFolders/inbox/messages?`$top=60&`$select=id,subject" -Limit 120)) {
        if ("$($m.'@odata.type')" -match 'eventMessage') {
            Invoke-Graph -Method DELETE -Path "/users/$($Ctx.LearnerId)/messages/$($m.id)" -Ok404 | Out-Null
        }
    }
}

# ------------------------------------------------------------------------------- entry point

function Invoke-Hydration {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$LearnerUpn,
        [Parameter(Mandatory)][string]$EventDate,
        [Parameter(Mandatory)][string]$EventTimeZone,
        [string]$DataPackUrl,
        [string]$Locale,
        [int]$BudgetMinutes = 40
    )
    $script:Deadline = (Get-Date).AddMinutes($BudgetMinutes)
    $script:Phase = 'data pack'
    $pack = Get-HelixPack -Url $DataPackUrl
    $tl = New-Timeline -EventDate $EventDate -TimeZoneName $EventTimeZone
    $script:Phase = 'hydration window'
    Assert-HydrationWindow $tl $pack

    $script:Phase = 'pre-flight'
    Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $missing = Test-GraphRoles -Required $script:HydrateRoles
    if ($missing) { throw "The cloud credential is missing Microsoft Graph application permissions: $($missing -join '; ')." }
    $learner = Invoke-Graph -Path "/users/$([uri]::EscapeDataString($LearnerUpn))?`$select=id,userPrincipalName,displayName,givenName,surname,assignedLicenses" -Ok404
    if (-not $learner) { throw "Learner account $LearnerUpn not found in tenant $TenantId." }
    if (@($learner.assignedLicenses).Count -eq 0) { throw "Learner account $LearnerUpn has no licences." }
    $domain = Get-DefaultDomain

    $map = Sync-Personas -Pack $pack -Learner $learner -Domain $domain
    Set-LearnerProfile -Pack $pack -Learner $learner -Map $map -TimeZoneName $EventTimeZone -Locale $Locale

    $first = if ($learner.givenName) { $learner.givenName } else { "$($learner.displayName)".Split(' ')[0] }
    $ctx = [pscustomobject]@{
        Pack = $pack; Timeline = $tl; Map = $map; LearnerId = $learner.id
        Learner = $learner.displayName; LearnerFirst = $first; LearnerEmail = $learner.userPrincipalName
    }
    $team = Sync-Team $ctx
    Sync-ChannelFiles $ctx $team
    Sync-Mail $ctx
    Sync-Calendar $ctx
    $script:Phase = 'done'
    return @{ learner = $learner.userPrincipalName; teamId = $team.teamId; personas = $map.Count; datapack = $pack.manifest.version }
}
