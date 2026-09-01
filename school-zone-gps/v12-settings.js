/* School Zone GPS v12 - local API key settings.
   Keys are stored in this browser only. They are never committed to GitHub. */
(function(){
  const GH_KEY='schoolZoneGpsGraphHopperKey';
  const ORS_KEY='schoolZoneGpsOrsKey';

  function read(){
    return {
      graphhopper:(localStorage.getItem(GH_KEY)||'').trim(),
      ors:(localStorage.getItem(ORS_KEY)||'').trim()
    };
  }
  function refresh(){
    const k=read();
    window.routingApiKeys=k;
    const e=document.getElementById('apiStatus');
    if(e){
      if(k.graphhopper&&k.ors)e.textContent='GraphHopper + ORS ready';
      else if(k.graphhopper)e.textContent='GraphHopper ready';
      else if(k.ors)e.textContent='ORS ready';
      else e.textContent='Routing API setup required';
      e.classList.toggle('warn',!k.graphhopper&&!k.ors);
    }
    return k;
  }
  window.getRoutingApiKeys=refresh;
  window.showApiSettings=function(){
    const k=read();
    const gh=document.getElementById('ghKey'),ors=document.getElementById('orsKey');
    if(gh)gh.value=k.graphhopper;
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
    const gh=(document.getElementById('ghKey').value||'').trim();
    const ors=(document.getElementById('orsKey').value||'').trim();
    if(gh)localStorage.setItem(GH_KEY,gh); else localStorage.removeItem(GH_KEY);
    if(ors)localStorage.setItem(ORS_KEY,ors); else localStorage.removeItem(ORS_KEY);
    refresh();
    hideApiSettings();
    const st=document.getElementById('st');
    if(st){
      st.className='status ok';
      st.textContent=gh
        ?'GraphHopper routing key saved on this browser.'
        :ors
          ?'OpenRouteService routing key saved on this browser.'
          :'Routing API keys cleared.';
    }
  };
  document.getElementById('apiClear').onclick=()=>{
    localStorage.removeItem(GH_KEY);
    localStorage.removeItem(ORS_KEY);
    document.getElementById('ghKey').value='';
    document.getElementById('orsKey').value='';
    refresh();
  };
  document.getElementById('apiModal').onclick=e=>{
    if(e.target.id==='apiModal')hideApiSettings();
  };

  refresh();
})();
