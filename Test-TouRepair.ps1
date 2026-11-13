$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Repair-Tou.Core.ps1"
function Assert($Condition, $Message) { if (!$Condition) { throw $Message } }
$bytes = [byte[]]::new(64 + 3072 * 16)
[Text.Encoding]::ASCII.GetBytes('TOUReg').CopyTo($bytes,0)
$bytes[8] = 64
[Text.Encoding]::ASCII.GetBytes('01/11/202600:00:00').CopyTo($bytes,10)
$access = @{}
for ($i=0; $i -le 500; $i++) { $access[$i] = @(100.0, (10000.0 + $i * 20)) }
foreach ($i in (0..9 + 490..500)) {
    [BitConverter]::GetBytes([double]$access[$i][0]).CopyTo($bytes,64+16*$i)
    [BitConverter]::GetBytes([double]$access[$i][1]).CopyTo($bytes,72+16*$i)
}
$month = [datetime]'2026-11-01'
$result = Get-TouRepairPlan $bytes $month $access
Assert ($result.Patches.Count -eq 480) 'Five-day gap should be fillable'
Assert ($result.Gaps.Count -eq 1) 'Future slots must not count as missing'
$shifted = @{}
foreach ($i in $access.Keys) { $shifted[$i-1] = $access[$i] }
$shift = Get-TouRepairPlan $bytes $month $shifted
Assert ($shift.Patches.Count -eq 480 -and $shift.Gaps[0].Shift -eq 1) 'One-period meter lag'
$access.Remove(250)
Assert ((Get-TouRepairPlan $bytes $month $access).Patches.Count -eq 0) 'Incomplete Access must block range'
$access[250] = @(100.0, 100.0)
Assert ((Get-TouRepairPlan $bytes $month $access).Patches.Count -eq 0) 'Counter decrease must block range'
$flat = @{}
foreach ($i in (0..500)) { $flat[$i] = @(0.0, 10000.0) }
$ambiguous = $bytes.Clone()
foreach ($i in (0..9 + 490..500)) { [BitConverter]::GetBytes(10000.0).CopyTo($ambiguous,72+16*$i) }
Assert ((Get-TouRepairPlan $ambiguous $month $flat).Patches.Count -eq 0) 'Ambiguous clock alignment must block'
$dir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($dir)
try {
    $file = Join-Path $dir 'D18Nov26.tou'
    [IO.File]::WriteAllBytes($file,$bytes)
    $backup = Save-TouRepair $file $bytes $result.Patches
    $actual = [IO.File]::ReadAllBytes($file)
    Assert ([BitConverter]::ToDouble($actual,72+16*250) -eq 15000) 'Repaired slot'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backup)) -eq [Convert]::ToBase64String($bytes)) 'Backup matches'
    Assert ((Get-TouRepairPlan $actual $month @{}).Gaps.Count -eq 0) 'Repaired file has no gaps'
    $stale = $false
    try { Save-TouRepair $file $bytes $result.Patches } catch { $stale = $true }
    Assert $stale 'Changed files must be rejected'
} finally {
    Get-ChildItem -LiteralPath $dir -File | Remove-Item
    Remove-Item -LiteralPath $dir
}
'All repair checks passed'

