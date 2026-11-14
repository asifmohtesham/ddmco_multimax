/* Item Variant Details — baseline + redesign (Cards/Compact toggle) + revamped image gallery. */

const VD_DATA = [
  { code:'1002092', name:'WALLETS MTR HQ', cat:'Wallets', brand:'FOCUS', material:'Material - B', type:'MEDIUM', flap:'DOUBLE FLAP',   stock:24, uom:'PCS', hue:'var(--blue-500)' },
  { code:'1001951', name:'WALLETS COW',    cat:'Wallets', brand:'CLIFF', material:'Cow - DD',     type:'MEDIUM', flap:'MIDDLE DOUBLE', stock:10, uom:'PCS', hue:'var(--cyan-500)' },
  { code:'1000927', name:'WALLETS COW',    cat:'Wallets', brand:'CLIFF', material:'Cow - DD',     type:'MEDIUM', loop:'ROUND ELASTIC', flap:'LEFT UP', stock:0, uom:'PCS', noImg:true },
  { code:'1000841', name:'WALLETS MTR',    cat:'Wallets', brand:'FOCUS', material:'Material - A', type:'SMALL',  flap:'SINGLE FLAP',   stock:6,  uom:'PCS', hue:'var(--purple-500)' },
];
const GALLERY = VD_DATA.filter(v => !v.noImg);
const attrsOf = (v) => [v.brand, v.material, v.type, v.loop || v.flap].filter(Boolean);

const ICON = {
  menu:  <svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z"/></svg>,
  filter:<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 18h4v-2h-4v2zM3 6v2h18V6H3zm3 7h12v-2H6v2z"/></svg>,
  x:     <svg viewBox="0 0 24 24" fill="currentColor"><path d="M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/></svg>,
  stock: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="4" rx="1"/><path d="M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8M9 12h6"/></svg>,
  chev:  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="m9 6 6 6-6 6"/></svg>,
  chevL: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="m15 6-6 6 6 6"/></svg>,
  cards: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="13" width="18" height="7" rx="1.5"/></svg>,
  rows:  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01"/></svg>,
  image: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="18" height="18" rx="2.5"/><circle cx="8.5" cy="8.5" r="1.6"/><path d="m21 15-4.5-4.5L5 21"/></svg>,
  imageOff: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3 3l18 18M21 15l-5-5M3.5 3.5A2 2 0 0 0 3 5v14a2 2 0 0 0 2 2h14a2 2 0 0 0 1.5-.7M8.5 8.5 5 21"/></svg>,
  expand: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"/></svg>,
  ext:   <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6M15 3h6v6M10 14 21 3"/></svg>,
  zoom:  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3M11 8v6M8 11h6"/></svg>,
};

/* product-photo placeholder (striped, on-brief) */
function ImgPH({ v, label, big }){
  if (v && v.noImg){
    return (
      <div className={"imgph imgph-no"+(big?" big":"")}>
        {ICON.imageOff}
        {big && <span className="imgph-cap">no photo</span>}
      </div>
    );
  }
  return (
    <div className={"imgph"+(big?" big":"")} style={{['--ih']: (v && v.hue) || 'var(--blue-500)'}}>
      {ICON.image}
      {big && <span className="imgph-cap">wallet · {v ? v.code : ''}</span>}
    </div>
  );
}

function StatusBar(){
  return (
    <div className="vd-status">
      <span className="clk">22:19</span>
      <span className="sys">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.93 2.93 7.08 2.93 1 9zm8 8l3 3 3-3c-1.65-1.66-4.34-1.66-6 0zm-4-4 2 2c2.76-2.76 7.24-2.76 10 0l2-2C15.14 9.14 8.87 9.14 5 13z"/></svg>
        <span className="batt">100
          <svg width="20" height="12" viewBox="0 0 24 13" fill="none"><rect x="1" y="1" width="19" height="11" rx="2.5" stroke="currentColor" strokeWidth="1.4"/><rect x="2.6" y="2.6" width="14.5" height="7.8" rx="1.2" fill="currentColor"/><rect x="21" y="4" width="2" height="5" rx="1" fill="currentColor"/></svg>
        </span>
      </span>
    </div>
  );
}

function Phone({ children, tone }){
  return (
    <div className={"vd-phone" + (tone ? " "+tone : "")}>
      <StatusBar/>
      <div className="vd-screen">{children}</div>
    </div>
  );
}

const statusOf = (s) => s === 0 ? 'out' : s < 10 ? 'low' : 'ok';
const statusWord = (s) => s === 0 ? 'Out of stock' : s < 10 ? 'Low stock' : 'In stock';

/* ============ BASELINE (recreates the current screen) ============ */
function Baseline(){
  return (
    <Phone tone="vd-pink">
      <div className="bl-h1">Item Variant Details</div>
      <div className="bl-bar">
        <button className="bl-menu">{ICON.menu}</button>
        <span className="bl-h2">Item Variant Details</span>
        <button className="bl-filt">{ICON.filter}<span className="bl-badge">1</span></button>
      </div>
      <div className="bl-chiprow">
        <span className="bl-chip">{ICON.filter}<span>Item: 895C</span><span className="bl-cx">{ICON.x}</span></span>
      </div>
      <div className="bl-list">
        {VD_DATA.map(v => (
          <div className="bl-card" key={v.code}>
            <div className="bl-top">
              <div className="bl-num">{v.code.slice(0,2)}</div>
              <div className="bl-id">
                <div className="bl-code">{v.code}</div>
                <div className="bl-name">{v.name}</div>
                <div className="bl-cat">{v.cat}</div>
              </div>
              <span className="bl-chev">{ICON.chev}</span>
            </div>
            <div className="bl-chips">
              <span className="bl-attr">Brand: {v.brand}</span>
              <span className="bl-attr">Material: {v.material}</span>
              <span className="bl-attr">Type: {v.type}</span>
              <span className="bl-attr">Flap: {v.flap}</span>
            </div>
            <button className="bl-cta">{ICON.stock} Check Stock</button>
          </div>
        ))}
      </div>
    </Phone>
  );
}

/* ---- prominent balance-qty pill (qty + UOM) ---- */
function QtyPill({ v }){
  const st = statusOf(v.stock);
  return (
    <div className={"a-stock s-"+st}>
      <div className="a-qrow"><span className="a-qty">{v.stock}</span><span className="a-quom">{v.uom}</span></div>
      <span className="a-qcap">{statusWord(v.stock)}</span>
    </div>
  );
}

/* ---- Cards (A) ---- */
function ACard({ v, onOpen }){
  const st = statusOf(v.stock);
  return (
    <div className={"a-card s-"+st}>
      <div className="a-top">
        <button className="a-thumb" onClick={()=>!v.noImg && onOpen(v.code)} disabled={v.noImg}>
          <ImgPH v={v}/>
          {!v.noImg && <span className="a-thumb-z">{ICON.expand}</span>}
        </button>
        <div className="a-id">
          <div className="a-name">{v.name}</div>
          <div className="a-code">{v.code}<span className="a-dot">·</span>{v.cat}</div>
        </div>
        <QtyPill v={v}/>
      </div>
      <div className="a-kv">
        <div className="kv"><span className="k">Brand</span><span className="v">{v.brand}</span></div>
        <div className="kv"><span className="k">Material</span><span className="v">{v.material}</span></div>
        <div className="kv"><span className="k">Type</span><span className="v">{v.type}</span></div>
        <div className="kv"><span className="k">{v.loop ? 'Loop' : 'Flap'}</span><span className="v">{v.loop || v.flap}</span></div>
      </div>
      <div className="a-foot">
        <button className="a-ghost">{ICON.stock} Check stock</button>
        <span className="a-go">View {ICON.chev}</span>
      </div>
    </div>
  );
}

/* ---- Compact (B) ---- */
function BRow({ v, onOpen }){
  const st = statusOf(v.stock);
  return (
    <div className={"b-row s-"+st}>
      <span className="b-acc"></span>
      <button className="b-thumb" onClick={()=>!v.noImg && onOpen(v.code)} disabled={v.noImg}><ImgPH v={v}/></button>
      <div className="b-main">
        <div className="b-line1"><span className="b-name">{v.name}</span><span className="b-code">{v.code}</span></div>
        <div className="b-attrs">{attrsOf(v).join(' · ')}</div>
      </div>
      <div className="b-right">
        <span className="b-qty">{v.stock}</span>
        <span className="b-uom">{v.uom}</span>
      </div>
      <span className="b-chev">{ICON.chev}</span>
    </div>
  );
}

/* ============ REVAMPED IMAGE GALLERY (cross-variant photo browser) ============ */
function GalleryView({ initialIndex, onClose }){
  const [i, setI] = React.useState(initialIndex || 0);
  const items = GALLERY;
  const v = items[i];
  const st = statusOf(v.stock);
  const go = (n) => setI((i + n + items.length) % items.length);
  return (
    <div className="gal">
      <div className="gal-top">
        <button className="gal-ic" onClick={onClose}>{ICON.x}</button>
        <div className="gal-ttl"><span>Item 895C</span><em>{i+1} of {items.length} photos</em></div>
        <button className="gal-ic" title="Zoom">{ICON.zoom}</button>
      </div>

      <div className="gal-stage">
        <button className="gal-nav l" onClick={()=>go(-1)}>{ICON.chevL}</button>
        <div className="gal-photo"><ImgPH v={v} big/></div>
        <button className="gal-nav r" onClick={()=>go(1)}>{ICON.chev}</button>
      </div>

      <div className="gal-info">
        <div className="gal-head">
          <div className="gal-id">
            <div className="gal-code">{v.code}</div>
            <div className="gal-name">{v.name} · {v.cat}</div>
          </div>
          <div className={"gal-qty s-"+st}>
            <span className="gq">{v.stock}</span><span className="gu">{v.uom}</span>
            <span className="gcap">{statusWord(v.stock)}</span>
          </div>
        </div>
        <div className="gal-chips">
          {attrsOf(v).map((a,k)=><span className="gal-chip" key={k}>{a}</span>)}
        </div>
        <button className="gal-open">Open item {ICON.ext}</button>
      </div>

      <div className="gal-film">
        {items.map((it,k)=>(
          <button className={"gal-thumb"+(k===i?" on":"")} key={it.code} onClick={()=>setI(k)}>
            <ImgPH v={it}/>
            <span className="gal-tcode">{it.code.slice(-4)}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

/* ============ REDESIGN — Cards/Compact toggle + gallery overlay ============ */
function Redesign(){
  const [view, setView] = React.useState('cards');
  const [gal, setGal] = React.useState(null); // null | itemCode
  const openGallery = (code) => {
    const idx = GALLERY.findIndex(g => g.code === code);
    if (idx >= 0) setGal(idx);
  };
  return (
    <Phone>
      <div className="a-bar">
        <button className="a-icon">{ICON.menu}</button>
        <span className="a-title">Item Variant Details</span>
        <button className="a-filt">{ICON.filter}<span className="a-badge">1</span></button>
      </div>
      <div className="a-chiprow">
        <span className="a-chip">Item: 895C <span className="a-cx">{ICON.x}</span></span>
      </div>
      <div className="a-summary">
        <span><b>4</b> variants · <b>1</b> out</span>
        <div className="vtoggle" role="tablist">
          <button className={"vt"+(view==='cards'?' on':'')} onClick={()=>setView('cards')}>{ICON.cards}<span>Cards</span></button>
          <button className={"vt"+(view==='compact'?' on':'')} onClick={()=>setView('compact')}>{ICON.rows}<span>Compact</span></button>
        </div>
      </div>
      {view==='cards' ? (
        <div className="a-list">{VD_DATA.map(v => <ACard v={v} onOpen={openGallery} key={v.code}/>)}</div>
      ) : (
        <React.Fragment>
          <div className="b-head"><span>Variant</span><span>On hand</span></div>
          <div className="b-list">{VD_DATA.map(v => <BRow v={v} onOpen={openGallery} key={v.code}/>)}</div>
        </React.Fragment>
      )}
      {gal !== null && <GalleryView initialIndex={gal} onClose={()=>setGal(null)}/>}
    </Phone>
  );
}

/* standalone artboard so the gallery is visible without interaction */
function GalleryStandalone(){
  return <Phone><GalleryView initialIndex={1} onClose={()=>{}}/></Phone>;
}

Object.assign(window, { Baseline, Redesign, GalleryStandalone, ACard, BRow, GalleryView });
