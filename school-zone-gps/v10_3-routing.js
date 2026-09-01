/* School Zone GPS v10.3 — Valhalla polygon routing
   - Sends intersecting 1,000 ft school circles directly to Valhalla as exclude_polygons.
   - Iteratively adds only newly encountered school zones.
   - Uses fast line-to-circle validation before a route is accepted.
   - Sequential calls respect the public demo server's rate limit and keep the UI responsive.
*/

const VALIDATION_RADIUS_M=304.8;
let lastValhallaCall=0;
const routeHitCache=new WeakMap();

function yieldBrowser(ms=0){
  return new Promise(resolve=>setTimeout(resolve,ms));
}

function metersPerLon(lat){return 111320*Math.cos(lat*Math.PI/180)}

function pointToSegmentMeters(sLon,sLat,aLon,aLat,bLon,bLat){
  const mx=metersPerLon(sLat),my=110540;
  const ax=(aLon-sLon)*mx,ay=(aLat-sLat)*my;
  const bx=(bLon-sLon)*mx,by=(bLat-sLat)*my;
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
      if(s.lon<Math.min(a[0],d[0])-padLon||s.lon>Math.max(a[0],d[0])+padLon||s.lat<Math.min(a[1],d[1])-padLat||s.lat>Math.max(a[1],d[1])+padLat)continue;
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

function pointInsideSchool(point,s){
  return distanceMeters(point,{lat:s.lat,lon:s.lon})<=VALIDATION_RADIUS_M;
}

function circleRing(s,points=12){
  const out=[];
  const latRad=s.lat*Math.PI/180;
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

async function valhallaRateLimit(){
  const wait=Math.max(0,1100-(Date.now()-lastValhallaCall));
  if(wait)await yieldBrowser(wait);
  lastValhallaCall=Date.now();
}

async function valhallaRoute(a,b,blockedSchools){
  await valhallaRateLimit();

  const payload={
    locations:[
      {lat:a.lat,lon:a.lon,type:'break'},
      {lat:b.lat,lon:b.lon,type:'break'}
    ],
    costing:'auto',
    units:'kilometers',
    directions_options:{units:'kilometers'},
    exclude_polygons:blockedSchools.map(s=>circleRing(s,12)),
    exclude_locations:blockedSchools.map(s=>({lat:s.lat,lon:s.lon}))
  };

  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),26000);
  try{
    const resp=await fetch('https://valhalla1.openstreetmap.de/route',{
      method:'POST',
      headers:{
        'Content-Type':'application/json',
        'X-Client-Id':'school-zone-gps'
      },
      body:JSON.stringify(payload),
      signal:controller.signal
    });

    if(!resp.ok){
      let detail='HTTP '+resp.status;
      try{const txt=await resp.text();if(txt)detail+=' '+txt.slice(0,180)}catch(_){}
      throw Error(detail);
    }

    const data=await resp.json();
    if(data.error||!data.trip||!data.trip.legs?.length)throw Error(data.error||'Valhalla returned no route');

    const coords=[];
    for(const leg of data.trip.legs){
      const c=decodePolyline6(leg.shape||'');
      if(coords.length&&c.length&&coords[coords.length-1][0]===c[0][0]&&coords[coords.length-1][1]===c[0][1])c.shift();
      coords.push(...c);
    }
    if(coords.length<2)throw Error('Valhalla returned empty geometry');

    const summary=data.trip.summary||{};
    return{
      geometry:{type:'LineString',coordinates:coords},
      duration:+summary.time||0,
      distance:(+summary.length||0)*1000,
      legs:data.trip.legs
    };
  }catch(e){
    if(e.name==='AbortError')throw Error('Valhalla routing timed out');
    throw e;
  }finally{clearTimeout(timer)}
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
  for(const r of sorted){
    await yieldBrowser(0);
    if(hitList(r).length===0)return{r,n:0};
  }

  const blocked=new Map();
  for(const h of schoolHitInfos(sorted[0]))blocked.set(h.s.id,h.s);

  for(let pass=0;pass<7;pass++){
    const blockedList=[...blocked.values()];
    progress(
      58+pass*5,
      'Routing around school zones',
      blockedList.length+' blocked school zone'+(blockedList.length===1?'':'s')+' · engine pass '+(pass+1)+'/7'
    );

    await yieldBrowser(0);

    let r;
    try{
      r=await valhallaRoute(a,b,blockedList.slice(0,32));
    }catch(e){
      throw Error('School-zone routing engine failed: '+e.message);
    }

    const hits=schoolHitInfos(r);
    if(!hits.length)return{r,n:0};

    let added=0;
    for(const h of hits){
      if(!blocked.has(h.s.id)&&blocked.size<32){blocked.set(h.s.id,h.s);added++}
    }

    if(!added){
      for(const h of hits){
        for(const s of schools){
          if(blocked.has(s.id)||blocked.size>=32)continue;
          if(distanceMeters({lat:h.s.lat,lon:h.s.lon},{lat:s.lat,lon:s.lon})<900){
            blocked.set(s.id,s);added++;
          }
        }
      }
    }

    if(!added)break;
  }

  return{r:null,n:Math.max(1,blocked.size)};
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
  L.polyline(ll,{color:'#172A46',weight:16,opacity:.82,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.polyline(ll,{color:'#FFFFFF',weight:12,opacity:1,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.polyline(ll,{color:'#006CFF',weight:8,opacity:1,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.circleMarker([a.lat,a.lon],{radius:8,color:'#fff',weight:3,fillColor:'#006CFF',fillOpacity:1}).addTo(markerLayer);
  L.marker([b.lat,b.lon]).addTo(markerLayer);
  map.fitBounds(ll,{padding:[40,40]});
  drawSchools(r);
}

function miles(m){return(m/1609.344).toFixed(1)+' mi'}
function time(s){const m=Math.round(s/60);return m<60?m+' min':Math.floor(m/60)+'h '+m%60+'m'}
