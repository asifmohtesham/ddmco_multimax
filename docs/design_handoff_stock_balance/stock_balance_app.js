// Stock Balance — interactive enhancements prototype
// Demonstrates: (1) hide out-of-stock, (2) item images, (3) client-side
// quick-filters mapped to report options, (4) tap-to-navigate drill-downs.

/* ───────────────────────── data ───────────────────────── */
// One object per report row, mirroring the Dart row Map keys.
const ROWS = [
  { item_code:'2002855', item_name:'BELTS FORMAL AUTO CP',       cat:'belt',  warehouse:'WH-DXB3 · KA',   rack:'BLOCK 1', opening:12, in:0,  out:0,  bal:12,  reserved:0,   rate:0,     val:0,     customer:'5067049', img:true },
  { item_code:'2003120', item_name:'WALLET BIFOLD LEATHER BLK',  cat:'wallet',warehouse:'WH-DXB3 · KA',   rack:'BLOCK 3', opening:180,in:64, out:24, bal:220, reserved:200, rate:38.5,  val:8470,  customer:'5067049', img:true },
  { item_code:'2001045', item_name:'BELT AUTOMATIC NICKEL 35MM', cat:'belt',  warehouse:'WH-DXB3 · KA',   rack:'BLOCK 2', opening:4,  in:0,  out:10, bal:-6,  reserved:0,   rate:21,    val:-126,  customer:'5067049', img:true },
  { item_code:'2004890', item_name:'CARD HOLDER SLIM TAN',       cat:'card',  warehouse:'WH-DXB1 · MAIN', rack:'',        opening:0,  in:0,  out:0,  bal:0,   reserved:0,   rate:0,     val:0,     customer:'5068213', img:false },
  { item_code:'2002770', item_name:'BELTS FORMAL AUTO CP BROWN', cat:'belt',  warehouse:'WH-DXB3 · KA',   rack:'BLOCK 1', opening:96, in:48, out:60, bal:84,  reserved:12,  rate:42,    val:3528,  customer:'5067112', img:true },
  { item_code:'2003355', item_name:'WALLET TRIFOLD TAN',         cat:'wallet',warehouse:'WH-DXB3 · KA',   rack:'BLOCK 3', opening:52, in:0,  out:12, bal:40,  reserved:6,   rate:45,    val:1800,  customer:'5067112', img:true },
  { item_code:'2005010', item_name:'KEY POUCH BLACK',            cat:'pouch', warehouse:'WH-DXB1 · MAIN', rack:'',        opening:8,  in:0,  out:8,  bal:0,   reserved:0,   rate:18,    val:0,     customer:'5068213', img:false },
  { item_code:'2001660', item_name:'BELT REVERSIBLE 30MM',       cat:'belt',  warehouse:'WH-DXB1 · MAIN', rack:'A2',      opening:120,in:60, out:30, bal:150, reserved:145, rate:26,    val:3900,  customer:'5067049', img:true },
  { item_code:'2004120', item_name:'CARD HOLDER ZIP NAVY',       cat:'card',  warehouse:'WH-DXB3 · KA',   rack:'BLOCK 2', opening:2,  in:0,  out:5,  bal:-3,  reserved:0,   rate:28,    val:-84,   customer:'5067112', img:true },
  { item_code:'2002990', item_name:'WALLET SLIM RFID GRY',       cat:'wallet',warehouse:'WH-DXB1 · MAIN', rack:'B1',      opening:40, in:40, out:15, bal:65,  reserved:8,   rate:52,    val:3380,  customer:'5068213', img:true },
];

// Synthetic stock-ledger entries for the drill-down (tap-to-navigate target).
function ledgerFor(r){
  const e=[]; let bal=r.opening;
  e.push({date:'2026-06-21 08:02', voucher:'Opening', type:'Opening', qty:0, bal});
  if(r.in){ bal+=r.in; e.push({date:'2026-06-21 09:15', voucher:'MAT-PRE-2026-0142', type:'Purchase Receipt', qty:r.in, bal}); }
  if(r.out){ bal-=r.out; e.push({date:'2026-06-21 13:40', voucher:'MAT-DN-2026-0391', type:'Delivery Note', qty:-r.out, bal}); }
  return e;
}
// Synthetic reservations behind the "Reserved" figure.
function reservationsFor(r){
  if(r.reserved<=0) return [];
  const out=[]; let left=r.reserved; const sos=['SO-2026-1187','SO-2026-1190','SO-2026-1204'];
  for(let i=0;i<sos.length && left>0;i++){ const q=i===sos.length-1?left:Math.ceil(left*0.55); out.push({so:sos[i], cust:r.customer, qty:Math.min(q,left)}); left-=q; }
  return out;
}

/* ───────────────────────── state ───────────────────────── */
const LS='mm_sb_v2';
const ui = Object.assign({ q:'', warehouse:'ALL', state:'ALL', sort:'bal', hideEmpty:false, showImg:true },
  JSON.parse(localStorage.getItem(LS)||'{}'));
function persist(){ localStorage.setItem(LS, JSON.stringify(ui)); }

const CUR='AED';
const fmtQty = n => Number.isInteger(n)? String(n) : (Math.round(n*100)/100).toString();
const fmtMoney = n => (n<0?'−':'')+CUR+' '+Math.abs(n).toLocaleString('en-US',{maximumFractionDigits:2});

function stateOf(r){
  if(r.bal<0) return 'neg';
  if(r.bal===0) return 'empty';
  if(r.reserved >= r.bal*0.8) return 'watch';
  return 'ok';
}

/* ───────────────────────── category thumbnails ───────────────────────── */
// Honest placeholder: tinted slot + product line-icon (where ERPNext item.image
// would load). Items without an image fall back to a code-initial tile.
const CAT = {
  belt:  {tint:'#b45309', ic:'M3 11h18v2H3zM6.5 9.5h2v5h-2zM10 10.5a1.5 1.5 0 1 1 3 0a1.5 1.5 0 0 1-3 0Z'},
  wallet:{tint:'#1d4ed8', ic:'M4 6h14a2 2 0 0 1 2 2v1h-5a2 2 0 0 0 0 4h5v1a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2Zm12.5 4.5a1 1 0 1 0 0 2a1 1 0 0 0 0-2Z'},
  card:  {tint:'#0f766e', ic:'M3 6h18a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1Zm0 3v2h18V9H3Zm2 5h6v1.5H5V14Z'},
  pouch: {tint:'#7c3aed', ic:'M7 8V6a5 5 0 0 1 10 0v2h1.5l1 11h-15l1-11H7Zm2 0h6V6a3 3 0 0 0-6 0v2Z'},
};
function thumb(r){
  const c=CAT[r.cat]||CAT.belt;
  if(!r.img){
    const init=r.item_name.replace(/[^A-Z ]/g,'').trim().split(/\s+/).slice(0,2).map(w=>w[0]).join('');
    return `<div class="sb-thumb fallback" aria-hidden="true"><span>${init||'··'}</span></div>`;
  }
  return `<div class="sb-thumb" style="--ti:${c.tint}" aria-hidden="true">
      <svg viewBox="0 0 24 24"><path d="${c.ic}"/></svg></div>`;
}

/* ───────────────────────── card render ───────────────────────── */
function card(r){
  const st=stateOf(r);
  const avail=Math.max(0, r.bal - r.reserved), resv=Math.min(Math.max(r.reserved,0), r.bal>0?r.bal:0);
  const total=avail+resv||1;
  const freeW=avail<=0?0:Math.max(4, avail/total*100), resvW=resv<=0?0:Math.max(4, resv/total*100);
  const zeroRate = r.rate===0 && r.val===0;

  const commit = r.bal>0
    ? `<div class="sb-avail">
         <div class="sb-bar"><i class="free" style="width:${freeW}%"></i><i class="resv" style="width:${resvW}%"></i></div>
         <div class="lab">
           <span class="k free">Available <b>${fmtQty(avail)}</b></span>
           <button class="k resv tap" data-act="reserved" ${resv>0?'':'disabled'}>Reserved <b>${fmtQty(resv)}</b>${resv>0?'<svg class="chev" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg>':''}</button>
         </div>
       </div>`
    : r.bal<0
    ? `<div class="sb-note neg"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>Negative stock — issued beyond on-hand qty</div>`
    : `<div class="sb-note empty"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M20 6h-3V4c0-1.1-.9-2-2-2H9c-1.1 0-2 .9-2 2v2H4v2h1v11c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V8h1V6zM9 4h6v2H9V4z"/></svg>Out of stock — no movement in period</div>`;

  return `<article class="sb-card ${st}" data-code="${r.item_code}">
    <button class="sb-open" data-act="ledger" aria-label="Open stock ledger for ${r.item_code}"></button>
    <div class="sb-head">
      ${ui.showImg?thumb(r):''}
      <div class="sb-id">
        <div class="sb-code">${r.item_code}</div>
        <div class="sb-name">${r.item_name}</div>
      </div>
      <div class="sb-balance"><span class="sb-qty">${fmtQty(r.bal)}</span><span class="sb-uom">Nos</span></div>
    </div>
    <div class="sb-loc">
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z"/></svg>
      <button class="wh tap" data-act="warehouse"><b>${r.warehouse}</b></button><span class="sep">·</span>
      ${r.rack? `<span class="rack">Rack <b>${r.rack}</b></span>` : `<span class="norack">No rack assigned</span>`}
    </div>
    <div class="sb-ledger">
      <div class="cell"><span class="k">Opening</span><span class="v">${fmtQty(r.opening)}</span></div>
      <div class="cell in"><span class="k">In</span><span class="v ${r.in?'':'zero'}">${r.in?'+'+fmtQty(r.in):'0'}</span></div>
      <div class="cell out"><span class="k">Out</span><span class="v ${r.out?'':'zero'}">${r.out?'−'+fmtQty(r.out):'0'}</span></div>
      <div class="cell bal"><span class="k">Balance</span><span class="v">${fmtQty(r.bal)}</span></div>
    </div>
    ${commit}
    <div class="sb-meta">
      <span class="m ${zeroRate?'muted':''}">Rate <b>${zeroRate?'0.00':fmtMoney(r.rate)}</b></span>
      <span class="m ${zeroRate?'muted':''}">Value <b>${zeroRate?'0.00':fmtMoney(r.val)}</b></span>
      <button class="cust tap" data-act="customer"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-4.42 0-8 2.24-8 5v1h16v-1c0-2.76-3.58-5-8-5z"/></svg>${r.customer}<svg class="chev" viewBox="0 0 24 24"><path d="M9 6l6 6-6 6"/></svg></button>
    </div>
  </article>`;
}

/* ───────────────────────── filtering + sorting ───────────────────────── */
function visibleRows(){
  let rows = ROWS.slice();
  if(ui.warehouse!=='ALL') rows=rows.filter(r=>r.warehouse===ui.warehouse);
  if(ui.q){ const q=ui.q.toLowerCase(); rows=rows.filter(r=>r.item_code.includes(q)||r.item_name.toLowerCase().includes(q)); }
  if(ui.state!=='ALL') rows=rows.filter(r=>{ const s=stateOf(r);
    return ui.state==='neg'? s==='neg' : ui.state==='instock'? (r.bal>0) : ui.state==='empty'? s==='empty' : true; });
  if(ui.hideEmpty) rows=rows.filter(r=>r.bal!==0);
  const sorters={ bal:(a,b)=>a.bal-b.bal, val:(a,b)=>b.val-a.val,
    move:(a,b)=>(b.in+b.out)-(a.in+a.out), code:(a,b)=>a.item_code.localeCompare(b.item_code) };
  rows.sort(sorters[ui.sort]||sorters.bal);
  return rows;
}

/* ───────────────────────── render shell ───────────────────────── */
function render(){
  const rows=visibleRows();
  const negTotal=ROWS.filter(r=>r.bal<0).length;
  const whs=[...new Set(ROWS.map(r=>r.warehouse))];

  // summary strip
  document.getElementById('sb-counts').innerHTML =
    `<b>${rows.length}</b> shown <span class="sep">·</span> <b>${whs.length}</b> warehouse${whs.length>1?'s':''}`;
  const alert=document.getElementById('sb-neg');
  alert.style.display = negTotal>0?'inline-flex':'none';
  alert.classList.toggle('on', ui.state==='neg');
  alert.querySelector('b').textContent=negTotal;

  // hide-empty switch
  document.getElementById('sw-empty').classList.toggle('on', ui.hideEmpty);
  document.getElementById('sw-img').classList.toggle('on', ui.showImg);

  // warehouse facet options
  const whSel=document.getElementById('f-wh');
  if(whSel.dataset.built!=='1'){
    whSel.innerHTML = `<option value="ALL">All warehouses</option>`+whs.map(w=>`<option value="${w}">${w}</option>`).join('');
    whSel.dataset.built='1';
  }
  whSel.value=ui.warehouse;
  document.getElementById('f-sort').value=ui.sort;
  document.getElementById('f-q').value=ui.q;

  // state segments
  document.querySelectorAll('#seg .seg').forEach(b=>b.classList.toggle('on', b.dataset.state===ui.state));

  // list
  const list=document.getElementById('sb-list');
  if(rows.length){
    list.innerHTML = rows.map(card).join('');
  } else {
    list.innerHTML = `<div class="empty-state">
      <svg viewBox="0 0 24 24" fill="currentColor"><path d="M11 18h2v-2h-2v2zm1-16C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm0-14a4 4 0 0 0-4 4h2a2 2 0 1 1 4 0c0 2-3 1.75-3 5h2c0-2.25 3-2.5 3-5a4 4 0 0 0-4-4z"/></svg>
      <p>No items match these filters</p>
      <button id="reset-empty">Clear quick filters</button></div>`;
    const rb=document.getElementById('reset-empty');
    rb && rb.addEventListener('click',()=>{ ui.q='';ui.warehouse='ALL';ui.state='ALL';ui.hideEmpty=false; persist(); render(); });
  }
  persist();
}

/* ───────────────────────── drill-down sheets (tap-to-navigate) ───────────────────────── */
const sheet=document.getElementById('sheet'), scrim=document.getElementById('scrim');
function openSheet(html){ sheet.innerHTML=html; sheet.classList.add('on'); scrim.classList.add('on'); }
function closeSheet(){ sheet.classList.remove('on'); scrim.classList.remove('on'); }
scrim.addEventListener('click', closeSheet);

function sheetHead(eyebrow,title,sub){
  return `<div class="sh-grip"></div>
    <div class="sh-head"><div><div class="sh-eyebrow">${eyebrow}</div><div class="sh-title">${title}</div>
    ${sub?`<div class="sh-sub">${sub}</div>`:''}</div>
    <button class="sh-x" data-close aria-label="Close"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg></button></div>`;
}

function ledgerSheet(r){
  const rows=ledgerFor(r).map(e=>`<div class="led-row">
      <div class="led-l"><div class="led-v">${e.voucher}</div><div class="led-t">${e.type} · ${e.date}</div></div>
      <div class="led-q ${e.qty>0?'pos':e.qty<0?'neg':''}">${e.qty>0?'+':''}${e.qty?fmtQty(e.qty):'—'}</div>
      <div class="led-b">${fmtQty(e.bal)}</div></div>`).join('');
  openSheet(sheetHead('Stock Ledger', r.item_code, r.item_name)+`
    <div class="sh-route"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 13h2v-2H3v2zm0 4h2v-2H3v2zm0-8h2V7H3v2zm4 4h14v-2H7v2zm0 4h14v-2H7v2zM7 7v2h14V7H7z"/></svg>Stock Ledger › ${r.item_code} · ${r.warehouse}</div>
    <div class="led-th"><span>Voucher</span><span>Qty</span><span>Balance</span></div>
    <div class="led-list">${rows}</div>
    <button class="sh-cta">Open full Stock Ledger Entry<svg viewBox="0 0 24 24" fill="currentColor"><path d="M14 5l7 7-7 7-1.4-1.4L17.2 13H3v-2h14.2l-4.6-4.6z"/></svg></button>`);
}
function reservedSheet(r){
  const rows=reservationsFor(r).map(x=>`<div class="led-row">
      <div class="led-l"><div class="led-v">${x.so}</div><div class="led-t">Customer ${x.cust}</div></div>
      <div class="led-b resv">${fmtQty(x.qty)}</div></div>`).join('');
  openSheet(sheetHead('Reserved stock', fmtQty(r.reserved)+' Nos committed', r.item_name)+`
    <div class="sh-route"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm-9 14l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>Sales Orders reserving ${r.item_code}</div>
    <div class="led-th"><span>Sales Order</span><span>Reserved</span></div>
    <div class="led-list">${rows}</div>
    <button class="sh-cta">View all reservations<svg viewBox="0 0 24 24" fill="currentColor"><path d="M14 5l7 7-7 7-1.4-1.4L17.2 13H3v-2h14.2l-4.6-4.6z"/></svg></button>`);
}
function customerSheet(r){
  const items=ROWS.filter(x=>x.customer===r.customer);
  const rows=items.map(x=>`<div class="led-row">
      <div class="led-l"><div class="led-v">${x.item_code}</div><div class="led-t">${x.item_name}</div></div>
      <div class="led-b">${fmtQty(x.bal)}</div></div>`).join('');
  openSheet(sheetHead('Customer Code', r.customer, items.length+' linked items')+`
    <div class="sh-route"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10zm0 2c-4.42 0-8 2.24-8 5v1h16v-1c0-2.76-3.58-5-8-5z"/></svg>Items mapped to ${r.customer}</div>
    <div class="led-th"><span>Item</span><span>Balance</span></div>
    <div class="led-list">${rows}</div>
    <button class="sh-cta" data-filter-cust="${r.customer}">Filter report to this customer<svg viewBox="0 0 24 24" fill="currentColor"><path d="M14 5l7 7-7 7-1.4-1.4L17.2 13H3v-2h14.2l-4.6-4.6z"/></svg></button>`);
}

/* ───────────────────────── events ───────────────────────── */
document.getElementById('sb-list').addEventListener('click', e=>{
  const card=e.target.closest('.sb-card'); if(!card) return;
  const r=ROWS.find(x=>x.item_code===card.dataset.code); if(!r) return;
  const act=e.target.closest('[data-act]')?.dataset.act;
  if(act==='reserved'){ reservedSheet(r); }
  else if(act==='customer'){ customerSheet(r); }
  else if(act==='warehouse'){ ui.warehouse=r.warehouse; render(); }
  else { ledgerSheet(r); } // tile body / ledger button
});
sheet.addEventListener('click', e=>{
  if(e.target.closest('[data-close]')) return closeSheet();
  const cust=e.target.closest('[data-filter-cust]');
  if(cust){ /* demo: customer filter lives in the report sheet; just close */ closeSheet(); }
});

document.getElementById('f-q').addEventListener('input', e=>{ ui.q=e.target.value.trim(); render(); });
document.getElementById('f-wh').addEventListener('change', e=>{ ui.warehouse=e.target.value; render(); });
document.getElementById('f-sort').addEventListener('change', e=>{ ui.sort=e.target.value; render(); });
document.getElementById('seg').addEventListener('click', e=>{ const b=e.target.closest('.seg'); if(!b) return; ui.state=b.dataset.state; render(); });
document.getElementById('sb-neg').addEventListener('click', ()=>{ ui.state = ui.state==='neg'?'ALL':'neg'; render(); });
document.getElementById('sw-empty').addEventListener('click', ()=>{ ui.hideEmpty=!ui.hideEmpty; render(); });
document.getElementById('sw-img').addEventListener('click', ()=>{ ui.showImg=!ui.showImg; render(); });

render();
