# ---------------------------------------------------------------------------------------------
# Relative dates. Every time in the data pack is an offset from the event day (D0) in the event
# time zone, for example "D-9 09:12" or "D+10". The event day comes from the lab profile
# variable EventDate, so the Helix launch is always ten days out on the day of the event.
# ---------------------------------------------------------------------------------------------

# Windows time zone names (used by Exchange and the lab profile) to IANA names (used on Linux hosts).
$script:WindowsToIana = @{
    'UTC'                           = 'UTC'
    'GMT Standard Time'             = 'Europe/London'
    'W. Europe Standard Time'       = 'Europe/Berlin'
    'Romance Standard Time'         = 'Europe/Paris'
    'Central Europe Standard Time'  = 'Europe/Budapest'
    'India Standard Time'           = 'Asia/Kolkata'
    'Singapore Standard Time'       = 'Asia/Singapore'
    'Tokyo Standard Time'           = 'Asia/Tokyo'
    'China Standard Time'           = 'Asia/Shanghai'
    'AUS Eastern Standard Time'     = 'Australia/Sydney'
    'Arabian Standard Time'         = 'Asia/Dubai'
    'Eastern Standard Time'         = 'America/New_York'
    'Central Standard Time'         = 'America/Chicago'
    'Mountain Standard Time'        = 'America/Denver'
    'Pacific Standard Time'         = 'America/Los_Angeles'
    'E. South America Standard Time' = 'America/Sao_Paulo'
}

function Get-EventTimeZone {
    <# Resolves a Windows time zone name on Windows or Linux hosts. #>
    param([Parameter(Mandatory)][string]$Name)
    foreach ($id in @($Name, $script:WindowsToIana[$Name])) {
        if (-not $id) { continue }
        try { return [TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { }
    }
    throw "Unknown time zone '$Name'. Use a Windows time zone name such as 'India Standard Time'."
}

function New-Timeline {
    param(
        [Parameter(Mandatory)][string]$EventDate,      # yyyy-MM-dd
        [Parameter(Mandatory)][string]$TimeZoneName     # Windows name, e.g. 'India Standard Time'
    )
    $day = [datetime]::ParseExact($EventDate.Trim(), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    return [pscustomobject]@{ Day = $day.Date; Tz = (Get-EventTimeZone $TimeZoneName); TzName = $TimeZoneName }
}

function ConvertFrom-Offset {
    <# 'D-9 09:12' -> @{Days=-9; Time=09:12}; 'D+10' -> @{Days=10; Time=$null}. #>
    param([Parameter(Mandatory)][string]$Offset)
    if ($Offset -notmatch '^\s*D\s*([+-]\s*\d+)?\s*(?:(\d{1,2}):(\d{2}))?\s*$') { throw "Not a lab-day offset: '$Offset'" }
    $days = if ($Matches[1]) { [int]($Matches[1] -replace '\s', '') } else { 0 }
    $time = if ($Matches[2]) { [timespan]::new([int]$Matches[2], [int]$Matches[3], 0) } else { $null }
    return @{ Days = $days; Time = $time }
}

function Get-TimelineLocal {
    <# Wall-clock time in the event time zone (Kind = Unspecified). #>
    param($Timeline, [string]$Offset)
    $o = ConvertFrom-Offset $Offset
    $t = if ($o.Time) { $o.Time } else { [timespan]::Zero }
    return [datetime]::SpecifyKind($Timeline.Day.AddDays($o.Days).Add($t), [DateTimeKind]::Unspecified)
}

function Get-TimelineUtc {
    param($Timeline, [string]$Offset)
    return [TimeZoneInfo]::ConvertTimeToUtc((Get-TimelineLocal $Timeline $Offset), $Timeline.Tz)
}

function Get-TimelineUtcIso {
    param($Timeline, [string]$Offset)
    return (Get-TimelineUtc $Timeline $Offset).ToString("yyyy-MM-dd'T'HH:mm:ss'.000Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function Get-TimelineLocalIso {
    <# For Graph {dateTime, timeZone} pairs. #>
    param($Timeline, [string]$Offset)
    return (Get-TimelineLocal $Timeline $Offset).ToString("yyyy-MM-dd'T'HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
}

function Get-TimelineDateText {
    <# 'Thursday 15 October 2026' #>
    param($Timeline, [string]$Offset)
    $d = $Timeline.Day.AddDays((ConvertFrom-Offset $Offset).Days)
    $c = [Globalization.CultureInfo]::InvariantCulture
    return "$($d.ToString('dddd', $c)) $($d.Day) $($d.ToString('MMMM yyyy', $c))"
}

function Get-TimelineWeekday {
    param($Timeline, [string]$Offset)
    return $Timeline.Day.AddDays((ConvertFrom-Offset $Offset).Days).ToString('dddd', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-EventNow {
    <# Current wall-clock time in the event time zone. #>
    param($Timeline)
    return [TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $Timeline.Tz)
}
