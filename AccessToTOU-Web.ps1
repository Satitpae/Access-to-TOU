param([string]$InputFile,[switch]$NoBrowser)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/Access-Log.ps1"
function Get-OutputName($Log,[string]$Key) {
    $start=[datetime]::ParseExact("$Key-01",'yyyy-MM-dd',$culture)
    $Log.Meter+$start.ToString('MMMyy',$culture)+'.tou'
}

function Get-TouBytes($Log,[string]$Key) {
    $start=[datetime]::ParseExact("$Key-01",'yyyy-MM-dd',$culture)
    $bytes=[byte[]]::new(64+3072*16)
    [Text.Encoding]::ASCII.GetBytes('TOUReg').CopyTo($bytes,0)
    $bytes[8]=64
    [Text.Encoding]::ASCII.GetBytes($start.ToString('dd/MM/yyyyHH:mm:ss',$culture)).CopyTo($bytes,10)
    foreach ($index in $Log.Months[$Key].Keys) {
        $pair=$Log.Months[$Key][$index]
        [BitConverter]::GetBytes([double]$pair[0]).CopyTo($bytes,64+16*$index)
        [BitConverter]::GetBytes([double]$pair[1]).CopyTo($bytes,72+16*$index)
    }
    ,$bytes
}


if (!$InputFile) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog=[Windows.Forms.OpenFileDialog]::new()
    $dialog.Filter='Access database (*.mdb;*.accdb)|*.mdb;*.accdb'
    try {
        if ($dialog.ShowDialog() -ne 'OK') { return }
        $InputFile=$dialog.FileName
    } finally { $dialog.Dispose() }
}
$log=Read-Log $InputFile
$folder=Join-Path (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Temp') ('AccessTOU-Web-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($folder)
$items=@(foreach ($key in ($log.Months.Keys | Sort-Object -Descending)) {
    $encoded=[Convert]::ToBase64String((Get-TouBytes $log $key))
    [pscustomobject]@{ month=$key; name=(Get-OutputName $log $key); slots=$log.Months[$key].Count; data=$encoded; present=@($log.Months[$key].Keys | Sort-Object) }
})
$json=ConvertTo-Json -InputObject $items -Depth 3 -Compress
$html=@'
<!doctype html>
<html lang="th">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Access to TOU</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#edf3f5;color:#142c38;font:16px/1.5 system-ui,sans-serif}main{max-width:760px;margin:8vh auto;padding:24px}h1{font-size:clamp(32px,7vw,56px);letter-spacing:-.05em;margin:0}p{margin:4px 0 22px;color:#48616d}.panel{background:white;border:1px solid #ccdde4;border-radius:16px;padding:22px}header,footer,label{display:flex;align-items:center;gap:14px}header,footer{justify-content:space-between;flex-wrap:wrap}label{padding:15px 0;border-bottom:1px solid #e0eaee}label span{margin-left:auto;color:#48616d;text-align:right}input{width:19px;height:19px;accent-color:#006d70}button{border:0;background:#006d70;color:white;padding:10px 15px;border-radius:9px;font:inherit;cursor:pointer}button.secondary{background:#e7f4f4;color:#00575a}button:disabled{opacity:.55;cursor:default}footer{margin-top:20px}small{color:#48616d}#downloads{display:grid;gap:8px;margin-top:12px}a{color:#006568}
.preview{margin-bottom:18px}.preview h2{margin:0;font-size:1.25rem}.preview nav{display:flex;flex-wrap:wrap;gap:8px;margin:16px 0}.preview nav button{background:#e7f4f4;color:#00575a}.preview nav button[aria-pressed=true]{background:#006d70;color:white}.preview label{display:inline-flex;padding:0;border:0}.preview select{font:inherit;padding:6px;border:1px solid #a4bec8;border-radius:6px}.preview table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}.preview td,.preview th{text-align:left;padding:8px;border-bottom:1px solid #e0eaee}.review-table{overflow:auto;max-height:430px}.review-table th{position:sticky;top:0;background:#f3f8fa}.preview svg{width:100%;height:auto}.preview h3{margin:12px 0 4px}.review-controls{display:flex;gap:12px;flex-wrap:wrap;margin:12px 0}.preview p{margin:8px 0}.missing{color:#9b4018}
</style>
<main>
<h1>Access to TOU</h1>
<p>เลือกเดือนที่ต้องการส่งออกเป็นไฟล์ .tou</p>
<section class="panel preview" aria-label="ตรวจข้อมูลก่อนส่งออก">
<header><h2>ตรวจข้อมูลรายเดือน</h2><label class="month-picker">เดือน <select id="review-month"></select></label></header>
<nav aria-label="มุมมองข้อมูล">
<button type="button" data-view="bill">บิลรายเดือน</button>
<button type="button" data-view="chart">กราฟรายเดือน</button>
<button type="button" data-view="period">ข้อมูลแต่ละ Period</button>
</nav>
<div id="review"></div>
</section>
<section class="panel">
<header><strong>เดือนที่มีข้อมูล</strong><button class="secondary" id="toggle" type="button">เลือกทั้งหมด</button></header>
<div id="months"></div>
<footer><button id="export" type="button" disabled>Export .tou</button><small id="status" aria-live="polite"></small></footer>
<div id="downloads"></div>
</section>
</main>
<script type="application/json" id="dataset">__DATA__</script>
<script>
const records = JSON.parse(document.querySelector('#dataset').textContent);
const months = document.querySelector('#months');
const downloads = document.querySelector('#downloads');
const toggle = document.querySelector('#toggle');
const status = document.querySelector('#status');
const exportButton = document.querySelector('#export');
const urls = [];
const boxes = records.map(record => {
  const row = document.createElement('label');
  const box = document.createElement('input');
  box.type = 'checkbox';
  const month = document.createElement('strong');
  month.textContent = record.month;
  const detail = document.createElement('span');
  detail.textContent = record.name + ' · ' + record.slots.toLocaleString() + ' ช่วง';
  row.append(box, month, detail);
  months.append(row);
  return box;
});
function update() {
  const count = boxes.filter(box => box.checked).length;
  status.textContent = 'เลือก ' + count + ' เดือน · ข้าม __SKIPPED__ แถว · ซ้ำ __DUPLICATES__ ช่อง';
  exportButton.disabled = count === 0;
  toggle.textContent = count === boxes.length ? 'ยกเลิกทั้งหมด' : 'เลือกทั้งหมด';
  downloads.replaceChildren();
  while (urls.length) URL.revokeObjectURL(urls.pop());
}
months.addEventListener('change', update);
toggle.addEventListener('click', () => {
  const select = boxes.some(box => !box.checked);
  boxes.forEach(box => { box.checked = select; });
  update();
});
exportButton.addEventListener('click', () => {
  update();
  const selected = records.filter((_, index) => boxes[index].checked);
  for (const record of selected) {
    const bytes = Uint8Array.from(atob(record.data), ch => ch.charCodeAt(0));
    const link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([bytes], {type:'application/octet-stream'}));
    urls.push(link.href);
    link.download = record.name;
    link.textContent = 'ดาวน์โหลด ' + record.name;
    downloads.append(link);
  }
  if (selected.length === 1) downloads.firstElementChild.click();
});
update();
</script>
<script>__REVIEW_SCRIPT__</script>
</html>
'@
$page=Join-Path $folder 'AccessToTOU.html'
$html=$html.Replace('__DATA__',$json).Replace('__SKIPPED__',[string]$log.Skipped).Replace('__DUPLICATES__',[string]$log.Duplicates)
$reviewScript=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'docs\review.js'))
[IO.File]::WriteAllText($page,$html.Replace('__REVIEW_SCRIPT__',$reviewScript))
if ($NoBrowser) { $page } else { Start-Process $page }

