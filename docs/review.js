(() => {
  const root = document.querySelector('#review');
  const month = document.querySelector('#review-month');
  const tabs = [...document.querySelectorAll('[data-view]')];
  const holidays = new Set('01-01 03-03 04-06 04-13 04-14 04-15 05-01 05-04 05-31 06-03 07-28 07-29 07-30 08-12 10-13 10-23 12-05 12-10 12-31'.split(' '));
  const format = new Intl.NumberFormat('th-TH',{maximumFractionDigits:2});
  const value = n => n == null ? '—' : format.format(n);
  let view = 'bill';
  let date = 'all';
  let filter = 'all';
  const cache = new Map();

  function analyze(record) {
    if (cache.has(record.month)) return cache.get(record.month);
    const bytes = Uint8Array.from(atob(record.data), ch => ch.charCodeAt(0));
    const binary = new DataView(bytes.buffer);
    const present = record.present ? new Set(record.present) : null;
    const [year,m] = record.month.split('-').map(Number);
    const start = Date.UTC(year,m-1,1);
    const length = new Date(Date.UTC(year,m,0)).getUTCDate()*96;
    const rows = Array.from({length}, (_,i) => {
      const timestamp = new Date(start+i*900000);
      const day = timestamp.toISOString().slice(0,10);
      const slot = i%96;
      const holiday = [0,6].includes(timestamp.getUTCDay()) || year===2026 && holidays.has(day.slice(5));
      const period = holiday ? 'Holiday' : slot>=36 && slot<88 ? 'On Peak' : 'Off Peak';
      const demand = binary.getFloat64(64+i*16,true);
      const energy = binary.getFloat64(72+i*16,true);
      return {day,time:timestamp.toISOString().slice(11,16),period,demand,energy,has:present ? present.has(i) : demand!==0 || energy!==0,delta:null};
    });
    const last = rows.findLastIndex(row => row.has);
    const isClosed = records.some(item=>item.month>record.month);
    const coverageEnd = isClosed ? rows.length-1 : last;
    const nextMonth = new Date(Date.UTC(year,m,1)).toISOString().slice(0,7);
    const nextRecord = records.find(item=>item.month===nextMonth);
    const boundaryBytes = nextRecord ? Uint8Array.from(atob(nextRecord.data.slice(0,108)), ch=>ch.charCodeAt(0)) : null;
    const boundaryView = boundaryBytes ? new DataView(boundaryBytes.buffer) : null;
    const boundary = boundaryView && (nextRecord.present ? nextRecord.present.includes(0) : boundaryView.getFloat64(64,true)!==0 || boundaryView.getFloat64(72,true)!==0)
      ? boundaryView.getFloat64(72,true) : null;
    const totals = Object.fromEntries(['On Peak','Off Peak','Holiday'].map(p => [p,{energy:null,peak:null,missing:0}]));
    const days = [];
    let resets = 0;
    for (const [i,row] of rows.entries()) {
      const dayIndex = Math.floor(i/96);
      if (i%96===0) days.push({day:row.day,energy:null,peak:null});
      const daily = days[dayIndex];
      const group = totals[row.period];
      if (!row.has) {
        if (i<=coverageEnd) group.missing++;
        continue;
      }
      group.peak = Math.max(group.peak ?? -Infinity,row.demand);
      daily.peak = Math.max(daily.peak ?? -Infinity,row.demand);
      const next = rows[i+1];
      const endEnergy = next ? (next.has ? next.energy : null) : boundary;
      if (endEnergy==null) continue;
      if (endEnergy < row.energy) { resets++; continue; }
      row.delta = endEnergy-row.energy;
      daily.energy = (daily.energy ?? 0)+row.delta;
      group.energy = (group.energy ?? 0)+row.delta;
    }
    const result = {rows,last:coverageEnd,days,totals,resets,year};
    cache.set(record.month,result);
    return result;
  }

  function table(headings,body) {
    return '<div class="review-table"><table><thead><tr>'+headings.map(h=>'<th>'+h+'</th>').join('')+'</tr></thead><tbody>'+body+'</tbody></table></div>';
  }
  const cells = values => values.map(x=>'<td>'+x+'</td>').join('');
  function graph(days,field,title,unit) {
    const max = Math.max(1,...days.map(d=>d[field] ?? 0));
    const width = 660, height = 135, step = 605/days.length;
    const bars = days.map((d,i)=>{
      const n=d[field], x=44+i*step;
      const tick = i%5===0 || i===days.length-1 ? '<text x="'+(x+step/2)+'" y="123" text-anchor="middle">'+(i+1)+'</text>' : '';
      const h=n==null ? 0 : Math.max(1,n/max*85);
      return (n==null ? '' : '<rect x="'+x+'" y="'+(104-h)+'" width="'+Math.max(1,step-3)+'" height="'+h+'" fill="#007e82"><title>'+d.day+' · '+value(n)+' '+unit+'</title></rect>')+tick;
    }).join('');
    return '<h3>'+title+'</h3><svg viewBox="0 0 '+width+' '+height+'" role="img" aria-label="'+title+' ('+unit+')"><g font-size="10" fill="#48616d"><text x="1" y="19">'+value(max)+'</text><text x="22" y="108">0</text><path d="M40 104H650" stroke="#a4bec8"/>'+bars+'</g></svg>';
  }
  function render() {
    const record = records.find(r=>r.month===month.value);
    if (!record) return;
    const info = analyze(record);
    const {rows,last,days,totals,resets,year} = info;
    tabs.forEach(tab=>tab.setAttribute('aria-pressed',String(tab.dataset.view===view)));
    if (view==='bill') {
      const groups = Object.entries(totals);
      const energies = groups.map(([,t])=>t.energy).filter(n=>n!=null);
      const peak = groups.map(([,t])=>t.peak).filter(n=>n!=null);
      const missing = groups.reduce((sum,[,t])=>sum+t.missing,0);
      const body = groups.map(([p,t])=>'<tr>'+cells([p,value(t.energy),value(t.peak),value(t.missing)])+'</tr>').join('') +
        '<tr>'+cells(['<strong>รวม</strong>',value(energies.length ? energies.reduce((a,b)=>a+b,0) : null),value(peak.length ? Math.max(...peak) : null),value(missing)])+'</tr>';
      root.innerHTML = '<p>สรุปหน่วยก่อนคิดค่าไฟ · '+record.name+'</p>'+table(['Period','พลังงาน (kWh)','สูงสุด (kW)','ช่องที่ขาด'],body)+
        '<p class="missing">คำนวณ kWh จากเลขสะสมสองจุดติดกัน ช่องที่คำนวณไม่ได้จะไม่รวมในยอด'+(resets ? ' · เลขสะสมลดลง '+resets+' ช่วง' : '')+'</p>'+
        '<p>On Peak จันทร์–ศุกร์ 09:00–22:00 · Holiday รวมเสาร์ อาทิตย์'+(year===2026 ? ' และวันหยุดตามปฏิทิน TOU 2569' : ' · ยังไม่มีปฏิทินวันหยุดปี '+year)+'</p>';
    } else if (view==='chart') {
      root.innerHTML = '<p>แกนนอนแสดงวันที่ในเดือน ช่องว่างคือวันที่ไม่มีค่าที่คำนวณได้</p>'+graph(days,'energy','พลังงานรายวัน','kWh')+graph(days,'peak','Demand สูงสุดรายวัน','kW');
    } else {
      const controls='<div class="review-controls"><label>วันที่ <select id="review-day"><option value="all">ทั้งเดือน</option>'+days.map(d=>'<option>'+d.day+'</option>').join('')+'</select></label><label>สถานะ <select id="review-filter"><option value="all">ทั้งหมด</option><option value="missing">ขาดก่อนจุดล่าสุด</option><option value="pending">หลังจุดล่าสุด</option><option value="recorded">มีข้อมูล</option></select></label></div>';
      const body = rows.map((r,i)=>{
        const key=r.has?'recorded':i<=last?'missing':'pending';
        if ((date!=='all' && date!==r.day) || (filter!=='all' && filter!==key)) return '';
        const status=r.has?'มีข้อมูล':key==='missing'?'<span class="missing">ขาด</span>':'หลังจุดล่าสุด';
        return '<tr>'+cells([r.day,r.time,r.period,r.has?value(r.demand):'—',r.has?value(r.energy):'—',value(r.delta),status])+'</tr>';
      }).join('');
      root.innerHTML=controls+table(['วันที่','เวลา','Period','kW','kWh สะสม','Δ kWh','สถานะ'],body || '<tr><td colspan="7">ไม่พบข้อมูลตามตัวกรอง</td></tr>');
      const day = root.querySelector('#review-day'), state = root.querySelector('#review-filter');
      day.value=date;
      state.value=filter;
      day.onchange=()=>{date=day.value;render();};
      state.onchange=()=>{filter=state.value;render();};
    }
  }
  for (const record of records) month.add(new Option(record.month,record.month));
  month.onchange=()=>{date='all';render();};
  tabs.forEach(tab=>tab.onclick=()=>{view=tab.dataset.view;render();});
  render();
})();