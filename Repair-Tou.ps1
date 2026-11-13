$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Access-Log.ps1"
. "$PSScriptRoot/Repair-Tou.Core.ps1"

Add-Type -AssemblyName System.Windows.Forms
[Windows.Forms.Application]::EnableVisualStyles()
$config = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Access-to-TOU/repair.json'
$form = [Windows.Forms.Form]@{Text='Access to TOU | ซ่อมข้อมูล EMS'; Width=1200; Height=860; MinimumSize=[Drawing.Size]::new(860,700)}
$form.Font = [Drawing.Font]::new('Segoe UI',10)
$layout = [Windows.Forms.TableLayoutPanel]@{Dock='Fill'; RowCount=5; ColumnCount=1; Padding=[Windows.Forms.Padding]::new(12)}
foreach ($size in 76,34,31,34,69) {
    if ($layout.RowStyles.Count -in 2,4) { $style = [Windows.Forms.RowStyle]::new('Percent',$size) }
    else { $style = [Windows.Forms.RowStyle]::new('Absolute',$size) }
    [void]$layout.RowStyles.Add($style)
}
$form.Controls.Add($layout)
$folders = [Windows.Forms.TableLayoutPanel]@{Dock='Fill';ColumnCount=3;RowCount=2}
[void]$folders.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',100))
[void]$folders.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
[void]$folders.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',100))
$inputs = @(foreach ($label in 'Access','TOU') {
    $row = $folders.RowCount - 2
    $folders.Controls.Add([Windows.Forms.Label]@{Text=$label; Dock='Fill'},0,$row)
    $inputBox = [Windows.Forms.TextBox]@{Dock='Fill'}
    $folders.Controls.Add($inputBox,1,$row)
    $pick = [Windows.Forms.Button]@{Text='เลือกโฟลเดอร์';AutoSize=$true;Tag=$inputBox}
    $pick.Add_Click({
        param($sender)
        $dialog = [Windows.Forms.FolderBrowserDialog]::new()
        try {
            if ([IO.Directory]::Exists($sender.Tag.Text)) { $dialog.SelectedPath = $sender.Tag.Text }
            if ($dialog.ShowDialog() -eq 'OK') { $sender.Tag.Text = $dialog.SelectedPath }
        } finally { $dialog.Dispose() }
    })
    $folders.Controls.Add($pick,2,$row)
    $folders.RowCount++
    $inputBox
})
$folders.RowCount = 2
$layout.Controls.Add($folders,0,0)
if ([IO.File]::Exists($config)) {
    try {
        $saved = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json
        $inputs[0].Text = $saved.access
        $inputs[1].Text = $saved.tou
    } catch { Write-Warning $_ }
}
$actions = [Windows.Forms.FlowLayoutPanel]@{Dock='Fill'}
$scan = [Windows.Forms.Button]@{Text='จำโฟลเดอร์และสแกน';AutoSize=$true}
$apply = [Windows.Forms.Button]@{Text='เติมช่วงที่ผ่านในไฟล์ที่เลือก';AutoSize=$true;Enabled=$false}
$status = [Windows.Forms.Label]@{AutoSize=$true;Margin=[Windows.Forms.Padding]::new(12,6,0,0)}
$actions.Controls.AddRange(@($scan,$apply,$status))
$layout.Controls.Add($actions,0,1)

function New-Grid([string[]]$Headers) {
    $grid = [Windows.Forms.DataGridView]@{
        Dock='Fill';ReadOnly=$true;AllowUserToAddRows=$false;AllowUserToDeleteRows=$false
        RowHeadersVisible=$false;SelectionMode='FullRowSelect';AutoSizeColumnsMode='Fill'
    }
    foreach ($header in $Headers) { [void]$grid.Columns.Add([string]$grid.Columns.Count,$header) }
    $grid
}
$files = New-Grid @('ไฟล์ TOU / Access','ช่วงขาด / รายละเอียด','สถานะ')
$layout.Controls.Add($files,0,2)
$dayBar = [Windows.Forms.FlowLayoutPanel]@{Dock='Fill'}
$dayBar.Controls.Add([Windows.Forms.Label]@{Text='ข้อมูล 15 นาที · วันที่';AutoSize=$true;Margin=[Windows.Forms.Padding]::new(0,7,8,0)})
$days = [Windows.Forms.ComboBox]@{DropDownStyle='DropDownList';Width=135}
$dayBar.Controls.Add($days)
$layout.Controls.Add($dayBar,0,3)
$periods = New-Grid @('เวลา TOU','TOU kW','TOU kWh สะสม','เวลา Access','Access kW','Access kWh สะสม','สถานะ')
$periods.MultiSelect = $false
$detail = [Windows.Forms.TabControl]@{Dock='Fill'}
$tableTab = [Windows.Forms.TabPage]@{Text='ตาราง 15 นาที'}
$chartTab = [Windows.Forms.TabPage]@{Text='กราฟ kWh สะสม'}
$chart = [Windows.Forms.Panel]@{Dock='Fill';BackColor=[Drawing.Color]::White}
$chartTab.Controls.Add($chart)
$tableTab.Controls.Add($periods)
$detail.TabPages.AddRange(@($tableTab,$chartTab))
$layout.Controls.Add($detail,0,4)
$chart.Add_Paint({
    param($sender,$eventArgs)
    $points = @($periods.Rows | ForEach-Object {
        foreach ($column in 2,5) {
            if ($null -ne $_.Cells[$column].Value) { [double]$_.Cells[$column].Value }
        }
    })
    if (!$points.Count) { return }
    $limits = $points | Measure-Object -Minimum -Maximum
    $span = [math]::Max(1.0,$limits.Maximum-$limits.Minimum)
    $width = [math]::Max(1,$sender.ClientSize.Width-98)
    $height = [math]::Max(1,$sender.ClientSize.Height-75)
    $g = $eventArgs.Graphics
    $g.DrawString('TOU (น้ำเงิน)   Access (ส้ม)', $form.Font,[Drawing.Brushes]::Black,76,5)
    $g.DrawString(('{0:N2}' -f $limits.Maximum),$form.Font,[Drawing.Brushes]::Black,0,25)
    $g.DrawString(('{0:N2}' -f $limits.Minimum),$form.Font,[Drawing.Brushes]::Black,0,25+$height)
    foreach ($tick in 0,24,48,72,95) {
        $g.DrawString(([timespan]::FromMinutes($tick*15).ToString('hh\:mm')),$form.Font,[Drawing.Brushes]::Black,76+$tick*$width/95,33+$height)
    }
    foreach ($column in 2,5) {
        $pen = if ($column -eq 2) { [Drawing.Pens]::RoyalBlue } else { [Drawing.Pens]::DarkOrange }
        $prior = $null
        for ($i=0; $i -lt $periods.Rows.Count; $i++) {
            $value = $periods.Rows[$i].Cells[$column].Value
            if ($null -eq $value) { $prior = $null; continue }
            $x = 76+$i*$width/95
            $y = 30+$height*(1-([double]$value-$limits.Minimum)/$span)
            $point = [Drawing.PointF]::new($x,$y)
            if ($null -ne $prior) { $g.DrawLine($pen,$prior,$point) }
            else { $g.DrawEllipse($pen,[single]($x-2),[single]($y-2),[single]4,[single]4) }
            $prior = $point
        }
    }
})

function Show-Day {
    $periods.Rows.Clear(); $chart.Invalidate()
    if (!$files.CurrentRow -or $days.SelectedIndex -lt 0) { return }
    $item = $files.CurrentRow.Tag
    if (!$item) { return }
    $start = $days.SelectedIndex * 96
    $gapIndex = @{}
    foreach ($gap in $item.Plan.Gaps) {
        for ($i=[math]::Max($start,$gap.First); $i -le [math]::Min($start+95,$gap.Last); $i++) { $gapIndex[$i] = $gap }
    }
    for ($i=$start; $i -lt $start+96; $i++) {
        $gap = $gapIndex[$i]
        $source = $i
        if ($gap -and $null -ne $gap.Shift) { $source -= $gap.Shift }
        $pair = $item.Access[$source]
        $stamp = $item.Month.AddMinutes($i*15).ToString('HH:mm')
        $kw = $null
        $kwh = $null
        $sourceTime = $null
        $sourceKw = $null
        $sourceKwh = $null
        $state = 'หลังค่าล่าสุด'
        if ($item.Plan.Present[$i]) {
            $kw = $item.Plan.Demand[$i]
            $kwh = $item.Plan.Energy[$i]
            $state = 'มีข้อมูล TOU'
        } elseif ($gap) {
            $state = if ($gap.Reason) { $gap.Reason } else { 'พร้อมเติม' }
        }
        if ($null -ne $pair) {
            $sourceTime = $item.Month.AddMinutes($source*15).ToString('dd/MM HH:mm')
            $sourceKw = $pair[0]
            $sourceKwh = $pair[1]
        }
        [void]$periods.Rows.Add($stamp,$kw,$kwh,$sourceTime,$sourceKw,$sourceKwh,$state)
    }
}
$days.Add_SelectedIndexChanged({ Show-Day })
$files.Add_SelectionChanged({
    $apply.Enabled = @($files.SelectedRows | Where-Object { $_.Tag -and $_.Tag.Plan.Patches.Count }).Count -gt 0
    $days.Items.Clear()
    $periods.Rows.Clear(); $chart.Invalidate()
    if (!$files.CurrentRow -or !$files.CurrentRow.Tag) { return }
    $item = $files.CurrentRow.Tag
    $count = [datetime]::DaysInMonth($item.Month.Year,$item.Month.Month)
    foreach ($index in 0..($count-1)) { [void]$days.Items.Add($item.Month.AddDays($index).ToString('dd/MM/yyyy')) }
    $days.SelectedIndex = if ($null -ne $item.Gap) { [int][math]::Floor($item.Gap.First/96) } else { 0 }
})
$scan.Add_Click({
    $status.Text = 'กำลังสแกน…'
    $form.UseWaitCursor = $true
    $form.Refresh()
    try {
        $accessFolder,$touFolder = $inputs.Text
        if (![IO.Directory]::Exists($accessFolder) -or ![IO.Directory]::Exists($touFolder)) { throw 'กรุณาเลือกทั้งสองโฟลเดอร์' }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($config))
        @{access=$accessFolder;tou=$touFolder} | ConvertTo-Json | Set-Content -LiteralPath $config -Encoding utf8
        $files.Rows.Clear()
        $accessFiles = @{}
        $matched = @{}
        foreach ($file in Get-ChildItem -LiteralPath $accessFolder -File) {
            if ($file.Extension -in '.mdb','.accdb' -and $file.BaseName -match '^(D[0-9A-F]+)(?=_|$)') {
                $meter = $Matches[1].ToUpperInvariant()
                $accessFiles[$meter] = @($accessFiles[$meter] | Where-Object { $_ }) + $file
            }
        }
        $logs = @{}
        $count = 0
        foreach ($file in Get-ChildItem -LiteralPath $touFolder -Filter '*.tou' -File) {
            try {
                if ($file.Name -notmatch '^(D[0-9A-F]+)([A-Z]{3})([0-9]{2})\.tou$') { throw 'ชื่อไฟล์ไม่ตรงรูปแบบ D18Nov26.tou' }
                $meter = $Matches[1].ToUpperInvariant()
                $month = [datetime]::ParseExact(('01' + $Matches[2] + '20' + $Matches[3]),'ddMMMyyyy',$culture)
                $sources = $accessFiles[$meter]
                $matched[$meter] = $true
                $access = @{}
                $sourceStatus = ''
                if (!$sources) { $sourceStatus = 'ไม่พบ Access ที่ตรงกัน' }
                elseif ($sources.Count -gt 1) { $sourceStatus = 'พบ Access รหัสซ้ำ' }
                else {
                    if (!$logs.ContainsKey($meter)) {
                        try { $logs[$meter] = Read-Log $sources[0].FullName -StrictDuplicates }
                        catch { $logs[$meter] = $_.Exception.Message }
                    }
                    $log = $logs[$meter]
                    if ($log -is [string]) { $sourceStatus = $log }
                    else {
                        $key = $month.ToString('yyyy-MM',$culture)
                        if ($log.Months.ContainsKey($key)) { $access = $log.Months[$key] }
                        else { $sourceStatus = 'Access ไม่มีข้อมูลเดือนนี้' }
                    }
                }
                $bytes = [IO.File]::ReadAllBytes($file.FullName)
                $plan = Get-TouRepairPlan $bytes $month $access
                $item = [pscustomobject]@{Path=$file.FullName; Bytes=$bytes; Month=$month; Plan=$plan; Access=$access; Gap=$null}
                if (!$plan.Gaps.Count) {
                    $message = if ($sourceStatus) { $sourceStatus } elseif ($plan.Last -lt 0) { 'ไม่มีจุดอ้างอิง TOU' } else { 'ไม่พบช่องขาดก่อนค่าล่าสุด' }
                    $row = $files.Rows.Add($file.Name,'',$message)
                    $files.Rows[$row].Tag = $item
                }
                foreach ($gap in $plan.Gaps) {
                    $range = '{0:dd/MM HH:mm} ถึง {1:dd/MM HH:mm} ({2} ช่อง)' -f $month.AddMinutes($gap.First*15),$month.AddMinutes($gap.Last*15),($gap.Last-$gap.First+1)
                    $message = if ($sourceStatus) { $sourceStatus } elseif ($gap.Reason) { $gap.Reason } else { "พร้อมเติม · เลื่อนเวลา Access $($gap.Shift*15) นาที" }
                    $row = $files.Rows.Add($file.Name,$range,$message)
                    $files.Rows[$row].Tag = [pscustomobject]@{Path=$item.Path;Bytes=$bytes;Month=$month;Plan=$plan;Access=$access;Gap=$gap}
                }
                $count++
            } catch { [void]$files.Rows.Add($file.Name,'',$_.Exception.Message) }
        }
        foreach ($meter in $accessFiles.Keys) {
            if (!$matched[$meter]) { [void]$files.Rows.Add($meter,'','ไม่พบไฟล์ TOU ที่ตรงกัน') }
        }
        $status.Text = "อ่าน TOU $count ไฟล์"
    } catch { $status.Text = $_.Exception.Message }
    finally { $form.UseWaitCursor = $false }
})
$apply.Add_Click({
    $selected = @($files.SelectedRows | ForEach-Object { $_.Tag } |
        Where-Object { $_ -and $_.Plan.Patches.Count } | Group-Object Path | ForEach-Object { $_.Group[0] })
    if (!$selected.Count) { return }
    $slots = ($selected | ForEach-Object { $_.Plan.Patches.Count } | Measure-Object -Sum).Sum
    $answer = [Windows.Forms.MessageBox]::Show($form,"เติม $slots ช่องใน $($selected.Count) ไฟล์ที่เลือก และสร้างไฟล์สำรอง?",'ยืนยันเติมข้อมูล','YesNo')
    if ($answer -ne 'Yes') { return }
    $messages = @(foreach ($item in $selected) {
        $name = [IO.Path]::GetFileName($item.Path)
        try {
            $backup = Save-TouRepair $item.Path $item.Bytes $item.Plan.Patches
            "$name · เติมแล้ว · สำรองที่ $backup"
        } catch { "$name · " + $_.Exception.Message }
    })
    $scan.PerformClick()
    [void][Windows.Forms.MessageBox]::Show($form,($messages -join [Environment]::NewLine),'ผลการเติมข้อมูล')
})
[void]$form.ShowDialog()

