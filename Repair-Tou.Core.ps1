function Get-TouRepairPlan([byte[]]$Bytes, [datetime]$Month, [hashtable]$Access) {
    $slotCount = [datetime]::DaysInMonth($Month.Year,$Month.Month) * 96
    $headerTime = $Month.ToString('dd/MM/yyyyHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
    if ($Bytes.Length -lt (64 + $slotCount * 16) -or ($Bytes.Length-64)%16 -ne 0 -or
        [Text.Encoding]::ASCII.GetString($Bytes,0,6) -cne 'TOUReg' -or
        [Text.Encoding]::ASCII.GetString($Bytes,10,18) -cne $headerTime) {
        throw 'Invalid TOU size, signature or month in header.'
    }
    $energy = [double[]]::new($slotCount)
    $demand = [double[]]::new($slotCount)
    $present = [bool[]]::new($slotCount)
    $last = -1
    for ($i=0; $i -lt $slotCount; $i++) {
        $demand[$i] = [BitConverter]::ToDouble($Bytes,64+16*$i)
        $energy[$i] = [BitConverter]::ToDouble($Bytes,72+16*$i)
        if (![double]::IsFinite($demand[$i]) -or ![double]::IsFinite($energy[$i]) -or $energy[$i] -lt 0) {
            throw "Invalid numeric reading at slot $i."
        }
        if ($energy[$i] -ne 0 -or $demand[$i] -ne 0) {
            $present[$i] = $true
            $last = $i
        }
    }
    $patches = @{}
    $gaps = [Collections.Generic.List[object]]::new()
    for ($i=0; $i -lt $last; $i++) {
        if ($present[$i]) { continue }
        $first = $i
        while (!$present[$i]) { $i++ }
        $end = $i-1
        $gap = [pscustomobject]@{ First=$first; Last=$end; Shift=$null; Reason='ไม่มีค่า TOU ก่อนช่วงขาด' }
        $gaps.Add($gap)
        if ($first -lt 1) { continue }
        $before = $first-1
        $after = $i
        $matches = @(foreach ($shift in (-1..1)) {
            if ($null -ne $Access[$before-$shift] -and $null -ne $Access[$after-$shift] -and
                [math]::Abs($Access[$before-$shift][1]-$energy[$before]) -le 0.001 -and
                [math]::Abs($Access[$after-$shift][1]-$energy[$after]) -le 0.001) { $shift }
        })
        $gap.Reason = 'เวลาและ kWh สะสมที่ขอบช่วงไม่ตรงกับ Access หรือจับคู่ได้หลายแบบ'
        if ($matches.Count -ne 1) { continue }
        $shift = $matches[0]
        $gap.Shift = $shift
        $previous = $energy[$before]
        $range = @{}
        $gap.Reason = ''
        for ($slot=$first; $slot -le $end; $slot++) {
            $source = $slot-$shift
            if ($null -eq $Access[$source]) {
                $gap.Reason = 'Access ขาดข้อมูลหรือมีเวลาซ้ำที่ ' + $Month.AddMinutes($source*15).ToString('dd/MM HH:mm')
                break
            }
            $pair = $Access[$source]
            if (($pair[0] -eq 0 -and $pair[1] -eq 0) -or $pair[1] -lt $previous -or $pair[1] -gt $energy[$after]) {
                $gap.Reason = ('kWh สะสมผิดช่วงที่ {0:dd/MM HH:mm} ({1} → {2}, ปลายช่วง {3})' -f $Month.AddMinutes($slot*15),$previous,$pair[1],$energy[$after])
                break
            }
            $previous = $pair[1]
            $range[$slot] = $pair
        }
        if (!$gap.Reason) {
            foreach ($slot in $range.Keys) { $patches[$slot] = $range[$slot] }
        }
    }
    [pscustomobject]@{ Patches=$patches; Gaps=$gaps; Last=$last; Demand=$demand; Energy=$energy; Present=$present }
}

function Save-TouRepair([string]$Path, [byte[]]$Original, [hashtable]$Patches) {
    if (!$Patches.Count) { throw 'No verified slots to repair.' }
    $updated = $Original.Clone()
    foreach ($slot in $Patches.Keys) {
        [BitConverter]::GetBytes([double]$Patches[$slot][0]).CopyTo($updated,64+16*$slot)
        [BitConverter]::GetBytes([double]$Patches[$slot][1]).CopyTo($updated,72+16*$slot)
    }
    $id = [guid]::NewGuid().ToString('N')
    $temp = "$Path.$id.tmp"
    $backup = "$Path.$id.bak"
    try {
        [IO.File]::WriteAllBytes($temp,$updated)
        $share = [IO.FileShare]::Read -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
        try {
            if ($stream.Length -ne $Original.Length) { throw 'TOU changed. Scan again.' }
            $current = [byte[]]::new($Original.Length)
            $stream.ReadExactly($current)
            if ([Convert]::ToBase64String($current) -cne [Convert]::ToBase64String($Original)) {
                throw 'TOU changed. Scan again.'
            }
            [IO.File]::Replace($temp,$Path,$backup)
        } finally { $stream.Dispose() }
        $backup
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

