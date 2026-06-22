/* User Area revamp — BASELINE recreations of the CURRENT screens (the "before"). */

/* ---- 1. Current Nav Drawer → User Area (the user menu) ---- */
function BaselineUserMenu(){
  const items = [
    { ic: UA_ICON.person,  t:'My Profile' },
    { ic: UA_ICON.sliders, t:'Session Defaults' },
    { ic: UA_ICON.info,    t:'About' },
  ];
  return (
    <div style={{height:'100%',display:'flex',flexDirection:'column',background:'#fff'}}>
      {/* UserAccountsDrawerHeader */}
      <div style={{background:'#2490ef',padding:'18px 16px 14px',color:'#fff'}}>
        <div style={{display:'flex',justifyContent:'space-between',alignItems:'flex-start'}}>
          <div style={{width:64,height:64,borderRadius:'50%',background:'#fff',display:'flex',
            alignItems:'center',justifyContent:'center',fontSize:32,fontWeight:700,color:'#2490ef'}}>A</div>
          <button style={{all:'unset',cursor:'pointer',color:'#fff',transform:'rotate(180deg)'}}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="m6 9 6 6 6-6"/></svg>
          </button>
        </div>
        <div style={{marginTop:12,fontSize:18,fontWeight:700}}>{UA_USER.name}</div>
        <div style={{fontSize:12,color:'rgba(255,255,255,.72)',marginTop:2}}>{UA_USER.email}</div>
        <div style={{fontSize:11,color:'rgba(255,255,255,.55)',marginTop:1}}>{UA_USER.designation} · {UA_USER.department}</div>
        <div style={{fontSize:11,color:'rgba(255,255,255,.55)',marginTop:1}}>Employee: {UA_USER.employeeId}</div>
      </div>
      <div style={{flex:1,overflow:'hidden',padding:'12px 0'}}>
        {items.map((it,i)=>(
          <div key={i} style={{display:'flex',alignItems:'center',gap:16,padding:'13px 24px',color:'#525c66'}}>
            <span style={{width:24,height:24,color:'#74808b'}}>{it.ic}</span>
            <span style={{fontSize:14,fontWeight:500,color:'#323a45'}}>{it.t}</span>
          </div>
        ))}
        <div style={{height:1,background:'#ebeef0',margin:'8px 16px'}}/>
        <div style={{display:'flex',alignItems:'center',gap:16,padding:'13px 24px'}}>
          <span style={{width:22,height:22,color:'#f09494'}}>{UA_ICON.logout}</span>
          <span style={{fontSize:14,fontWeight:600,color:'#e03636'}}>Logout</span>
        </div>
      </div>
    </div>
  );
}

/* ---- 2. Current My Profile ---- */
function BaselineProfile(){
  return (
    <div className="bl" style={{height:'100%',display:'flex',flexDirection:'column',background:'#f4f5f6'}}>
      <div className="bl-appbar">
        <span className="t">My Profile</span>
        <button className="mi">{UA_ICON.refresh}</button>
      </div>
      <div style={{flex:1,overflow:'hidden',padding:'20px 16px'}}>
        <div style={{display:'flex',flexDirection:'column',alignItems:'center'}}>
          <div style={{width:112,height:112,borderRadius:'50%',border:'2px solid #2490ef',padding:3,
            display:'flex',alignItems:'center',justifyContent:'center'}}>
            <div style={{width:'100%',height:'100%',borderRadius:'50%',background:'rgba(36,144,239,.1)',
              display:'flex',alignItems:'center',justifyContent:'center',fontSize:42,fontWeight:700,color:'#2490ef'}}>A</div>
          </div>
          <div style={{fontSize:22,fontWeight:700,color:'#1f272e',marginTop:14}}>{UA_USER.name}</div>
          <div style={{fontSize:13,color:'#98a1a9',marginTop:4}}>{UA_USER.email}</div>
          <div style={{fontSize:13,color:'#98a1a9',fontWeight:500,marginTop:4}}>{UA_USER.designation} · {UA_USER.department}</div>
        </div>
        <div style={{height:28}}/>
        <div className="bl-secttl">General Information</div>
        <div style={{background:'#fff',border:'1px solid #ebeef0',borderRadius:12,padding:16}}>
          {[['Email',UA_USER.email,UA_ICON.mail],['Designation',UA_USER.designation,UA_ICON.badge],
            ['Department',UA_USER.department,UA_ICON.dept]].map((r,i)=>(
            <div key={i}>
              {i>0 && <div style={{height:1,background:'#ebeef0',margin:'12px 0'}}/>}
              <div style={{display:'flex',alignItems:'center',gap:12}}>
                <span style={{width:20,height:20,color:'#98a1a9'}}>{r[2]}</span>
                <div>
                  <div style={{fontSize:12,color:'#98a1a9'}}>{r[0]}</div>
                  <div style={{fontSize:15,fontWeight:500,color:'#323a45',marginTop:3}}>{r[1]}</div>
                </div>
              </div>
            </div>
          ))}
          <div style={{height:1,background:'#ebeef0',margin:'12px 0'}}/>
          <div style={{display:'flex',alignItems:'center',gap:12}}>
            <span style={{width:20,height:20,color:'#98a1a9'}}>{UA_ICON.phone}</span>
            <div style={{flex:1}}>
              <div style={{fontSize:12,color:'#98a1a9'}}>Mobile</div>
              <div style={{fontSize:15,fontWeight:500,color:'#323a45',marginTop:3}}>{UA_USER.mobile}</div>
            </div>
            <span style={{width:20,height:20,color:'#2490ef'}}>{UA_ICON.edit}</span>
          </div>
        </div>
        <div style={{height:28}}/>
        <div className="bl-secttl">Assigned Roles</div>
        <div style={{background:'#fff',border:'1px solid #ebeef0',borderRadius:12,padding:16,
          display:'flex',flexWrap:'wrap',gap:8}}>
          {UA_USER.roles.slice(0,4).map((r,i)=>(
            <span key={i} style={{display:'inline-flex',alignItems:'center',gap:5,fontSize:13,fontWeight:500,
              color:'#1f75c9',background:'rgba(36,144,239,.06)',border:'1px solid rgba(36,144,239,.25)',
              borderRadius:20,padding:'5px 11px'}}>
              <span style={{width:14,height:14,color:'#2490ef'}}>{UA_ICON.shield}</span>{r}</span>
          ))}
        </div>
        <div style={{height:28}}/>
        <div className="bl-secttl">Account Settings</div>
        <div style={{background:'#fff',border:'1px solid #ebeef0',borderRadius:12,overflow:'hidden'}}>
          <div style={{display:'flex',alignItems:'center',gap:14,padding:'15px 16px'}}>
            <span style={{width:22,height:22,color:'#74808b'}}>{UA_ICON.lock}</span>
            <span style={{flex:1,fontSize:15,color:'#323a45'}}>Change Password</span>
            <span style={{width:18,height:18,color:'#bcc4cb'}}>{UA_ICON.chev}</span>
          </div>
          <div style={{height:1,background:'#ebeef0',margin:'0 16px'}}/>
          <div style={{display:'flex',alignItems:'center',gap:14,padding:'15px 16px'}}>
            <span style={{width:22,height:22,color:'#e03636'}}>{UA_ICON.logout}</span>
            <span style={{flex:1,fontSize:15,fontWeight:500,color:'#e03636'}}>Logout</span>
            <span style={{width:18,height:18,color:'#e03636'}}>{UA_ICON.chev}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---- 3. Current Session Defaults (bottom sheet) ---- */
function BaselineSession(){
  return (
    <div style={{height:'100%',position:'relative',background:'#f4f5f6',overflow:'hidden'}}>
      {/* dim scrim suggesting the sheet floats over a screen */}
      <div style={{position:'absolute',inset:0,background:'rgba(17,23,29,.45)'}}/>
      <div style={{position:'absolute',left:0,right:0,bottom:0,background:'#fff',
        borderRadius:'20px 20px 0 0',padding:24,maxHeight:'88%',overflow:'hidden'}}>
        <div style={{display:'flex',alignItems:'center',justifyContent:'space-between'}}>
          <div style={{fontSize:20,fontWeight:600,color:'#1f272e'}}>Settings &amp; Defaults</div>
          <span style={{width:24,height:24,color:'#74808b'}}>{UA_ICON.close}</span>
        </div>
        <div style={{height:1,background:'#ebeef0',margin:'14px 0 18px'}}/>
        <div style={{fontSize:14,fontWeight:700,color:'#2490ef'}}>Session Defaults</div>
        <div style={{marginTop:12,height:52,border:'1px solid #bcc4cb',borderRadius:4,display:'flex',
          alignItems:'center',gap:10,padding:'0 14px',color:'#323a45'}}>
          <span style={{width:18,height:18,color:'#74808b'}}>{UA_ICON.building}</span>
          <span style={{fontSize:13,color:'#98a1a9'}}>Company</span>
          <span style={{marginLeft:'auto',fontSize:15,fontWeight:500}}>Multimax LLC</span>
          <span style={{width:16,height:16,color:'#74808b',transform:'rotate(90deg)'}}>{UA_ICON.chev}</span>
        </div>
        <div style={{height:22}}/>
        <div style={{fontSize:14,fontWeight:700,color:'#2490ef'}}>Automation</div>
        <div style={{display:'flex',alignItems:'center',marginTop:8}}>
          <div style={{flex:1}}>
            <div style={{fontSize:15,color:'#323a45'}}>Auto-Submit Valid Items</div>
            <div style={{fontSize:12,color:'#98a1a9',marginTop:2}}>Automatically add item when validation passes</div>
          </div>
          <div style={{width:44,height:26,borderRadius:13,background:'#2490ef',position:'relative'}}>
            <div style={{position:'absolute',top:3,left:21,width:20,height:20,borderRadius:'50%',background:'#fff'}}/>
          </div>
        </div>
        <div style={{fontSize:13,color:'#525c66',marginTop:14}}>Auto-Submit Delay: 2s</div>
        <input type="range" min="1" max="10" defaultValue="2" className="ua-slider" style={{marginTop:10,accentColor:'#2490ef'}}/>
        <div style={{height:22}}/>
        <div style={{fontSize:14,fontWeight:700,color:'#2490ef'}}>Troubleshooting</div>
        <div style={{display:'flex',alignItems:'center',gap:12,marginTop:10}}>
          <div style={{width:40,height:40,borderRadius:'50%',background:'#fef0e3',display:'flex',
            alignItems:'center',justifyContent:'center',color:'#ce6e10'}}>
            <span style={{width:20,height:20}}>{UA_ICON.synclock}</span></div>
          <div>
            <div style={{fontSize:15,color:'#323a45'}}>Reload Permissions</div>
            <div style={{fontSize:12,color:'#98a1a9',marginTop:2}}>Clear cache and re-fetch access rights</div>
          </div>
        </div>
        <div style={{marginTop:22,height:50,borderRadius:6,background:'#2490ef',color:'#fff',display:'flex',
          alignItems:'center',justifyContent:'center',fontSize:15,fontWeight:600}}>Save Settings</div>
      </div>
    </div>
  );
}

/* ---- 4. Current About / System Information ---- */
function BaselineAbout(){
  const health = [
    { n:'ERPNext API', t:'REST · /api/method', ok:true, d:'Connected', lat:'142 ms' },
    { n:'Database', t:'MariaDB', ok:true, d:'Connected', lat:'38 ms' },
    { n:'Print Service', t:'PDF generator', ok:false, d:'Offline', lat:null },
    { n:'Scan Bridge', t:'DataWedge', ok:true, d:'Connected', lat:'9 ms' },
  ];
  return (
    <div className="bl" style={{height:'100%',display:'flex',flexDirection:'column',background:'#f4f5f6'}}>
      <div className="bl-appbar"><span className="t">System Information</span></div>
      <div style={{flex:1,overflow:'hidden',padding:'24px 24px'}}>
        <div style={{display:'flex',flexDirection:'column',alignItems:'center',gap:16}}>
          <div style={{width:80,height:80,borderRadius:'50%',overflow:'hidden',boxShadow:'0 4px 10px rgba(0,0,0,.12)',
            background:'repeating-linear-gradient(45deg,#dbeafe 0 8px,#eff6ff 8px 16px)',display:'flex',
            alignItems:'center',justifyContent:'center',fontSize:11,fontFamily:'monospace',color:'#60a5fa'}}>logo</div>
          <div style={{fontSize:22,fontWeight:700,color:'#2490ef'}}>Multimax</div>
        </div>
        <div style={{height:32}}/>
        <div style={{background:'#fff',border:'1px solid #ebeef0',borderRadius:12,display:'flex',padding:'16px 0'}}>
          {[['Version','3.4.1'],['Build','241']].map((v,i)=>(
            <div key={i} style={{flex:1,textAlign:'center',borderLeft:i?'1px solid #d8dee3':'none'}}>
              <div style={{fontSize:12,color:'#74808b'}}>{v[0]}</div>
              <div style={{fontSize:16,fontWeight:700,color:'#1f272e',marginTop:4}}>{v[1]}</div>
            </div>
          ))}
        </div>
        <div style={{height:24}}/>
        <div className="bl-secttl" style={{fontSize:15}}>System Health</div>
        <div style={{background:'#fff',border:'1px solid #ebeef0',borderRadius:12,overflow:'hidden'}}>
          {health.map((h,i)=>(
            <div key={i}>
              {i>0 && <div style={{height:1,background:'#ebeef0',marginLeft:56}}/>}
              <div style={{display:'flex',alignItems:'center',gap:12,padding:'13px 16px'}}>
                <div style={{width:32,height:32,borderRadius:'50%',display:'flex',alignItems:'center',justifyContent:'center',
                  background:h.ok?'#e8f6ee':'#fdeaea',color:h.ok?'#2e8049':'#c42b2b'}}>
                  <span style={{width:18,height:18}}>{h.ok?UA_ICON.check:UA_ICON.alert}</span></div>
                <div style={{flex:1}}>
                  <div style={{fontSize:14,fontWeight:600,color:'#323a45'}}>{h.n}</div>
                  <div style={{fontSize:12,color:'#98a1a9',marginTop:1}}>{h.t}</div>
                </div>
                <div style={{textAlign:'right'}}>
                  <div style={{fontSize:12,fontWeight:500,color:h.ok?'#2e8049':'#c42b2b'}}>{h.d}</div>
                  {h.lat && <div style={{fontSize:10,color:'#98a1a9'}}>{h.lat}</div>}
                </div>
              </div>
            </div>
          ))}
        </div>
        <div style={{height:36}}/>
        <div style={{textAlign:'center',fontSize:12,color:'#bcc4cb',lineHeight:1.5}}>© 2026 Multimax<br/>Powered by DDMCO</div>
      </div>
    </div>
  );
}

Object.assign(window, { BaselineUserMenu, BaselineProfile, BaselineSession, BaselineAbout });
