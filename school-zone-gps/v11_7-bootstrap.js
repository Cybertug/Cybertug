(function(){
  const statusEl=()=>document.getElementById('st');
  function setBootStatus(msg){const e=statusEl();if(e)e.textContent=msg}
  function loadScript(src,timeout=10000){return new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=src;s.async=false;let done=false;const t=setTimeout(()=>{if(done)return;done=true;s.remove();reject(Error('Timeout '+src))},timeout);s.onload=()=>{if(done)return;done=true;clearTimeout(t);resolve()};s.onerror=()=>{if(done)return;done=true;clearTimeout(t);reject(Error('Failed '+src))};document.head.appendChild(s)})}
  async function loadAny(urls,key){let last;for(const u of urls){try{await loadScript(u,8500);if(window[key])return true}catch(e){last=e}}throw last||Error(key+' unavailable')}
  async function local(n){await loadScript(n+'?v=11.7.0',10000)}
  function stableFallback(){window.__SZ_MAP_MODE='stable';window.__requestHeadingPermission=async()=>false;window.__enterNavVisual=()=>{document.body.classList.add('navMode');try{map.setZoom(17)}catch(_){}};window.__exitNavVisual=()=>document.body.classList.remove('navMode');window.__setNavMarker=(lon,lat)=>{try{gpsLayer.clearLayers();L.circleMarker([lat,lon],{radius:9,color:'#fff',weight:3,fillColor:'#0b69ff',fillOpacity:1}).addTo(gpsLayer)}catch(_){}};window.__updateNavCamera=(lat,lon,heading,speed)=>{try{map.setView([lat,lon],(speed||0)>20?16:(speed||0)>8?17:18);window.__setNavMarker(lon,lat,heading||0)}catch(_){}}}
  async function boot(){
    setBootStatus('Loading map…');let vector=false;
    try{await loadAny(['https://cdn.jsdelivr.net/npm/maplibre-gl@5.13.0/dist/maplibre-gl.js','https://unpkg.com/maplibre-gl@5.13.0/dist/maplibre-gl.js'],'maplibregl');await local('v11_2-map.js');vector=true;window.__SZ_MAP_MODE='vector'}
    catch(e){try{await loadAny(['https://unpkg.com/leaflet@1.9.4/dist/leaflet.js','https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js'],'L');stableFallback()}catch(_){setBootStatus('Map failed to load.');return}}
    try{
      await loadAny(['https://unpkg.com/@turf/turf@6/turf.min.js','https://cdn.jsdelivr.net/npm/@turf/turf@6/turf.min.js'],'turf');
      await local('v10-core.js');
      await local('v11_4-search.js');
      await local('v11_5-search-patch.js');
      await local('v11_7-routing.js');
      await local('v11_1-app.js');
      await local('v11_7-patch.js');
      setBootStatus(vector?'Map ready · origin-zone escape + nearest safe-stop fallback enabled.':'Stable map ready · origin-zone escape + nearest safe-stop fallback enabled.');
      document.body.classList.add('appReady');
    }catch(e){console.error(e);setBootStatus('App initialization failed: '+e.message)}
  }
  boot();
})();
