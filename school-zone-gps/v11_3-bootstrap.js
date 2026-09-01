(function(){
  const statusEl=()=>document.getElementById('st');
  function setBootStatus(msg){const e=statusEl();if(e)e.textContent=msg}
  function loadScript(src,timeout=9000){
    return new Promise((resolve,reject)=>{
      const s=document.createElement('script');s.src=src;s.async=false;
      let done=false;
      const t=setTimeout(()=>{if(done)return;done=true;s.remove();reject(new Error('Timeout loading '+src))},timeout);
      s.onload=()=>{if(done)return;done=true;clearTimeout(t);resolve()};
      s.onerror=()=>{if(done)return;done=true;clearTimeout(t);reject(new Error('Failed loading '+src))};
      document.head.appendChild(s);
    });
  }
  async function loadMapLibre(){
    for(const u of ['https://cdn.jsdelivr.net/npm/maplibre-gl@5.13.0/dist/maplibre-gl.js','https://unpkg.com/maplibre-gl@5.13.0/dist/maplibre-gl.js']){
      try{await loadScript(u,8500);if(window.maplibregl)return true}catch(_){}
    }
    throw Error('MapLibre unavailable');
  }
  async function loadLeaflet(){
    for(const u of ['https://unpkg.com/leaflet@1.9.4/dist/leaflet.js','https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js']){
      try{await loadScript(u,8000);if(window.L)return true}catch(_){}
    }
    throw Error('Leaflet unavailable');
  }
  async function loadTurf(){
    for(const u of ['https://unpkg.com/@turf/turf@6/turf.min.js','https://cdn.jsdelivr.net/npm/@turf/turf@6/turf.min.js']){
      try{await loadScript(u,8000);if(window.turf)return true}catch(_){}
    }
    throw Error('Turf unavailable');
  }
  async function local(name){await loadScript(name+'?v=11.3.0',10000)}
  function stableFallback(){
    window.__SZ_MAP_MODE='stable';
    window.__requestHeadingPermission=async()=>false;
    window.__enterNavVisual=()=>{document.body.classList.add('navMode');try{map.setZoom(17)}catch(_){}};
    window.__exitNavVisual=()=>document.body.classList.remove('navMode');
    window.__setNavMarker=(lon,lat)=>{try{gpsLayer.clearLayers();L.circleMarker([lat,lon],{radius:9,color:'#fff',weight:3,fillColor:'#1565ff',fillOpacity:1}).addTo(gpsLayer)}catch(_){}};
    window.__updateNavCamera=(lat,lon,heading,speed)=>{try{const z=(speed||0)>20?16:(speed||0)>8?17:18;map.setView([lat,lon],z);window.__setNavMarker(lon,lat,heading||0)}catch(_){}};
  }
  async function boot(){
    setBootStatus('Loading map…');
    let vector=false;
    try{
      await loadMapLibre();await local('v11_2-map.js');vector=true;window.__SZ_MAP_MODE='vector';
    }catch(e){
      console.warn('Vector engine unavailable',e);
      try{await loadLeaflet();stableFallback()}catch(_){setBootStatus('Map failed to load. Reload the page and check your connection.');return}
    }
    try{
      await loadTurf();
      await local('v10-core.js');
      await local('v11_2-search.js');
      await local('v11_3-routing.js');
      await local('v11_1-app.js');
      setBootStatus(vector?'Map ready. Fast routing fallback enabled.':'Stable map ready. Fast routing fallback enabled.');
      document.body.classList.add('appReady');
    }catch(e){
      console.error(e);setBootStatus('App initialization failed: '+e.message);
    }
  }
  boot();
})();
