/* User Area revamp — interactive prototype + standalone wrappers for artboards. */

const UA_LABELS = { drawer:'Menu', userarea:'Account', profile:'My Profile',
  session:'Session Defaults', about:'System Information', theme:'Theme' };

function useThemeState(){
  const [theme, setTheme] = React.useState(() => {
    try { const s = JSON.parse(localStorage.getItem('ua-proto-theme')||'null');
      if (s && s.mode && s.accent && s.dens) return s; } catch {}
    return { mode:'system', accent:'blue', dens:'comfortable' };
  });
  React.useEffect(()=>{ try{ localStorage.setItem('ua-proto-theme', JSON.stringify(theme)); }catch{} },[theme]);
  return [theme, setTheme];
}

/* ---------- full interactive flow ---------- */
function UAPrototype(){
  const [stack, setStack] = React.useState(['drawer']);
  const [dir, setDir] = React.useState('fwd');
  const [theme, setTheme] = useThemeState();
  const [confirm, setConfirm] = React.useState(false);
  const [toast, setToast] = React.useState('');

  const push = (s) => { setDir('fwd'); setStack(st => [...st, s]); };
  const back = () => { setDir('back'); setStack(st => st.length>1 ? st.slice(0,-1) : st); };
  const cur = stack[stack.length-1];
  const resolved = resolveTheme(theme.mode);

  React.useEffect(()=>{ if(!toast) return; const t=setTimeout(()=>setToast(''),1700); return ()=>clearTimeout(t); },[toast]);

  const doLogout = () => { setConfirm(false); setStack(['drawer']); setDir('back'); setToast('Signed out'); };

  let screen;
  if (cur==='drawer')        screen = <RUADrawer user={UA_USER} onAccount={()=>push('userarea')}/>;
  else if (cur==='userarea') screen = <RUAUserArea user={UA_USER} theme={theme} onBack={back} onNav={push} onLogout={()=>setConfirm(true)}/>;
  else if (cur==='profile')  screen = <RUAProfile user={UA_USER} onBack={back}/>;
  else if (cur==='session')  screen = <RUASession onBack={back}/>;
  else if (cur==='about')    screen = <RUAAbout onBack={back}/>;
  else if (cur==='theme')    screen = <RUATheme value={theme} onChange={setTheme} onBack={back}/>;

  return (
    <UAPhone theme={resolved} accent={theme.accent} dens={DENS_MAP[theme.dens]}>
      <div style={{flex:1,position:'relative',overflow:'hidden'}}>
        <div key={cur+stack.length} className={"ua-nav " + (dir==='fwd'?'ua-anim-fwd':'ua-anim-back')}>
          {screen}
        </div>

        {/* logout confirm */}
        {confirm && (
          <div style={{position:'absolute',inset:0,zIndex:30,display:'flex',alignItems:'center',justifyContent:'center',
            padding:24,background:'rgba(17,23,29,.5)'}} onClick={()=>setConfirm(false)}>
            <div onClick={e=>e.stopPropagation()} style={{background:'var(--fg)',borderRadius:'var(--r-lg)',
              boxShadow:'var(--shadow-lg)',padding:22,width:'100%',maxWidth:300}}>
              <div style={{display:'flex',gap:12,alignItems:'center',marginBottom:12}}>
                <span style={{width:38,height:38,borderRadius:'50%',flex:'none',display:'flex',alignItems:'center',justifyContent:'center',
                  background:'color-mix(in srgb,var(--red-500) 14%,var(--fg))',color:'var(--red-600)'}}>
                  <span style={{width:20,height:20,display:'flex'}}>{UA_ICON.logout}</span></span>
                <div style={{fontSize:17,fontWeight:700,color:'var(--text)'}}>Log out?</div>
              </div>
              <div style={{fontSize:13.5,color:'var(--text-muted)',lineHeight:1.5}}>You’ll need to sign in again to access your documents.</div>
              <div style={{display:'flex',gap:10,marginTop:20}}>
                <button onClick={()=>setConfirm(false)} style={{flex:1,height:42,borderRadius:'var(--r-md)',border:'1px solid var(--border-strong)',
                  background:'var(--fg)',color:'var(--text)',fontSize:14,fontWeight:600,cursor:'pointer'}}>Cancel</button>
                <button onClick={doLogout} style={{flex:1,height:42,borderRadius:'var(--r-md)',border:'none',
                  background:'var(--red-500)',color:'#fff',fontSize:14,fontWeight:600,cursor:'pointer'}}>Log out</button>
              </div>
            </div>
          </div>
        )}

        {/* toast */}
        {toast && (
          <div style={{position:'absolute',left:0,right:0,bottom:24,display:'flex',justifyContent:'center',zIndex:40,pointerEvents:'none'}}>
            <div style={{background:'var(--gray-900)',color:'#fff',fontSize:13,fontWeight:500,padding:'10px 18px',
              borderRadius:'var(--r-full)',boxShadow:'var(--shadow-md)'}}>{toast}</div>
          </div>
        )}
      </div>
    </UAPhone>
  );
}

/* ---------- standalone wrappers for before/after artboards ---------- */
function RedesignUserArea({ theme }){
  const t = { mode: theme||'light', accent:'blue', dens:'comfortable' };
  return (
    <UAPhone theme={theme||'light'} accent="blue" dens={1}>
      <div style={{flex:1,position:'relative',overflow:'hidden'}}>
        <RUAUserArea user={UA_USER} theme={t} onBack={()=>{}} onNav={()=>{}} onLogout={()=>{}}/>
      </div>
    </UAPhone>
  );
}
function RedesignDrawer(){
  return (
    <UAPhone theme="light" accent="blue" dens={1} statusbar={false}>
      <RUADrawer user={UA_USER} onAccount={()=>{}}/>
    </UAPhone>
  );
}
function RedesignProfile(){
  return (
    <UAPhone theme="light" accent="blue" dens={1}>
      <div style={{flex:1,position:'relative',overflow:'hidden'}}><RUAProfile user={UA_USER} onBack={()=>{}}/></div>
    </UAPhone>
  );
}
function RedesignSession(){
  return (
    <UAPhone theme="light" accent="blue" dens={1}>
      <div style={{flex:1,position:'relative',overflow:'hidden'}}><RUASession onBack={()=>{}}/></div>
    </UAPhone>
  );
}
function RedesignAbout(){
  return (
    <UAPhone theme="light" accent="blue" dens={1}>
      <div style={{flex:1,position:'relative',overflow:'hidden'}}><RUAAbout onBack={()=>{}}/></div>
    </UAPhone>
  );
}
/* live Theme screen for the artboard (its own state, applies to its own phone) */
function ThemeDemo({ start }){
  const [theme, setTheme] = React.useState(start || { mode:'light', accent:'purple', dens:'comfortable' });
  const resolved = resolveTheme(theme.mode);
  return (
    <UAPhone theme={resolved} accent={theme.accent} dens={DENS_MAP[theme.dens]}>
      <div style={{flex:1,position:'relative',overflow:'hidden'}}>
        <RUATheme value={theme} onChange={setTheme} onBack={()=>{}}/>
      </div>
    </UAPhone>
  );
}

Object.assign(window, { UAPrototype, RedesignUserArea, RedesignDrawer, RedesignProfile,
  RedesignSession, RedesignAbout, ThemeDemo });
