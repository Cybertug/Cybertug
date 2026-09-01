/* School Zone GPS v12 app controller */
let NAV_DEST=null;

function restrictedBBox(r,padKm=1.2){return routeBox(r,padKm)}
async function overpassRestricted(r){
  if(!$('restricted').checked)return[];
  const b=restrictedBBox(r),q=`[out:json][timeout:8];(nwr["amenity"~"^(police|courthouse|prison|university|college)$"](${b.ymin},${b.xmin},${b.ymax},${b.xmax});nwr["aeroway"="terminal"](${b.ymin},${b.xmin},${b.ymax},${b.xmax}););out center tags;`;
  const body='data='+encodeURIComponent(q),eps=['https://overpass.kumi.systems/api/interpreter','https://overpass-api.de/api/interpreter'];
  let data=null;
  for(const ep of eps){
    try{
      data=await j(ep,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},body},9000);
      break;
    }catch(_){}
  }
  if(!data)return[];
  return(data.elements||[]).map(e=>{
    const lat=e.lat??e.center?.lat,lon=e.lon??e.center?.lon,t=e.tags||{};
    if(lat==null||lon==null)return null;
    return{name:t.name||(t.amenity||t.aeroway||'restricted'),lat,lon,kind:t.amenity||t.aeroway||'restricted'};
  }).filter(Boolean);
}
function restrictedLabel(k){
  return({police:'Police facility',courthouse:'Courthouse',prison:'Jail / prison',university:'University',college:'College',terminal:'Airport terminal'})[k]||'Potential restricted location';
}
function drawRestricted(list){
  restrictedLayer.clearLayers();
  for(const p of list){
    L.circleMarker([p.lat,p.lon],{radius:5,color:'#fff',weight:2,fillColor:'#8b1e1e',fillOpacity:1})
      .bindPopup('<b>'+p.name+'</b><br>'+restrictedLabel(p.kind)+'<br><small>Potential firearm-restricted location. No distance buffer applied; verify current law and site rules.</small>')
      .addTo(restrictedLayer);
  }
}
function destinationWarning(dest,list){
  let nearest=null,dist=Infinity;
  for(const p of list){
    const d=turf.distance(turf.point([dest.lon,dest.lat]),turf.point([p.lon,p.lat]),{units:'kilometers'})*1000;
    if(d<dist){dist=d;nearest=p}
  }
  return nearest&&dist<180
    ?'Destination is near '+nearest.name+' ('+restrictedLabel(nearest.kind)+'). Verify firearm restrictions before entering.'
    :'';
}
async function loadRestrictedAsync(r,dest){
  $('destWarning').textContent='';
  if(!$('restricted').checked){restrictedLayer.clearLayers();return}
  try{
    const list=await overpassRestricted(r);
    restrictedPlaces=list;drawRestricted(list);
    const w=destinationWarning(dest,list);
    if(w)$('destWarning').innerHTML='<span class="red">'+w+'</span>';
  }catch(_){}
}
function clearUnsafeRoute(){
  routeLayer.clearLayers();markerLayer.clearLayers();
  $('sum').style.display='none';
  AR=null;NAV_DEST=null;
}
function safeStopFeet(r){
  return r?._safeStop?Math.round(r._safeStop.distanceToDestination*3.28084):null;
}
async function build(fromGps=false){
  const oq=$('o').value.trim(),dq=$('d').value.trim();
  if(!dq)return status('Enter a destination.','err');

  $('go').disabled=true;
  clearUnsafeRoute();
  $('nav').style.display='none';
  $('fill').style.background='#1a73e8';

  try{
    progress(8,'Resolving route','Checking origin and destination');
    const a=fromGps||!oq||oq==='Current location'?await gpsOnce():await resolve(oq,SO);
    const b=await resolve(dq,SD);

    SO=a;DEST=b;activeOrigin=a;
    if(fromGps||!oq)$('o').value='Current location';

    progress(20,'Normal route','Getting fast baseline alternatives');
    const alternatives=await route(a,b,[],true);

    progress(30,'School data','Using Tampa / Orlando cache when possible');
    schools=await loadSchools(alternatives[0]);

    progress(48,'Scanning school zones',schools.length+' nearby schools ready');
    const out=await avoidRoute(a,b,alternatives);

    if(!out.r){
      clearUnsafeRoute();
      drawSchools(alternatives[0]);
      progress(100,'Route not validated',out.diagnostic||'No clean route or safe stop found');
      $('fill').style.background='#d93025';
      status(out.diagnostic||'No validated school-safe route or safe stop was found.','err');
      return;
    }

    const r=out.r;
    const remaining=hitList(r);
    if(remaining.length){
      clearUnsafeRoute();
      drawSchools(r);
      throw Error('Final validation rejected '+remaining.length+' school-zone intersection'+(remaining.length===1?'':'s'));
    }

    AR=r;
    NAV_DEST=r._safeStop?r._safeStop.point:b;

    progress(95,'Drawing route','Final independent validation passed');
    drawRoute(r,a,b);

    $('sumMain').textContent=time(r.duration)+' · '+miles(r.distance);
    if(r._safeStop){
      const ft=safeStopFeet(r);
      $('sumSub').innerHTML='<span class="safeStopText">SAFE STOP · closest reachable validated road point outside the red zone</span>';
      $('destWarning').innerHTML='<span class="red">Navigation stops approximately '+ft.toLocaleString()+' ft from the requested destination, outside the school zone near '+r._safeStop.school+'.</span>';
    }else{
      $('sumSub').innerHTML='<span class="valid">Validated · zero prohibited 1,000 ft school-zone crossings</span>';
    }
    $('sum').style.display='block';

    progress(100,'Route ready',(r.provider||routingDiagnostics.provider||'Routing')+' · strict validation passed');
    $('fill').style.background='#0b69ff';
    status(
      r._safeStop
        ?'Safe-stop route ready. Navigation will stop outside the red school zone.'
        :'Route validated. Tap Navigation for follow mode.',
      'ok'
    );
    loadRestrictedAsync(r,b);
  }catch(e){
    clearUnsafeRoute();
    status('Could not calculate route: '+e.message,'err');
    progress(100,'Route failed',e.message);
    $('fill').style.background='#d93025';
  }finally{
    $('go').disabled=false;
  }
}
$('go').onclick=()=>build(false);

$('loc').onclick=async()=>{
  try{
    $('loc').disabled=true;$('loc').textContent='Locating…';
    const p=await gpsOnce();
    SO=p;activeOrigin=p;$('o').value='Current location';
    gpsLayer.clearLayers();
    L.circleMarker([p.lat,p.lon],{radius:8,color:'#fff',weight:3,fillColor:'#0b69ff',fillOpacity:1}).addTo(gpsLayer);
    map.setView([p.lat,p.lon],16);
    status('Current GPS location selected.','ok');
  }catch(e){
    status(e.message.toLowerCase().includes('denied')
      ?'Location is blocked for this site. Allow Location in browser/site settings, then try again.'
      :e.message,'err');
  }finally{
    $('loc').disabled=false;$('loc').textContent='Use My Location';
  }
};

$('restricted').onchange=()=>{
  if(!$('restricted').checked){restrictedLayer.clearLayers();$('destWarning').textContent=''}
  else if(AR&&DEST)loadRestrictedAsync(AR,DEST);
};

function routeBearingNear(lat,lon){
  try{
    if(!AR?.geometry?.coordinates?.length)return null;
    const c=AR.geometry.coordinates,mx=111320*Math.cos(lat*Math.PI/180),my=110540;
    let bi=0,bd=Infinity;
    for(let i=0;i<c.length-1;i++){
      const dx=(c[i][0]-lon)*mx,dy=(c[i][1]-lat)*my,d=dx*dx+dy*dy;
      if(d<bd){bd=d;bi=i}
    }
    const a=c[bi],b=c[Math.min(c.length-1,bi+4)];
    const p1=a[1]*Math.PI/180,p2=b[1]*Math.PI/180,dl=(b[0]-a[0])*Math.PI/180;
    const y=Math.sin(dl)*Math.cos(p2),x=Math.cos(p1)*Math.sin(p2)-Math.sin(p1)*Math.cos(p2)*Math.cos(dl);
    return(Math.atan2(y,x)*180/Math.PI+360)%360;
  }catch(_){return null}
}
async function reroute(lat,lon){
  if(isRerouting||!NAV_DEST||Date.now()-lastReroute<15000)return;
  isRerouting=true;lastReroute=Date.now();
  try{
    const a={lat,lon,label:'Current location'};
    activeOrigin=a;
    const target=NAV_DEST;
    const alternatives=await route(a,target,[],true);
    schools=await loadSchools(alternatives[0]);
    const out=await avoidRoute(a,target,alternatives);

    if(!out.r||hitList(out.r).length){
      status('Live reroute could not find a validated route. Keeping the last validated route.','err');
      return;
    }
    AR=out.r;
    if(out.r._safeStop)NAV_DEST=out.r._safeStop.point;
    drawRoute(out.r,a,target);
    $('sumMain').textContent=time(out.r.duration)+' · '+miles(out.r.distance);
    $('sumSub').innerHTML='<span class="valid">Live reroute validated · zero prohibited school-zone crossings</span>';
    status('Rerouted from current position.','ok');
  }catch(e){
    status('Live reroute failed: '+e.message,'err');
  }finally{isRerouting=false}
}
function stopGps(){
  if(watch!==null){navigator.geolocation.clearWatch(watch);watch=null}
  $('gps').textContent='Start GPS';$('gps').classList.remove('active');
}
async function startGpsTracking(){
  if(!navigator.geolocation){status('GPS unavailable in this browser.','err');return false}
  if(watch!==null)return true;

  $('gps').disabled=true;$('gps').textContent='Starting GPS…';
  try{
    await window.__requestHeadingPermission?.();
    const first=await gpsOnce();
    const firstHeading=routeBearingNear(first.lat,first.lon);
    window.__setNavMarker?.(first.lon,first.lat,firstHeading||0);
    window.__updateNavCamera?.(first.lat,first.lon,firstHeading,0,false);

    watch=navigator.geolocation.watchPosition(p=>{
      const lat=p.coords.latitude,lon=p.coords.longitude;
      const speed=Number.isFinite(p.coords.speed)?p.coords.speed:0;
      const heading=Number.isFinite(p.coords.heading)&&p.coords.heading!=null?p.coords.heading:routeBearingNear(lat,lon);
      window.__updateNavCamera?.(lat,lon,heading,speed,false);
      if(AR){
        let off=0;
        try{
          off=turf.pointToLineDistance(
            turf.point([lon,lat]),
            turf.lineString(AR.geometry.coordinates),
            {units:'kilometers'}
          )*1000;
        }catch(_){}
        if(off>130)reroute(lat,lon);
      }
    },e=>{
      stopGps();
      status(e.code===1
        ?'GPS permission denied. Allow Location for this site, then tap Start GPS again.'
        :'GPS error: '+e.message,'err');
    },{enableHighAccuracy:true,maximumAge:1000,timeout:15000});

    $('gps').textContent='GPS Active';$('gps').classList.add('active');
    status(window.__SZ_MAP_MODE==='vector'
      ?'GPS active · heading-up follow mode.'
      :'GPS active · stable follow mode.','ok');
    return true;
  }catch(e){
    $('gps').textContent='Start GPS';
    status(e.message.toLowerCase().includes('denied')
      ?'GPS permission denied. Allow Location for this site, then try again.'
      :'GPS error: '+e.message,'err');
    return false;
  }finally{$('gps').disabled=false}
}
$('navBtn').onclick=async()=>{
  if(!AR)return status('No validated route is available for navigation.','err');
  if(hitList(AR).length)return status('Navigation blocked: route failed school-zone validation.','err');
  $('sum').style.display='none';
  $('nav').style.display='flex';
  window.__enterNavVisual?.();
  $('navTitle').textContent=AR._safeStop?'Navigation to Safe Stop':'Navigation';
  $('navText').textContent=AR._safeStop
    ?'Stopping outside the red school zone'
    :(window.__SZ_MAP_MODE==='vector'?'Following position + heading':'Following live GPS position');
  await startGpsTracking();
};
$('gps').onclick=()=>startGpsTracking();
$('exit').onclick=()=>{
  stopGps();$('nav').style.display='none';
  window.__exitNavVisual?.();
  $('sum').style.display=AR?'block':'none';
  status('Navigation stopped.','');
};
