/* User Area revamp — REDESIGNED screens + interactive prototype.
   Screens are presentational; the prototype owns navigation + theme state. */

const ACCENTS = [
  { key:'blue',   name:'Blue' },
  { key:'green',  name:'Green' },
  { key:'purple', name:'Purple' },
  { key:'orange', name:'Orange' },
  { key:'cyan',   name:'Cyan' },
  { key:'pink',   name:'Pink' },
];
const DENS_MAP = { compact:0.9, comfortable:1, large:1.12 };
const resolveTheme = (mode) =>
  mode === 'system'
    ? (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
    : mode;
const themeLabel = (t) => ({ light:'Light', dark:'Dark', system:'System' }[t.mode]) + ' · ' +
  (ACCENTS.find(a=>a.key===t.accent)||{}).name;

/* ---------- redesigned NAV DRAWER (account header → User Area) ---------- */
function RUADrawer({ user, onAccount }){
  const Item = ({ ic, t, active }) => (
    <div className="ua-row" style={{padding:'11px 14px',borderRadius:12,background:active?'color-mix(in srgb,var(--primary) 9%,transparent)':'transparent'}}>
      <span style={{width:24,height:24,color:active?'var(--primary)':'var(--text-muted)',display:'flex'}}>{ic}</span>
      <span style={{flex:1,fontSize:14.5,fontWeight:active?700:500,color:active?'var(--primary)':'var(--text)'}}>{t}</span>
    </div>
  );
  const Group = ({ ic, t }) => (
    <div className="ua-row" style={{padding:'11px 14px'}}>
      <span style={{width:24,height:24,color:'var(--text-muted)',display:'flex'}}>{ic}</span>
      <span style={{flex:1,fontSize:14.5,fontWeight:600,color:'var(--text)'}}>{t}</span>
      <span style={{width:18,height:18,color:'var(--text-subtle)',transform:'rotate(90deg)',display:'flex'}}>{UA_ICON.chev}</span>
    </div>
  );
  return (
    <div style={{height:'100%',display:'flex',flexDirection:'column',background:'var(--fg)'}}>
      {/* Account header — now a clear, tappable entry into the User Area */}
      <button className="ua-id" onClick={onAccount}
        style={{margin:'10px 12px 4px',borderRadius:'var(--r-lg)',width:'auto'}}>
        <span className="ua-avatar">{user.initials}</span>
        <span className="ua-idmain">
          <span className="ua-idname">{user.name}</span>
          <span className="ua-idrole">{user.designation}</span>
          <span style={{fontSize:11.5,fontWeight:600,color:'var(--primary)',display:'inline-flex',alignItems:'center',gap:3,marginTop:2}}>
            Account &amp; settings <span style={{width:13,height:13,display:'flex'}}>{UA_ICON.chev}</span></span>
        </span>
      </button>
      <div style={{height:1,background:'var(--border)',margin:'8px 16px'}}/>
      <div style={{flex:1,overflow:'hidden',padding:'2px 8px',display:'flex',flexDirection:'column',gap:2}}>
        <Item ic={UA_ICON.doc} t="Dashboard" active/>
        <Item ic={UA_ICON.check} t="To Do"/>
        <div style={{height:1,background:'var(--border)',margin:'6px 14px'}}/>
        <Group ic={UA_ICON.building} t="Stock"/>
        <Group ic={UA_ICON.doc} t="Buying"/>
        <Group ic={UA_ICON.sliders} t="Manufacturing"/>
        <Group ic={UA_ICON.search} t="Selling"/>
      </div>
    </div>
  );
}

/* ---------- USER AREA hub ---------- */
function RUAUserArea({ user, theme, onBack, onNav, onLogout }){
  const Row = ({ ic, ric, title, val, to }) => (
    <button className="ua-row" onClick={()=>onNav(to)}>
      <span className="ua-ricon" style={{['--ric']:ric}}>{ic}</span>
      <span className="ua-rmain"><span className="ua-rtitle">{title}</span></span>
      {val && <span className="ua-rval">{val}</span>}
      <span className="ua-rchev">{UA_ICON.chev}</span>
    </button>
  );
  return (
    <div style={{height:'100%',display:'flex',flexDirection:'column'}}>
      <UABar title="Account" onBack={onBack}/>
      <div className="ua-body"><div className="ua-scroll">
        <button className="ua-id" onClick={()=>onNav('profile')}>
          <span className="ua-avatar">{user.initials}</span>
          <span className="ua-idmain">
            <span className="ua-idname">{user.name}</span>
            <span className="ua-idmail">{user.email}</span>
            <span className="ua-idrole">{user.designation} · {user.department}</span>
          </span>
          <span className="ua-rchev">{UA_ICON.chev}</span>
        </button>

        <div className="ua-group">
          <div className="ua-glabel">Preferences</div>
          <div className="ua-card">
            <Row ic={UA_ICON.theme} ric="var(--purple-500)" title="Theme" val={themeLabel(theme)} to="theme"/>
            <Row ic={UA_ICON.sliders} ric="var(--cyan-500)" title="Session Defaults" val="Multimax LLC" to="session"/>
          </div>
        </div>

        <div className="ua-group">
          <div className="ua-glabel">Support</div>
          <div className="ua-card">
            <Row ic={UA_ICON.info} ric="var(--blue-500)" title="System Information" val="v3.4.1" to="about"/>
          </div>
        </div>

        <button className="ua-logout" onClick={onLogout}>{UA_ICON.logout} Log out</button>
        <div className="ua-foot">Signed in as {user.email}<br/>Multimax v3.4.1 · build 241</div>
      </div></div>
    </div>
  );
}

/* ---------- MY PROFILE ---------- */
function RUAProfile({ user, onBack }){
  const KV = ({ ic, k, v, edit }) => (
    <div className="ua-kv">
      <span className="ua-kv-ic">{ic}</span>
      <span className="ua-kv-main"><span className="ua-kv-k">{k}</span><span className={"ua-kv-v"+(v?'':' muted')}>{v||'—'}</span></span>
      {edit && <button className="ua-kv-edit">{UA_ICON.edit}</button>}
    </div>
  );
  return (
    <div style={{height:'100%',display:'flex',flexDirection:'column'}}>
      <UABar title="My Profile" onBack={onBack}/>
      <div className="ua-body"><div className="ua-scroll">
        <div className="ua-hero">
          <div className="ua-hero-av">{user.initials}</div>
          <div className="ua-hero-name">{user.name}</div>
          <div className="ua-hero-mail">{user.email}</div>
          <div className="ua-hero-role">{user.designation} · {user.department}</div>
        </div>

        <div className="ua-group">
          <div className="ua-glabel">General information</div>
          <div className="ua-card">
            <KV ic={UA_ICON.badge}    k="Employee ID" v={user.employeeId}/>
            <KV ic={UA_ICON.dept}     k="Department"  v={user.department}/>
            <KV ic={UA_ICON.person}   k="Designation" v={user.designation}/>
            <KV ic={UA_ICON.phone}    k="Mobile"      v={user.mobile} edit/>
          </div>
        </div>

        <div className="ua-group">
          <div className="ua-glabel">Roles · {user.roles.length}</div>
          <div className="ua-card"><div className="ua-chips">
            {user.roles.map((r,i)=><span key={i} className="ua-chip">{UA_ICON.shield}{r}</span>)}
          </div></div>
        </div>

        <div className="ua-group">
          <div className="ua-glabel">Security</div>
          <div className="ua-card">
            <button className="ua-row">
              <span className="ua-ricon" style={{['--ric']:'var(--gray-600)'}}>{UA_ICON.lock}</span>
              <span className="ua-rmain"><span className="ua-rtitle">Change password</span></span>
              <span className="ua-rchev">{UA_ICON.chev}</span>
            </button>
          </div>
        </div>
        <div style={{height:8}}/>
      </div></div>
    </div>
  );
}

/* ---------- SESSION DEFAULTS (full screen) ---------- */
function RUASession({ onBack }){
  const [auto, setAuto] = React.useState(true);
  const [delay, setDelay] = React.useState(2);
  return (
    <div style={{height:'100%',display:'flex',flexDirection:'column'}}>
      <UABar title="Session Defaults" onBack={onBack}/>
      <div className="ua-body"><div className="ua-scroll">
        <div className="ua-group" style={{marginTop:6}}>
          <div className="ua-glabel">Session</div>
          <div className="ua-card">
            <div className="ua-field">
              <span className="ua-flabel">Company</span>
              <div className="ua-control">{UA_ICON.building}<span>Multimax LLC</span>
                <span className="caret" style={{width:16,height:16,color:'var(--text-subtle)',transform:'rotate(90deg)',display:'flex'}}>{UA_ICON.chev}</span></div>
              <span className="ua-fhelp">Applied to every new document this session.</span>
            </div>
          </div>
        </div>

        <div className="ua-group">
          <div className="ua-glabel">Automation</div>
          <div className="ua-card">
            <div className="ua-switchrow">
              <span className="ua-rmain"><span className="ua-rtitle">Auto-submit valid items</span>
                <span className="ua-rsub">Add item automatically when validation passes</span></span>
              <label className="ua-switch"><input type="checkbox" checked={auto} onChange={e=>setAuto(e.target.checked)}/>
                <span className="track"></span><span className="thumb"></span></label>
            </div>
            {auto && (
              <div className="ua-sliderrow">
                <div className="ua-sliderhead"><span>Auto-submit delay</span><b>{delay}s</b></div>
                <input type="range" min="1" max="10" value={delay} className="ua-slider"
                  onChange={e=>setDelay(+e.target.value)}/>
              </div>
            )}
          </div>
        </div>

        <div className="ua-group">
          <div className="ua-glabel">Troubleshooting</div>
          <div className="ua-card">
            <button className="ua-row">
              <span className="ua-ricon" style={{['--ric']:'var(--orange-500)'}}>{UA_ICON.synclock}</span>
              <span className="ua-rmain"><span className="ua-rtitle">Reload permissions</span>
                <span className="ua-rsub">Clear cache &amp; re-fetch access rights</span></span>
              <span className="ua-rchev">{UA_ICON.chev}</span>
            </button>
          </div>
        </div>
        <div style={{height:8}}/>
      </div></div>
      <div className="ua-savebar"><button className="ua-save">{UA_ICON.check} Save settings</button></div>
    </div>
  );
}

/* ---------- ABOUT / SYSTEM INFORMATION ---------- */
function RUAAbout({ onBack }){
  const health = [
    { n:'ERPNext API', t:'REST · /api/method', ok:true, d:'Connected', lat:'142 ms' },
    { n:'Database', t:'MariaDB', ok:true, d:'Connected', lat:'38 ms' },
    { n:'Print Service', t:'PDF generator', ok:false, d:'Offline', lat:null },
    { n:'Scan Bridge', t:'DataWedge', ok:true, d:'Connected', lat:'9 ms' },
  ];
  return (
    <div style={{height:'100%',display:'flex',flexDirection:'column'}}>
      <UABar title="System Information" onBack={onBack}
        action={<button className="ua-baricon">{UA_ICON.refresh}</button>}/>
      <div className="ua-body"><div className="ua-scroll">
        <div className="ua-about-head">
          <div className="ua-logo">M</div>
          <div className="ua-appname">Multimax</div>
        </div>
        <div className="ua-group" style={{marginTop:14}}>
          <div className="ua-card ua-vcard">
            <div className="ua-vcell"><span className="ua-vk">Version</span><span className="ua-vv">3.4.1</span></div>
            <div className="ua-vcell"><span className="ua-vk">Build</span><span className="ua-vv">241</span></div>
            <div className="ua-vcell"><span className="ua-vk">Channel</span><span className="ua-vv" style={{fontSize:14}}>Stable</span></div>
          </div>
        </div>
        <div className="ua-group">
          <div className="ua-glabel">System health</div>
          <div className="ua-card">
            {health.map((h,i)=>(
              <div key={i} className="ua-health">
                <span className={"ua-hstat "+(h.ok?'ok':'err')}>{h.ok?UA_ICON.check:UA_ICON.alert}</span>
                <span className="ua-hmain"><span className="ua-hname">{h.n}</span><span className="ua-htype">{h.t}</span></span>
                <span className="ua-hright"><span className={"ua-hdetail "+(h.ok?'ok':'err')}>{h.d}</span>
                  {h.lat && <span className="ua-hlat">{h.lat}</span>}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="ua-foot" style={{marginTop:24}}>© 2026 Multimax · Powered by DDMCO</div>
      </div></div>
    </div>
  );
}

/* ---------- THEME (new) — controlled ---------- */
function RUATheme({ value, onChange, onBack }){
  const set = (patch) => onChange({ ...value, ...patch });
  const modes = [
    { key:'light',  label:'Light',  cols:['#ffffff','#f4f5f6'] },
    { key:'dark',   label:'Dark',   cols:['#1f262c','#15191d'] },
    { key:'system', label:'System', cols:['#ffffff','#15191d'] },
  ];
  return (
    <div style={{height:'100%',display:'flex',flexDirection:'column'}}>
      <UABar title="Theme" onBack={onBack}/>
      <div className="ua-body"><div className="ua-scroll">
        {/* live preview */}
        <div className="ua-group" style={{marginTop:6}}>
          <div className="ua-glabel">Preview</div>
          <div className="ua-preview"><div className="pv-card">
            <div className="pv-top">
              <span className="pv-dot">{UA_ICON.doc}</span>
              <div><div className="pv-h">Stock Entry · SE-2026</div><div className="pv-s">12 items · In stock</div></div>
            </div>
            <div className="pv-btns"><span className="pv-btn out">Cancel</span><span className="pv-btn fill">Submit</span></div>
          </div></div>
        </div>

        {/* appearance */}
        <div className="ua-group">
          <div className="ua-glabel">Appearance</div>
          <div className="ua-seg">
            {modes.map(m=>(
              <button key={m.key} className={"ua-segbtn"+(value.mode===m.key?' on':'')} onClick={()=>set({mode:m.key})}>
                <span className="swatch">{m.cols.map((c,i)=><i key={i} style={{background:c}}/>)}</span>
                {m.label}
              </button>
            ))}
          </div>
        </div>

        {/* accent */}
        <div className="ua-group">
          <div className="ua-glabel">Accent color</div>
          <div className="ua-card"><div className="ua-accents">
            {ACCENTS.map(a=>(
              <button key={a.key} className={"ua-acc"+(value.accent===a.key?' on':'')} onClick={()=>set({accent:a.key})}
                style={{['--swatch']:`var(--${a.key}-500)`}} title={a.name}>
                <span className="ring"></span>
                <span className="fill">{value.accent===a.key && UA_ICON.check}</span>
              </button>
            ))}
          </div></div>
        </div>

        {/* density */}
        <div className="ua-group">
          <div className="ua-glabel">Text size</div>
          <div className="ua-segrow">
            {['compact','comfortable','large'].map(d=>(
              <button key={d} className={"ua-segbtn"+(value.dens===d?' on':'')} onClick={()=>set({dens:d})}
                style={{textTransform:'capitalize'}}>{d}</button>
            ))}
          </div>
        </div>
        <div style={{height:8}}/>
      </div></div>
    </div>
  );
}

Object.assign(window, {
  ACCENTS, DENS_MAP, resolveTheme, themeLabel,
  RUADrawer, RUAUserArea, RUAProfile, RUASession, RUAAbout, RUATheme,
});
