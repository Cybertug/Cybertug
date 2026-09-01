/* School Zone GPS v13 - OpenRouteService-only browser settings.
   The ORS key remains only in this browser localStorage. Nothing is committed to GitHub. */
(function(){
  const ORS_KEY='schoolZoneGpsOrsKey';
  const OLD_GH_KEY='schoolZoneGpsGraphHopperKey';

  /* v13 intentionally ignores/removes the stale GraphHopper credential that caused 401 errors in v12. */
  try{localStorage.removeItem(OLD_GH_KEY)}catch(_){}

  function read(){
    return{graphhopper:'',ors:(localStorage.getItem(ORS_KEY)||'').trim()};
  }
  function refresh(){
    const k=read();
    window.routingApiKeys=k;
    const e=document.getElementById('apiStatus');
    if(e){
      e.textContent=k.ors?'OpenRouteService ready':'ORS API setup required';
      e.classList.toggle('warn',!k.ors);
    }
    return k;
  }
  window.getRoutingApiKeys=refresh;
  window.showApiSettings=function(){
    const k=read();
    const ors=document.getElementById('orsKey');
    if(ors)ors.value=k.ors;
    document.getElementById('apiModal').style.display='flex';
  };
  window.hideApiSettings=function(){
    document.getElementById('apiModal').style.display='none';
  };

  document.getElementById('apiSettingsBtn').onclick=showApiSettings;
  document.getElementById('apiClose').onclick=hideApiSettings;
  document.getElementById('apiCancel').onclick=hideApiSettings;
  document.getElementById('apiSave').onclick=()=>{
    const ors=(document.getElementById('orsKey').value||'').trim();
    if(ors)localStorage.setItem(ORS_KEY,ors);else localStorage.removeItem(ORS_KEY);
    refresh();hideApiSettings();
    const st=document.getElementById('st');
    if(st){st.className=ors?'status ok':'status';st.textContent=ors?'OpenRouteService key saved on this browser.':'OpenRouteService key cleared.'}
  };
  document.getElementById('apiClear').onclick=()=>{
    localStorage.removeItem(ORS_KEY);
    document.getElementById('orsKey').value='';
    refresh();
  };
  document.getElementById('apiModal').onclick=e=>{if(e.target.id==='apiModal')hideApiSettings()};
  refresh();
})();