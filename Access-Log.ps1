$culture = [Globalization.CultureInfo]::InvariantCulture
function Read-Log([string]$Path, [switch]$StrictDuplicates) {
    $meter=[regex]::Match([IO.Path]::GetFileNameWithoutExtension($Path),'^D([0-9A-F]+)(?=_|$)','IgnoreCase')
    if (!$meter.Success) { throw 'Expected an Access filename beginning with a hexadecimal meter ID, e.g. D18_...' }
    $snapshot=Join-Path ((Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "Temp")) ("AccessTOU-"+[guid]::NewGuid()+[IO.Path]::GetExtension($Path))
    $connection=$null
    $reader=$null
    try {
        Copy-Item -LiteralPath $Path -Destination $snapshot
        foreach ($provider in 'Microsoft.ACE.OLEDB.16.0','Microsoft.ACE.OLEDB.12.0','Microsoft.Jet.OLEDB.4.0') {
            $builder=[Data.OleDb.OleDbConnectionStringBuilder]::new()
            $builder.Provider=$provider
            $builder["Data Source"]=[string]$snapshot
            $builder['Mode']='Read'
            $connection=[Data.OleDb.OleDbConnection]::new($builder.ConnectionString)
            try { $connection.Open(); break } catch { $openError += "$provider $($_.Exception.Message) "; $connection.Dispose(); $connection=$null }
        }
        if (!$connection) { throw "Cannot open Access file. Microsoft Access Database Engine must match PowerShell bitness. $openError" }
        $command=$connection.CreateCommand()
        $command.CommandText='SELECT [StringTime],[DoubleTime],[kW IMP BD],[kWh IMPORT] FROM [Data Log # 1] ORDER BY [DoubleTime],[Sequence]'
        $reader=$command.ExecuteReader()
        $months=@{}
        $skipped=0
        $duplicates=0
        while ($reader.Read()) {
            if ($reader.IsDBNull(0) -or $reader.IsDBNull(1) -or $reader.IsDBNull(2) -or $reader.IsDBNull(3) -or $reader.GetDouble(1) -le 0) { $skipped++; continue }
            $stamp=$reader.GetString(0).Trim() -replace '\s+',' '
            $time=[datetime]::MinValue
            if (![datetime]::TryParseExact($stamp,[string[]]@('M/d/yy H:mm:ss.FFF','M/d/yy H:mm:ss'),$culture,[Globalization.DateTimeStyles]::None,[ref]$time)) { $skipped++; continue }
            $year=2000+($time.Year%100)
            $slot=$time.Hour*4+[int][math]::Floor($time.Minute/15)
            if ($time.Minute%15 -ne 0 -or $time.Second -ne 0) { $skipped++; continue }
            $demand=$reader.GetDouble(2)
            $energy=$reader.GetDouble(3)
            if ([double]::IsNaN($demand) -or [double]::IsInfinity($demand) -or [double]::IsNaN($energy) -or [double]::IsInfinity($energy)) { $skipped++; continue }
            $key='{0:D4}-{1:D2}' -f $year,$time.Month
            if (!$months.ContainsKey($key)) { $months[$key]=@{} }
            $index=($time.Day-1)*96+$slot
            if ($months[$key].ContainsKey($index)) { $duplicates++; if ($StrictDuplicates) { $months[$key][$index] = $null; continue } }
            $months[$key][$index]=@($demand,$energy)
        }
        if (!$months.Count) { throw 'No usable 15-minute readings found in Data Log # 1.' }
        [pscustomobject]@{Meter=$meter.Value.ToUpperInvariant();Months=$months;Skipped=$skipped;Duplicates=$duplicates}
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($connection) { $connection.Dispose() }
        Remove-Item -LiteralPath $snapshot -ErrorAction SilentlyContinue
    }
}


