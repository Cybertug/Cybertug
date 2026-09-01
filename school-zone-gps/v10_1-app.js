function restrictedBBox(r,padKm=1.2){return routeBox(r,padKm)}

async function overpassRestricted(r){
  if(!$('restricted').checked)return[];
  const b=restrictedBBox(r);
  const q=`[out:json][timeout:8];(
    nwr["amenity"~"^(police|courthouse|prison|university|college)$"](${b.ymin},${b.xmin},${b.ymax},${b.xmax});
    nwr["aeroway"="terminal"](${b.ymin},${b.xmin},${b.ymax},${b.xmax});
  );out center tags;`;

  const body='data='+encodeURIComponent(q);
  const eps=[
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass-api.de/api/interpreter'
  ];

  let data=null;
  for(const ep of eps){
    try{
      data=await j(ep,{
        method:'POST',
        headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},
        body
      },9000);
      break;
    }catch(_){}
  }
  if(!data)return[];

  return(data.elements||[]).map(e=>{
    const lat=e.lat??e.center?.lat,lon=e.lon??e.center?.lon,t=e.tags||{};
    if(lat==null||lon==null)return null;
    const kind=t.amenity||t.aeroway||'restricted';
    return{name:t.name||kind,lat,lon,kind};
  }).filter(Boolean);
}

function restrictedLabel(kind){
  return({
    police:'Police facility',
    courthouse:'Courthouse',
    prison:'Jail / prison',
    university:'University',
    college:'College',
    terminal:'Airport terminal'
  })[kind]||'Potential restricted location'
}

function drawRestricted(list){
  restrictedLayer.clearLayers();
  for(const p of list){
    L.circleMarker([p.lat,p.lon],{
      radius:5,color:'#fff',weight:2,fillColor:'#8b1e1e',fillOpacity:1
    })
    .bindPopup(
      '<b>'+p.name+'</b><br>'+restrictedLabel(p.kind)+
      '<br><small>Potential firearm-restricted location. No distance buffer applied; verify current law and site rules.</small>'
    )
    .addTo(restrictedLayer);
  }
}

function destinationWarning(dest,list){
  let nearest=null,dist=Infinity;
  for(const p of list){
    const d=turf.distance(
      turf.point([dest.lon,dest.lat]),
      turf.point([p.lon,p.lat]),
      {units:'kilometers'}
    )*1000;
    if(d<dist){dist=d;nearest=p}
  }
  if(nearest&&dist<180){
    return'Destination is near '+nearest.name+' ('+
      restrictedLabel(nearest.kind)+'). Verify firearm restrictions before entering.';
  }
  return'';
}

async function loadRestrictedAsync(r,dest){
  $('destWarning').textContent='';
  if(!$('restricted').checked){
    restrictedLayer.clearLayers();
    return;
  }
  try{
    const list=await overpassRestricted(r);
    restrictedPlaces=list;
    drawRestricted(list);
    const w=destinationWarning(dest,list);
    if(w)$('destWarning').innerHTML='<span class="red">'+w+'</span>';
  }catch(_){}
}

function clearUnsafeRoute(){
  routeLayer.clearLayers();
  markerLayer.clearLayers();
  $('sum').style.display='none';
  $('nav').style.display='none';
  AR=null;
}

async function build(fromGps=false){
  const oq=$('o').value.trim(),dq=$('d').value.trim();
  if(!dq)return status('Enter a destination.','err');

  $('go').disabled=true;
  clearUnsafeRoute();
  $('fill').style.background='#1a73e8';

  try{
    progress(8,'Resolving route','Checking origin and destination');

    const a=fromGps||!oq||oq==='Current location'
      ?await gpsOnce()
      :await resolve(oq,SO);

    const b=await resolve(dq,SD);

    SO=a;DEST=b;activeOrigin=a;
    if(fromGps||!oq)$('o').value='Current location';

    progress(20,'Normal route','Getting route alternatives');
    const alternatives=await route(a,b,[],true);

    progress(30,'School data','Using preloaded Tampa / Orlando cache when possible');
    schools=await loadSchools(alternatives[0]);

    progress(48,'Scanning alternatives',schools.length+' nearby schools ready');

    const out=await avoidRoute(a,b,alternatives);

    if(!out.r){
      clearUnsafeRoute();
      drawSchools(alternatives[0]);
      progress(
        100,
        'No validated route yet',
        'Every tested route still entered at least one 1,000 ft school zone'
      );
      $('fill').style.background='#d93025';
      status(
        'No validated school-safe route was found. The app will not display or navigate a route that enters a red school zone.',
        'err'
      );
      return;
    }

    const r=out.r;
    const remaining=hitList(r);
    if(remaining.length){
      clearUnsafeRoute();
      drawSchools(r);
      throw Error(
        'Final validation rejected the route because it intersects '+
        remaining.length+' school zone'+(remaining.length===1?'':'s')+'.'
      );
    }

    AR=r;
    progress(95,'Drawing route','Zero school-zone intersections confirmed');
    drawRoute(r,a,b);

    $('sumMain').textContent=time(r.duration)+' · '+miles(r.distance);
    $('sumSub').innerHTML=
      '<span style="color:#137333;font-weight:700">Validated · zero detected 1,000 ft school-zone crossings</span>';

    $('sum').style.display='block';
    progress(100,'Route ready','Strict validation passed');
    $('fill').style.background='#0057FF';
    status('Strict school-safe route calculated successfully.','ok');

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
  $('loc').disabled=true;
  $('loc').textContent='Requesting location…';
  try{
    const p=await gpsOnce();
    SO=p;activeOrigin=p;
    $('o').value='Current location';

    gpsLayer.clearLayers();
    L.circleMarker([p.lat,p.lon],{
      radius:8,color:'#fff',weight:3,fillColor:'#0057FF',fillOpacity:1
    }).addTo(gpsLayer);

    map.setView([p.lat,p.lon],15);
    status('Current GPS location selected.','ok');
  }catch(e){
    status(
      e.message.toLowerCase().includes('denied')
        ?'Location permission is blocked. Allow location for this site in your browser, or use a typed starting address.'
        :e.message,
      'err'
    );
  }finally{
    $('loc').disabled=false;
    $('loc').textContent='Use My Location';
  }
};

$('restricted').onchange=()=>{
  if(!$('restricted').checked){
    restrictedLayer.clearLayers();
    $('destWarning').textContent='';
  }else if(AR&&DEST){
    loadRestrictedAsync(AR,DEST);
  }
};

$('navBtn').onclick=()=>{
  if(!AR)return status('No validated route is available for navigation.','err');

  const conflicts=hitList(AR);
  if(conflicts.length){
    clearUnsafeRoute();
    return status(
      'Navigation blocked: the route failed the final school-zone validation.',
      'err'
    );
  }

  $('nav').style.display='block';
  $('navTitle').textContent='Navigation';
  $('navText').textContent='Press Start GPS to follow your live position.';
};

$('exit').onclick=()=>{
  $('nav').style.display='none';
  if(watch!==null){
    navigator.geolocation.clearWatch(watch);
    watch=null;
    $('gps').textContent='Start GPS';
  }
};

async function reroute(lat,lon){
  if(isRerouting||!DEST||Date.now()-lastReroute<15000)return;

  isRerouting=true;
  lastReroute=Date.now();

  try{
    const a={lat,lon,label:'Current location'};
    activeOrigin=a;

    const alternatives=await route(a,DEST,[],true);
    schools=await loadSchools(alternatives[0]);

    const out=await avoidRoute(a,DEST,alternatives);

    if(!out.r){
      status(
        'Live reroute could not find a zero-conflict school-safe route. Keeping the last validated route.',
        'err'
      );
      return;
    }

    if(hitList(out.r).length){
      status('Live reroute rejected because it enters a school zone.','err');
      return;
    }

    AR=out.r;
    drawRoute(out.r,a,DEST);

    $('sumMain').textContent=time(out.r.duration)+' · '+miles(out.r.distance);
    $('sumSub').innerHTML=
      '<span style="color:#137333;font-weight:700">Live reroute validated · zero school-zone crossings</span>';

    status('Rerouted from your current GPS location.','ok');
    loadRestrictedAsync(out.r,DEST);

  }catch(e){
    status('Live reroute failed: '+e.message,'err');
  }finally{
    isRerouting=false;
  }
}

function beginGpsWatch(){
  watch=navigator.geolocation.watchPosition(
    p=>{
      const lat=p.coords.latitude,lon=p.coords.longitude;

      gpsLayer.clearLayers();
      L.circleMarker([lat,lon],{
        radius:8,color:'#fff',weight:3,fillColor:'#0057FF',fillOpacity:1
      }).addTo(gpsLayer);

      map.setView([lat,lon],16);

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
    },
    e=>{
      if(watch!==null){
        navigator.geolocation.clearWatch(watch);
        watch=null;
      }
      $('gps').textContent='Start GPS';
      status(
        e.code===1
          ?'GPS permission denied. Allow location for this site in browser settings, then press Start GPS again.'
          :'GPS error: '+e.message,
        'err'
      );
    },
    {enableHighAccuracy:true,maximumAge:2000,timeout:15000}
  );
}

$('gps').onclick=async()=>{
  if(!navigator.geolocation)return status('GPS unavailable in this browser.','err');
  if(watch!==null)return;

  $('gps').disabled=true;
  $('gps').textContent='Requesting GPS…';

  try{
    const first=await gpsOnce();

    gpsLayer.clearLayers();
    L.circleMarker([first.lat,first.lon],{
      radius:8,color:'#fff',weight:3,fillColor:'#0057FF',fillOpacity:1
    }).addTo(gpsLayer);

    map.setView([first.lat,first.lon],16);

    beginGpsWatch();
    $('gps').textContent='GPS Active';
    status('GPS active.','ok');

  }catch(e){
    $('gps').textContent='Start GPS';
    status(
      e.message.toLowerCase().includes('denied')
        ?'GPS permission denied. Allow location for this site in browser settings, then try again.'
        :'GPS error: '+e.message,
      'err'
    );
  }finally{
    $('gps').disabled=false;
  }
};
