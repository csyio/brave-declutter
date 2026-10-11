<#
.SYNOPSIS
Hide leftover Brave toolbar buttons and new-tab items by editing the
profile's Preferences file (Windows PowerShell 5.1 or PowerShell 7).

.DESCRIPTION
Brave must be fully closed. A timestamped backup is written next to the
file before any change. -Undo first keeps a copy of the current file
(Preferences.bak-declutter-preundo-<time>), then restores the newest backup
made by this script and marks it as used (.restored), so running -Undo again
steps back to the next older backup. No network access, no elevated rights
needed.

.PARAMETER ProfileDir
Profile folder that contains Preferences. Default: the Default profile of Brave.

.PARAMETER Undo
Restore the newest backup made by this script (a copy of the current file is
kept first).

.PARAMETER SkipRunningCheck
Only if the running check itself fails and Brave is definitely closed.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\declutter-prefs.ps1
#>
[CmdletBinding()]
param(
    [string]$ProfileDir,
    [switch]$Undo,
    [switch]$SkipRunningCheck
)

$ErrorActionPreference = 'Stop'
$Marker = '.bak-declutter-'
$PreundoMarker = '.bak-declutter-preundo-'

# Dotted path under the top-level "brave" object -> value.
$Keys = [ordered]@{
    'show_brave_rewards_button'                          = $false
    'rewards.show_brave_rewards_button_in_location_bar'  = $false
    'ai_chat.show_toolbar_button'                         = $false
    'wallet.show_wallet_icon_on_toolbar'                 = $false
    'brave_vpn.show_button'                              = $false
    'today.should_show_toolbar_button'                   = $false
    'show_side_panel_button'                             = $false
    'sidebar.sidebar_show_option'                        = 3   # 3 = never show the sidebar
    'new_tab_page.show_branded_background_image'         = $false  # sponsored images
    'new_tab_page.show_stats'                            = $false
    'new_tab_page.show_brave_news'                       = $false
}

function Fail([string]$Message, [int]$Code = 1) {
    [Console]::Error.WriteLine("Error: $Message")
    exit $Code
}

function Get-Dotted($Root, [string]$Dotted) {
    $node = $Root
    foreach ($part in $Dotted.Split('.')) {
        if ($null -eq $node -or $node -isnot [System.Management.Automation.PSCustomObject]) { return $null }
        $prop = $node.PSObject.Properties[$part]
        if ($null -eq $prop) { return $null }
        $node = $prop.Value
    }
    return $node
}

function Set-Dotted($Root, [string]$Dotted, $Value) {
    $parts = $Dotted.Split('.')
    $node = $Root
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        $prop = $node.PSObject.Properties[$parts[$i]]
        if ($null -eq $prop -or $prop.Value -isnot [System.Management.Automation.PSCustomObject]) {
            $node | Add-Member -NotePropertyName $parts[$i] -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $node = $node.PSObject.Properties[$parts[$i]].Value
    }
    $node | Add-Member -NotePropertyName $parts[-1] -NotePropertyValue $Value -Force
}

function Test-SameValue($Old, $New) {
    if ($null -eq $Old) { return $false }
    # PowerShell treats $false -eq 0 as true; keep booleans and numbers apart.
    if (($Old -is [bool]) -ne ($New -is [bool])) { return $false }
    return ($Old -eq $New)
}

function Get-FreeName([string]$Base) {
    $candidate = $Base
    $n = 1
    while ((Test-Path -LiteralPath $candidate) -or (Test-Path -LiteralPath "$candidate.restored")) { $n++; $candidate = "$Base-$n" }
    return $candidate
}

function Get-Backups([string]$Dir) {
    # Real backups only: not "preundo" copies and not ".restored" ones.
    # Oldest first: sort by timestamp, then by the optional -N suffix.
    $found = foreach ($file in (Get-ChildItem -LiteralPath $Dir -Filter ("Preferences$Marker*") -File)) {
        if ($file.Name -match '^Preferences\.bak-declutter-(\d{8}-\d{6})(?:-(\d+))?$') {
            $seq = 1
            if ($Matches[2]) { $seq = [int]$Matches[2] }
            [pscustomobject]@{ Stamp = $Matches[1]; Seq = $seq; File = $file }
        }
    }
    return @($found | Sort-Object Stamp, Seq | ForEach-Object { $_.File })
}

function Write-FileAtomic([string]$Path, [string]$Text) {
    $tmp = "$Path.declutter.tmp"
    $utf8 = New-Object System.Text.UTF8Encoding($false)   # UTF-8 without BOM
    [System.IO.File]::WriteAllText($tmp, $Text, $utf8)
    [System.IO.File]::Replace($tmp, $Path, $null)
}

if (-not $ProfileDir) {
    if (-not $env:LOCALAPPDATA) { Fail 'LOCALAPPDATA is not set; use -ProfileDir.' }
    $ProfileDir = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default'
}
if (-not (Test-Path -LiteralPath $ProfileDir -PathType Container)) {
    Fail "$ProfileDir not found. Pass -ProfileDir if your profile is elsewhere."
}
# Relative paths resolve differently for .NET calls and PowerShell cmdlets.
$ProfileDir = (Resolve-Path -LiteralPath $ProfileDir).ProviderPath
$Prefs = Join-Path $ProfileDir 'Preferences'
if (-not (Test-Path -LiteralPath $Prefs -PathType Leaf)) {
    Fail "$Prefs not found. Pass -ProfileDir if your profile is elsewhere."
}

if (-not $SkipRunningCheck -and (Get-Process -Name 'brave' -ErrorAction SilentlyContinue)) {
    Fail 'Brave is running. Quit it completely (including background processes) and run this again.' 2
}

if ($Undo) {
    $backups = Get-Backups $ProfileDir
    if ($backups.Count -eq 0) { Fail "No backup made by this script found next to $Prefs." }
    $latest = $backups[-1]
    $restored = "$($latest.FullName).restored"
    if (Test-Path -LiteralPath $restored) { Fail "$restored already exists; remove or rename it and try again." }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $preundo = Get-FreeName "$Prefs$PreundoMarker$stamp"
    Copy-Item -LiteralPath $Prefs -Destination $preundo
    $tmp = "$Prefs.declutter.tmp"
    Copy-Item -LiteralPath $latest.FullName -Destination $tmp -Force
    [System.IO.File]::Replace($tmp, $Prefs, $null)
    Move-Item -LiteralPath $latest.FullName -Destination $restored
    Write-Host "Restored $Prefs from $($latest.Name)"
    Write-Host "Your settings from before the undo are kept in $preundo"
    Write-Host "Backup renamed to $(Split-Path -Leaf $restored); run -Undo again to step back to an older backup."
    exit 0
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    $data = [System.IO.File]::ReadAllText($Prefs, $utf8) | ConvertFrom-Json
} catch {
    Fail "$Prefs is not valid JSON ($($_.Exception.Message)). Nothing was changed."
}
if ($data -isnot [System.Management.Automation.PSCustomObject]) {
    Fail 'Unexpected Preferences layout. Nothing was changed.'
}

$brave = $data.PSObject.Properties['brave']
$braveObj = $null
if ($null -ne $brave -and $brave.Value -is [System.Management.Automation.PSCustomObject]) {
    $braveObj = $brave.Value
}

$pending = @()
foreach ($dotted in $Keys.Keys) {
    $old = $null
    if ($null -ne $braveObj) { $old = Get-Dotted $braveObj $dotted }
    if (-not (Test-SameValue $old $Keys[$dotted])) { $pending += $dotted }
}
if ($pending.Count -eq 0) {
    Write-Host 'Already applied, nothing to do.'
    exit 0
}

if ($null -eq $braveObj) {
    $data | Add-Member -NotePropertyName 'brave' -NotePropertyValue ([pscustomobject]@{}) -Force
    $braveObj = $data.PSObject.Properties['brave'].Value
}

foreach ($dotted in $Keys.Keys) {
    $value = $Keys[$dotted]
    $state = if ($pending -contains $dotted) { 'set' } else { 'already set' }
    Set-Dotted $braveObj $dotted $value
    Write-Host ("  brave.{0} = {1} ({2})" -f $dotted, ($value | ConvertTo-Json -Compress), $state)
}

$json = ConvertTo-Json -InputObject $data -Depth 100 -Compress
try {
    $null = $json | ConvertFrom-Json
} catch {
    Fail 'Serialized output is not valid JSON; file left unchanged.'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Get-FreeName "$Prefs$Marker$stamp"
Copy-Item -LiteralPath $Prefs -Destination $backup
Write-Host "Backup written: $backup"
Write-FileAtomic $Prefs $json
Write-Host 'Done. Start Brave again to see the changes.'
