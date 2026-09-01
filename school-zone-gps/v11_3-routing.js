/* School Zone GPS v11.3 — resilient school avoidance
   OSRM-first progressive detours; Valhalla is only an optional secondary attempt.
   No route is accepted unless it has ZERO detected 1,000 ft school-circle intersections.
*/
const VALIDATION_RADIUS_M=304.8;
const routeHitCache=new WeakMap();
let lastValhallaCall=0;

function yieldBrowser(ms=0){return new Promise(r=>setTimeout(r,ms))}
function metersPerLon(lat){return 111320*Math.cos(lat*Math.PI/180)}

function pointToSegmentMeters(sLon,sLat,aLon,aLat,bLon,bLat){
  const mx=metersPerLon(sLat),my=110540;
  const ax=(aLon-sLon)*mx, ay=(aLat-sLat)*my;
  const bx=(bLon-sLon)*mx, by=(bLat-sLat)*my;
  const vx=bx-ax,vy=by-ay,vv=vx*vx+vy*vy;
  if(vv<1e-9)return Math.hypot(ax,ay);
  let t=-(ax*vx+ay*vy)/vv;
  if(t<0)t=0; else if(t>1)t=1;
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
    if(s.lon<b.minLon-padLon||s.lon>b.maxLon+padLon||s.lat<b.minLat-padLat||s.lat>b.maxLat+padLat)continue;
    let seg=-1,minDist=Infinity;
    for(let i=0;i<coords.length-1;i++){
      const a=coords[i],d=coords[i+1];
      if(s.lon<Math.min(a[0],d[0])-padLon||s.lon>Math.max(a[0],d[0])+padLon||
         s.lat<Math.min(a[1],d[1])-padLat||s.lat>Math.max(a[1],d[1])+padLat)continue;
      const dist=pointToSegmentMeters(s.lon,s.lat,a[0],a[1],d[0],d[1]);
      if(dist<minDist)minDist=dist;
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

function pointInsideSchool(p,s){
  return distanceMeters(p,{lat:s.lat,lon:s.lon})<=VALIDATION_RADIUS_M;
}

function bearingCoords(a,b){
  const p1=a[1]*Math.PI/180,p2=b[1]*Math.PI/180,dl=(b[0]-a[0])*Math.PI/180;
  const y=Math.sin(dl)*Math.cos(p2);
  const x=Math.cos(p1)*Math.sin(p2)-Math.sin(p1)*Math.cos(p2)*Math.cos(dl);
  let h=Math.atan2(y,x)*180/Math.PI;
  if(h<0)h+=360;
  return h;
}

function destinationPoint(lon,lat,distM,bearingDeg){
  const R0=6371000,br=bearingDeg*Math.PI/180,p1=lat*Math.PI/180,l1=lon*Math.PI/180,d=distM/R0;
  const p2=Math.asin(Math.sin(p1)*Math.cos(d)+Math.cos(p1)*Math.sin(d)*Math.cos(br));
  const l2=l1+Math.atan2(Math.sin(br)*Math.sin(d)*Math.cos(p1),Math.cos(d)-Math.sin(p1)*Math.sin(p2));
  return{lon:l2*180/Math.PI,lat:p2*180/Math.PI};
}

function waypointKey(wps){
  return wps.map(p=>p.lon.toFixed(5)+','+p.lat.toFixed(5)).join('|');
}

function detourPatternsForHit(r,hit,pass){
  const c=r.geometry.coordinates;
  const i=hit.segmentIndex;
  const before=c[Math.max(0,i-10)];
  const after=c[Math.min(c.length-1,i+12)];
  let heading=bearingCoords(before,after);
  if(!Number.isFinite(heading))heading=0;

  const s=hit.s;
  const margins=pass<2?[450,700]:pass<4?[650,950]:[850,1250,1650];
  const out=[],seen=new Set();

  function add(points){
    const k=waypointKey(points);
    if(seen.has(k))return;
    seen.add(k);out.push(points);
  }

  for(const side of [1,-1]){
    for(const m of margins){
      const d=VALIDATION_RADIUS_M+m;
      add([135,105,75,45].map(a=>destinationPoint(s.lon,s.lat,d,heading+side*a)));
      if(pass>=2){
        const d2=d+250;
        add([150,120,90,60,30].map(a=>destinationPoint(s.lon,s.lat,d2,heading+side*a)));
      }
    }
  }

  for(const side of [1,-1]){
    const d=VALIDATION_RADIUS_M+(pass<3?800:1300);
    add([
      destinationPoint(s.lon,s.lat,d,heading+side*135),
      destinationPoint(s.lon,s.lat,d,heading+side*90),
      destinationPoint(s.lon,s.lat,d,heading+side*45)
    ]);
  }

  return out.slice(0,10);
}

async function routeWithWps(a,b,wps){
  const rs=await route(a,b,wps,false);
  if(!rs?.length)throw Error('No route returned');
  return rs[0];
}

function routeScore(r){
  return schoolHitInfos(r).length*1e10+(r.duration||0);
}

async function osrmProgressiveAvoid(a,b,alternatives){
  let seeds=alternatives.map(r=>({r,wps:[]}));
  seeds.sort((x,y)=>routeScore(x.r)-routeScore(y.r));

  for(const s of seeds)if(!schoolHitInfos(s.r).length)return s.r;

  let current=seeds[0];

  for(let pass=0;pass<8;pass++){
    await yieldBrowser(0);
    const hits=schoolHitInfos(current.r);
    if(!hits.length)return current.r;

    const target=hits[0];
    progress(
      58+pass*4,
      'Avoiding school zones',
      hits.length+' conflict'+(hits.length===1?'':'s')+' · local detour '+(pass+1)+'/8'
    );

    const patterns=detourPatternsForHit(current.r,target,pass);
    let candidates=[];

    for(let i=0;i<patterns.length;i+=2){
      const batch=patterns.slice(i,i+2);
      const settled=await Promise.allSettled(batch.map(extra=>{
        const wps=[...current.wps,...extra];
        return routeWithWps(a,b,wps).then(r=>({r,wps}));
      }));
      for(const x of settled)if(x.status==='fulfilled')candidates.push(x.value);
      await yieldBrowser(0);
    }

    if(!candidates.length)break;

    const clean=candidates
      .filter(c=>schoolHitInfos(c.r).length===0)
      .sort((x,y)=>(x.r.duration||0)-(y.r.duration||0));
    if(clean.length)return clean[0].r;

    candidates.sort((x,y)=>{
      const xh=schoolHitInfos(x.r),yh=schoolHitInfos(y.r);
      const xStill=xh.some(h=>h.s.id===target.s.id)?1:0;
      const yStill=yh.some(h=>h.s.id===target.s.id)?1:0;
      if(xStill!==yStill)return xStill-yStill;
      if(xh.length!==yh.length)return xh.length-yh.length;
      return (x.r.duration||0)-(y.r.duration||0);
    });

    current=candidates[0];
  }

  return null;
}

function circleRing(s,points=12){
  const out=[],latRad=s.lat*Math.PI/180;
  const dLat=VALIDATION_RADIUS_M/110540;
  const dLon=VALIDATION_RADIUS_M/Math.max(20000,111320*Math.cos(latRad));
  for(let i=0;i<points;i++){
    const a=2*Math.PI*i/points;
    out.push([
      +(s.lon+dLon*Math.cos(a)).toFixed(6),
      +(s.lat+dLat*Math.sin(a)).toFixed(6)
    ]);
  }
  out.push(out[0]);
  return out;
}

function decodePolyline6(str){
  let index=0,lat=0,lon=0,out=[];
  while(index<str.length){
    let result=0,shift=0,b;
    do{b=str.charCodeAt(index++)-63;result|=(b&31)<<shift;shift+=5}while(b>=32);
    lat+=(result&1)?~(result>>1):(result>>1);
    result=0;shift=0;
    do{b=str.charCodeAt(index++)-63;result|=(b&31)<<shift;shift+=5}while(b>=32);
    lon+=(result&1)?~(result>>1):(result>>1);
    out.push([lon/1e6,lat/1e6]);
  }
  return out;
}

async function valhallaFallback(a,b,blocked){
  const wait=Math.max(0,1150-(Date.now()-lastValhallaCall));
  if(wait)await yieldBrowser(wait);
  lastValhallaCall=Date.now();

  const payload={
    locations:[{lat:a.lat,lon:a.lon,type:'break'},{lat:b.lat,lon:b.lon,type:'break'}],
    costing:'auto',
    units:'kilometers',
    directions_options:{units:'kilometers'},
    exclude_polygons:blocked.slice(0,20).map(s=>circleRing(s,12))
  };

  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),8500);
  try{
    const resp=await fetch('https://valhalla1.openstreetmap.de/route',{
      method:'POST',
      headers:{'Content-Type':'application/json','X-Client-Id':'school-zone-gps'},
      body:JSON.stringify(payload),
      signal:controller.signal
    });
    if(!resp.ok)throw Error('HTTP '+resp.status);
    const data=await resp.json();
    if(!data.trip?.legs?.length)throw Error('No route');
    const coords=[];
    for(const leg of data.trip.legs){
      const part=decodePolyline6(leg.shape||'');
      if(coords.length&&part.length&&coords.at(-1)[0]===part[0][0]&&coords.at(-1)[1]===part[0][1])part.shift();
      coords.push(...part);
    }
    const sm=data.trip.summary||{};
    return{
      geometry:{type:'LineString',coordinates:coords},
      duration:+sm.time||0,
      distance:(+sm.length||0)*1000,
      legs:data.trip.legs
    };
  }finally{
    clearTimeout(timer);
  }
}

async function avoidRoute(a,b,alternatives){
  if(!$('avoid').checked){
    const r=alternatives.slice().sort((x,y)=>x.duration-y.duration)[0];
    return{r,n:0};
  }

  for(const s of schools){
    if(pointInsideSchool(a,s))throw Error('Starting point is inside a mapped 1,000 ft school zone.');
    if(pointInsideSchool(b,s))throw Error('Destination is inside a mapped 1,000 ft school zone.');
  }

  const sorted=alternatives.slice().sort((x,y)=>x.duration-y.duration);
  for(const r of sorted)if(!schoolHitInfos(r).length)return{r,n:0};

  progress(55,'Avoiding school zones','Fast local detour engine');
  try{
    const r=await osrmProgressiveAvoid(a,b,sorted);
    if(r&&!schoolHitInfos(r).length)return{r,n:0};
  }catch(e){
    console.warn('OSRM school detour failed',e);
  }

  progress(90,'Trying secondary routing','Short polygon-routing attempt');
  try{
    const blocked=schoolHitInfos(sorted[0]).map(h=>h.s);
    const vr=await valhallaFallback(a,b,blocked);
    if(vr&&!schoolHitInfos(vr).length)return{r:vr,n:0};
  }catch(e){
    console.warn('Valhalla fallback unavailable',e);
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
    if(s.lon<b.minLon-padLon||s.lon>b.maxLon+padLon||s.lat<b.minLat-padLat||s.lat>b.maxLat+padLat)continue;
    L.circle([s.lat,s.lon],{
      radius:VALIDATION_RADIUS_M,
      color:'#D93025',weight:2.5,
      fillColor:'#EA4335',fillOpacity:.13
    }).bindPopup('<b>'+s.name+'</b><br>1,000 ft school exclusion zone').addTo(schoolLayer);
  }
}

function drawRoute(r,a,b){
  routeLayer.clearLayers();markerLayer.clearLayers();
  if(!r)return;
  const ll=r.geometry.coordinates.map(p=>[p[1],p[0]]);
  L.polyline(ll,{color:'#0b2854',weight:15,opacity:.7,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.polyline(ll,{color:'#fff',weight:11,opacity:1,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.polyline(ll,{color:'#1565ff',weight:7,opacity:1,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.circleMarker([a.lat,a.lon],{radius:8,color:'#fff',weight:3,fillColor:'#1565ff',fillOpacity:1}).addTo(markerLayer);
  L.marker([b.lat,b.lon]).addTo(markerLayer);
  map.fitBounds(ll,{padding:[40,40]});
  drawSchools(r);
}

function miles(m){return(m/1609.344).toFixed(1)+' mi'}
function time(s){const m=Math.round(s/60);return m<60?m+' min':Math.floor(m/60)+'h '+m%60+'m'}
