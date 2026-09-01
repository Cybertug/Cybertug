/* School Zone GPS v11.5 — BRouter native no-go circles.
   BRouter supports nogos=lon,lat,radius|... directly in its routing engine.
   Every displayed route is still independently revalidated against the 1,000 ft circles.
*/
const VALIDATION_RADIUS_M=304.8;
const routeHitCache=new WeakMap();

function metersPerLon(lat){return 111320*Math.cos(lat*Math.PI/180)}
function pointToSegmentMeters(sLon,sLat,aLon,aLat,bLon,bLat){
  const mx=metersPerLon(sLat),my=110540;
  const ax=(aLon-sLon)*mx,ay=(aLat-sLat)*my;
  const bx=(bLon-sLon)*mx,by=(bLat-sLat)*my;
  const vx=bx-ax,vy=by-ay,vv=vx*vx+vy*vy;
  if(vv<1e-9)return Math.hypot(ax,ay);
  let t=-(ax*vx+ay*vy)/vv;
  t=Math.max(0,Math.min(1,t));
  return Math.hypot(ax+t*vx,ay+t*vy);
}
function routeBoundsFast(r){
  if(r.__fastBounds)return r.__fastBounds;
  const c=r.geometry.coordinates;
  let minLon=Infinity,maxLon=-Infinity,minLat=Infinity,maxLat=-Infinity;
  for(const p of c){
    minLon=Math.min(minLon,p[0]);maxLon=Math.max(maxLon,p[0]);
    minLat=Math.min(minLat,p[1]);maxLat=Math.max(maxLat,p[1]);
  }
  const b={minLon,maxLon,minLat,maxLat};
  try{Object.defineProperty(r,'__fastBounds',{value:b,enumerable:false})}catch(_){}
  return b;
}
function schoolHitInfos(r){
  if(!r)return[];
  const cached=routeHitCache.get(r);
  if(cached&&cached.schoolsRef===schools)return cached.hits;

  const coords=r.geometry.coordinates,b=routeBoundsFast(r);
  const padLat=VALIDATION_RADIUS_M/110540;
  const padLon=VALIDATION_RADIUS_M/Math.max(20000,metersPerLon((b.minLat+b.maxLat)/2));
  const hits=[];

  for(const s of schools){
    if(s.lon<b.minLon-padLon||s.lon>b.maxLon+padLon||
       s.lat<b.minLat-padLat||s.lat>b.maxLat+padLat)continue;

    let seg=-1,minDist=Infinity;
    for(let i=0;i<coords.length-1;i++){
      const a=coords[i],d=coords[i+1];
      if(s.lon<Math.min(a[0],d[0])-padLon||s.lon>Math.max(a[0],d[0])+padLon||
         s.lat<Math.min(a[1],d[1])-padLat||s.lat>Math.max(a[1],d[1])+padLat)continue;
      const dist=pointToSegmentMeters(s.lon,s.lat,a[0],a[1],d[0],d[1]);
      minDist=Math.min(minDist,dist);
      if(dist<=VALIDATION_RADIUS_M){seg=i;break}
    }
    if(seg>=0)hits.push({s,segmentIndex:seg,distance:minDist});
  }

  hits.sort((a,b)=>a.segmentIndex-b.segmentIndex);
  routeHitCache.set(r,{schoolsRef:schools,hits});
  return hits;
}
function hitList(r){
  if(!$('avoid').checked||!r)return[];
  return schoolHitInfos(r).map(x=>x.s);
}

function distanceMeters(a,b){
  const R0=6371000,p1=a.lat*Math.PI/180,p2=b.lat*Math.PI/180;
  const dp=(b.lat-a.lat)*Math.PI/180,dl=(b.lon-a.lon)*Math.PI/180;
  const h=Math.sin(dp/2)**2+Math.cos(p1)*Math.cos(p2)*Math.sin(dl/2)**2;
  return 2*R0*Math.asin(Math.min(1,Math.sqrt(h)));
}
function destinationConflict(b){
  let nearest=null,d=Infinity;
  for(const s of schools){
    const x=distanceMeters(b,{lat:s.lat,lon:s.lon});
    if(x<d){d=x;nearest=s}
  }
  return nearest&&d<=VALIDATION_RADIUS_M?{s:nearest,d}:null;
}
function bearing(a,b){
  const p1=a.lat*Math.PI/180,p2=b.lat*Math.PI/180,dl=(b.lon-a.lon)*Math.PI/180;
  const y=Math.sin(dl)*Math.cos(p2);
  const x=Math.cos(p1)*Math.sin(p2)-Math.sin(p1)*Math.cos(p2)*Math.cos(dl);
  return(Math.atan2(y,x)*180/Math.PI+360)%360;
}
function destinationPoint(lon,lat,distM,bearingDeg){
  const R0=6371000,br=bearingDeg*Math.PI/180,p1=lat*Math.PI/180,l1=lon*Math.PI/180,d=distM/R0;
  const p2=Math.asin(Math.sin(p1)*Math.cos(d)+Math.cos(p1)*Math.sin(d)*Math.cos(br));
  const l2=l1+Math.atan2(Math.sin(br)*Math.sin(d)*Math.cos(p1),Math.cos(d)-Math.sin(p1)*Math.sin(p2));
  return{lon:l2*180/Math.PI,lat:p2*180/Math.PI};
}
function safeApproachPoint(a,b,conf){
  const h=bearing({lat:conf.s.lat,lon:conf.s.lon},a);
  return destinationPoint(conf.s.lon,conf.s.lat,VALIDATION_RADIUS_M+120,h);
}

function uniqueSchools(list){
  const m=new Map();
  for(const s of list)m.set(s.id||s.type+':'+s.name+':'+s.lat.toFixed(5)+':'+s.lon.toFixed(5),s);
  return[...m.values()];
}
function schoolNeighbors(seed,list,maxM=1150){
  const out=[];
  for(const s of list){
    if(distanceMeters({lat:seed.lat,lon:seed.lon},{lat:s.lat,lon:s.lon})<=maxM)out.push(s);
  }
  return out;
}
function initialBlocked(route){
  let blocked=[];
  for(const h of schoolHitInfos(route)){
    blocked.push(h.s);
    blocked.push(...schoolNeighbors(h.s,schools,1000));
  }
  return uniqueSchools(blocked).slice(0,55);
}

function parseBrouterGeoJson(data){
  const feat=(data.features||[]).find(f=>f.geometry?.type==='LineString');
  if(!feat)throw Error('BRouter returned no route geometry');

  const coords=(feat.geometry.coordinates||[]).map(p=>[+p[0],+p[1]]);
  if(coords.length<2)throw Error('BRouter route geometry is empty');

  const p=feat.properties||{};
  const distance=Number(p['track-length'])||0;
  const duration=Number(p['total-time'])||0;

  return{
    geometry:{type:'LineString',coordinates:coords},
    distance,
    duration,
    brouter:true,
    brouterProperties:p
  };
}

async function brouterNativeRoute(a,b,blocked,attempt=0){
  const u=new URL('https://brouter.de/brouter');
  u.searchParams.set('lonlats',a.lon+','+a.lat+'|'+b.lon+','+b.lat);
  u.searchParams.set('profile','car-fast');
  u.searchParams.set('alternativeidx',String(Math.min(3,attempt)));
  u.searchParams.set('format','geojson');
  u.searchParams.set('timode','4');

  if(blocked.length){
    u.searchParams.set(
      'nogos',
      blocked.map(s=>[
        (+s.lon).toFixed(6),
        (+s.lat).toFixed(6),
        VALIDATION_RADIUS_M.toFixed(1)
      ].join(',')).join('|')
    );
  }

  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),22000);
  try{
    const resp=await fetch(u.toString(),{
      method:'GET',
      headers:{'Accept':'application/geo+json,application/json'},
      signal:controller.signal
    });
    if(!resp.ok){
      let msg='HTTP '+resp.status;
      try{
        const t=await resp.text();
        if(t)msg+=' '+t.slice(0,180);
      }catch(_){}
      throw Error(msg);
    }
    const data=await resp.json();
    return parseBrouterGeoJson(data);
  }catch(e){
    if(e.name==='AbortError')throw Error('BRouter timed out');
    throw e;
  }finally{
    clearTimeout(timer);
  }
}

async function mergeSchoolsForRoute(r){
  try{
    const extra=await loadSchools(r);
    schools=uniqueSchools([...schools,...extra]);
  }catch(e){
    console.warn('Additional school lookup skipped',e);
  }
}

async function brouterAvoid(a,b,seedRoute){
  let blocked=initialBlocked(seedRoute);
  if(!blocked.length)return seedRoute;

  let lastRoute=null;
  for(let pass=0;pass<6;pass++){
    progress(
      56+pass*6,
      'Routing around school zones',
      blocked.length+' school no-go circle'+(blocked.length===1?'':'s')+
      ' · native no-go pass '+(pass+1)+'/6'
    );

    const r=await brouterNativeRoute(a,b,blocked,pass%2);
    lastRoute=r;

    await mergeSchoolsForRoute(r);
    const hits=schoolHitInfos(r);

    if(!hits.length)return r;

    let added=0;
    for(const h of hits){
      const candidates=[h.s,...schoolNeighbors(h.s,schools,1000)];
      for(const s of candidates){
        if(blocked.length>=70)break;
        const key=s.id||s.type+':'+s.name+':'+s.lat.toFixed(5)+':'+s.lon.toFixed(5);
        const exists=blocked.some(x=>(x.id||x.type+':'+x.name+':'+x.lat.toFixed(5)+':'+x.lon.toFixed(5))===key);
        if(!exists){blocked.push(s);added++}
      }
    }

    if(!added)break;
    await new Promise(r=>setTimeout(r,250));
  }

  return lastRoute&&schoolHitInfos(lastRoute).length===0?lastRoute:null;
}

async function avoidRoute(a,b,alternatives){
  if(!$('avoid').checked){
    const r=alternatives.slice().sort((x,y)=>x.duration-y.duration)[0];
    return{r,n:0};
  }

  // Normal OSRM alternatives are free to use if already clear.
  const sorted=alternatives.slice().sort((x,y)=>x.duration-y.duration);
  for(const r of sorted){
    if(!schoolHitInfos(r).length)return{r,n:0};
  }

  // Destination inside a red zone: stop outside it instead of routing into it.
  const dc=destinationConflict(b);
  let target=b;
  let safeApproach=null;
  if(dc){
    target=safeApproachPoint(a,b,dc);
    safeApproach={
      original:b,
      point:target,
      school:dc.s.name,
      reason:'Destination lies inside a mapped 1,000 ft school zone'
    };

    const targetAlts=await route(a,target,[],true);
    await mergeSchoolsForRoute(targetAlts[0]);

    for(const r of targetAlts){
      if(!schoolHitInfos(r).length){
        r._safeApproach=safeApproach;
        return{r,n:0,safeApproach:true};
      }
    }

    const br=await brouterAvoid(a,target,targetAlts[0]);
    if(br){
      br._safeApproach=safeApproach;
      return{r:br,n:0,safeApproach:true};
    }
    return{r:null,n:1,destinationBlocked:true,school:dc.s.name};
  }

  // Native no-go engine.
  try{
    const br=await brouterAvoid(a,b,sorted[0]);
    if(br&&!schoolHitInfos(br).length)return{r:br,n:0};
  }catch(e){
    console.warn('BRouter native no-go routing failed',e);
    progress(88,'BRouter unavailable','Using local fallback');
  }

  // Final resilient fallback: use the existing corridor engine if present.
  if(typeof globalCorridorSearch==='function'){
    try{
      const c=await globalCorridorSearch(a,b,sorted);
      if(c&&!schoolHitInfos(c).length)return{r:c,n:0};
    }catch(_){}
  }

  return{r:null,n:Math.max(1,schoolHitInfos(sorted[0]).length)};
}

function drawSchools(r){
  schoolLayer.clearLayers();
  if(!r)return;
  const b=routeBoundsFast(r);
  const padLat=1400/110540;
  const padLon=1400/Math.max(20000,metersPerLon((b.minLat+b.maxLat)/2));

  for(const s of schools){
    if(s.lon<b.minLon-padLon||s.lon>b.maxLon+padLon||
       s.lat<b.minLat-padLat||s.lat>b.maxLat+padLat)continue;

    L.circle([s.lat,s.lon],{
      radius:VALIDATION_RADIUS_M,
      color:'#D93025',
      weight:2.5,
      fillColor:'#EA4335',
      fillOpacity:.13
    })
    .bindPopup('<b>'+s.name+'</b><br>1,000 ft school exclusion zone')
    .addTo(schoolLayer);
  }
}

function drawRoute(r,a,b){
  routeLayer.clearLayers();
  markerLayer.clearLayers();
  if(!r)return;

  const ll=r.geometry.coordinates.map(p=>[p[1],p[0]]);

  L.polyline(ll,{color:'#082d67',weight:16,opacity:.72,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.polyline(ll,{color:'#fff',weight:12,opacity:1,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.polyline(ll,{color:'#0b69ff',weight:8,opacity:1,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);

  L.circleMarker([a.lat,a.lon],{
    radius:8,color:'#fff',weight:3,fillColor:'#0b69ff',fillOpacity:1
  }).addTo(markerLayer);

  const end=r._safeApproach?r._safeApproach.point:b;
  L.marker([end.lat,end.lon]).addTo(markerLayer);

  map.fitBounds(ll,{padding:[40,40]});
  drawSchools(r);
}

function miles(m){return(m/1609.344).toFixed(1)+' mi'}
function time(s){
  const m=Math.round(s/60);
  return m<60?m+' min':Math.floor(m/60)+'h '+m%60+'m';
}
