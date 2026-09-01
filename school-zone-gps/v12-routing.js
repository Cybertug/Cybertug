/* School Zone GPS v12
   Primary: GraphHopper Directions API custom_model areas (priority multiply_by 0)
   Fallback: openrouteservice avoid_polygons on api.heigit.org
   Final independent validation: every displayed route must have zero forbidden school-zone re-entries/crossings.
*/
const VALIDATION_RADIUS_M=304.8;
const routeHitCache=new WeakMap();
let routingDiagnostics={provider:'',detail:'',attempts:0,originZones:0};

function metersPerLon(lat){return 111320*Math.cos(lat*Math.PI/180)}
function distanceMeters(a,b){
  const R0=6371000,p1=a.lat*Math.PI/180,p2=b.lat*Math.PI/180;
  const dp=(b.lat-a.lat)*Math.PI/180,dl=(b.lon-a.lon)*Math.PI/180;
  const h=Math.sin(dp/2)**2+Math.cos(p1)*Math.cos(p2)*Math.sin(dl/2)**2;
  return 2*R0*Math.asin(Math.min(1,Math.sqrt(h)));
}
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
  if(r.__v12bounds)return r.__v12bounds;
  const c=r.geometry.coordinates;
  let minLon=Infinity,maxLon=-Infinity,minLat=Infinity,maxLat=-Infinity;
  for(const p of c){
    minLon=Math.min(minLon,p[0]);maxLon=Math.max(maxLon,p[0]);
    minLat=Math.min(minLat,p[1]);maxLat=Math.max(maxLat,p[1]);
  }
  const b={minLon,maxLon,minLat,maxLat};
  try{Object.defineProperty(r,'__v12bounds',{value:b,enumerable:false})}catch(_){}
  return b;
}
function originInsideSchool(s){
  if(!activeOrigin||!Number.isFinite(activeOrigin.lat)||!Number.isFinite(activeOrigin.lon))return false;
  return distanceMeters(activeOrigin,{lat:s.lat,lon:s.lon})<=VALIDATION_RADIUS_M;
}
function originZoneList(){return schools.filter(originInsideSchool)}
function segmentTouchesSchool(s,a,b){
  return pointToSegmentMeters(s.lon,s.lat,a[0],a[1],b[0],b[1])<=VALIDATION_RADIUS_M;
}
function schoolViolation(r,s){
  const c=r.geometry.coordinates;
  if(c.length<2)return null;

  if(originInsideSchool(s)){
    let firstOutside=-1;
    for(let i=0;i<c.length;i++){
      const p={lon:c[i][0],lat:c[i][1]};
      if(distanceMeters(p,{lat:s.lat,lon:s.lon})>VALIDATION_RADIUS_M+15){
        firstOutside=i;break;
      }
    }
    if(firstOutside<0)return{s,segmentIndex:0,reason:'origin-zone-never-exited'};
    for(let i=Math.max(0,firstOutside-1);i<c.length-1;i++){
      if(i===firstOutside-1)continue;
      if(segmentTouchesSchool(s,c[i],c[i+1]))return{s,segmentIndex:i,reason:'origin-zone-reentry'};
    }
    return null;
  }

  for(let i=0;i<c.length-1;i++){
    if(segmentTouchesSchool(s,c[i],c[i+1]))return{s,segmentIndex:i,reason:'intersection'};
  }
  return null;
}
function schoolHitInfos(r){
  if(!r)return[];
  const cached=routeHitCache.get(r);
  if(cached&&cached.schoolsRef===schools&&cached.originRef===activeOrigin)return cached.hits;

  const b=routeBoundsFast(r);
  const padLat=VALIDATION_RADIUS_M/110540;
  const padLon=VALIDATION_RADIUS_M/Math.max(20000,metersPerLon((b.minLat+b.maxLat)/2));
  const hits=[];

  for(const s of schools){
    if(s.lon<b.minLon-padLon||s.lon>b.maxLon+padLon||
       s.lat<b.minLat-padLat||s.lat>b.maxLat+padLat)continue;
    const v=schoolViolation(r,s);
    if(v)hits.push(v);
  }
  hits.sort((x,y)=>x.segmentIndex-y.segmentIndex);
  routeHitCache.set(r,{schoolsRef:schools,originRef:activeOrigin,hits});
  return hits;
}
function hitList(r){
  if(!$('avoid').checked||!r)return[];
  return schoolHitInfos(r).map(x=>x.s);
}
function uniqueSchools(list){
  const m=new Map();
  for(const s of list){
    const k=s.id||`${s.type}:${s.name}:${s.lat.toFixed(5)}:${s.lon.toFixed(5)}`;
    m.set(k,s);
  }
  return[...m.values()];
}
function schoolNeighbors(seed,maxM=900){
  return schools.filter(s=>distanceMeters(
    {lat:seed.lat,lon:seed.lon},{lat:s.lat,lon:s.lon}
  )<=maxM);
}
function originZoneKeySet(){
  return new Set(originZoneList().map(s=>s.id||`${s.lat},${s.lon}`));
}
function blockedForRoute(r,existing=[]){
  const originKeys=originZoneKeySet();
  let out=[...existing];
  for(const h of schoolHitInfos(r)){
    const candidates=[h.s,...schoolNeighbors(h.s,850)];
    for(const s of candidates){
      const k=s.id||`${s.lat},${s.lon}`;
      if(originKeys.has(k)&&!r.__providerOriginEscaped)continue;
      out.push(s);
    }
  }
  return uniqueSchools(out).slice(0,42);
}
function circleRing(s,radius=VALIDATION_RADIUS_M+5,steps=14){
  const coords=[];
  const dLat=radius/110540;
  const dLon=radius/Math.max(20000,111320*Math.cos(s.lat*Math.PI/180));
  for(let i=0;i<=steps;i++){
    const a=2*Math.PI*i/steps;
    coords.push([
      +(s.lon+dLon*Math.cos(a)).toFixed(7),
      +(s.lat+dLat*Math.sin(a)).toFixed(7)
    ]);
  }
  return coords;
}
function graphHopperCustomModel(blocked){
  const features=[];
  const priority=[];
  blocked.forEach((s,i)=>{
    const id='sz'+i;
    features.push({
      type:'Feature',
      id,
      properties:{},
      geometry:{type:'Polygon',coordinates:[circleRing(s)]}
    });
    priority.push({if:`in_${id}`,multiply_by:0});
  });
  return{
    priority,
    areas:{type:'FeatureCollection',features}
  };
}
function parseGraphHopper(data){
  const p=data.paths?.[0];
  if(!p)throw Error(data.message||'GraphHopper returned no path');
  let coords=null;
  if(p.points?.type==='LineString')coords=p.points.coordinates;
  else if(Array.isArray(p.points?.coordinates))coords=p.points.coordinates;
  if(!coords?.length)throw Error('GraphHopper route geometry missing');
  return{
    geometry:{type:'LineString',coordinates:coords.map(x=>[+x[0],+x[1]])},
    distance:+p.distance||0,
    duration:(+p.time||0)/1000,
    instructions:p.instructions||[],
    provider:'GraphHopper'
  };
}
async function graphHopperRoute(a,b,blocked,key){
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),18000);
  try{
    const resp=await fetch('https://graphhopper.com/api/1/route?key='+encodeURIComponent(key),{
      method:'POST',
      headers:{'Content-Type':'application/json','Accept':'application/json'},
      body:JSON.stringify({
        points:[[a.lon,a.lat],[b.lon,b.lat]],
        profile:'car',
        points_encoded:false,
        instructions:true,
        calc_points:true,
        custom_model:graphHopperCustomModel(blocked)
      }),
      signal:controller.signal
    });
    const text=await resp.text();
    let data={};
    try{data=JSON.parse(text)}catch(_){}
    if(!resp.ok){
      const msg=data.message||text.slice(0,220)||('HTTP '+resp.status);
      throw Error(`GraphHopper HTTP ${resp.status}: ${msg}`);
    }
    return parseGraphHopper(data);
  }catch(e){
    if(e.name==='AbortError')throw Error('GraphHopper timed out');
    if(/Failed to fetch/i.test(e.message))throw Error('GraphHopper request blocked or unavailable');
    throw e;
  }finally{clearTimeout(timer)}
}
function parseORS(data){
  const f=data.features?.[0];
  if(!f?.geometry?.coordinates?.length)throw Error(data.error?.message||'ORS returned no route');
  const s=f.properties?.summary||{};
  return{
    geometry:{type:'LineString',coordinates:f.geometry.coordinates.map(x=>[+x[0],+x[1]])},
    distance:+s.distance||0,
    duration:+s.duration||0,
    provider:'openrouteservice'
  };
}
function bboxKm(list){
  if(!list.length)return{w:0,h:0};
  let x1=Infinity,x2=-Infinity,y1=Infinity,y2=-Infinity;
  for(const s of list){x1=Math.min(x1,s.lon);x2=Math.max(x2,s.lon);y1=Math.min(y1,s.lat);y2=Math.max(y2,s.lat)}
  const mid=(y1+y2)/2;
  return{
    w:(x2-x1)*111*Math.cos(mid*Math.PI/180),
    h:(y2-y1)*111
  };
}
async function orsRoute(a,b,blocked,key){
  const ext=bboxKm(blocked);
  if(ext.w>19||ext.h>19)throw Error('ORS avoid-area extent exceeds the public 20 km limit');
  const geom={
    type:'MultiPolygon',
    coordinates:blocked.map(s=>[circleRing(s)])
  };
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),18000);
  try{
    const resp=await fetch('https://api.heigit.org/v2/directions/driving-car/geojson',{
      method:'POST',
      headers:{
        'Content-Type':'application/json',
        'Accept':'application/geo+json,application/json',
        'Authorization':key
      },
      body:JSON.stringify({
        coordinates:[[a.lon,a.lat],[b.lon,b.lat]],
        instructions:true,
        options:{avoid_polygons:geom}
      }),
      signal:controller.signal
    });
    const text=await resp.text();
    let data={};
    try{data=JSON.parse(text)}catch(_){}
    if(!resp.ok){
      const msg=data.error?.message||data.message||text.slice(0,220)||('HTTP '+resp.status);
      throw Error(`ORS HTTP ${resp.status}: ${msg}`);
    }
    return parseORS(data);
  }catch(e){
    if(e.name==='AbortError')throw Error('openrouteservice timed out');
    if(/Failed to fetch/i.test(e.message))throw Error('openrouteservice request blocked or unavailable');
    throw e;
  }finally{clearTimeout(timer)}
}

function prepareProviderOrigin(seed,a){
  const oz=originZoneList();
  if(!oz.length)return{providerOrigin:a,prefix:null,originZones:[]};

  const c=seed.geometry.coordinates;
  let idx=-1;
  for(let i=1;i<c.length;i++){
    const p={lon:c[i][0],lat:c[i][1]};
    if(oz.every(s=>distanceMeters(p,{lat:s.lat,lon:s.lon})>VALIDATION_RADIUS_M+35)){
      idx=i;break;
    }
  }
  if(idx<0)throw Error('Could not find a road exit from the starting school zone');

  const prefixCoords=c.slice(0,idx+1);
  let prefixDistance=0;
  for(let i=0;i<prefixCoords.length-1;i++){
    prefixDistance+=distanceMeters(
      {lon:prefixCoords[i][0],lat:prefixCoords[i][1]},
      {lon:prefixCoords[i+1][0],lat:prefixCoords[i+1][1]}
    );
  }
  const ratio=seed.distance?Math.min(1,prefixDistance/seed.distance):0;
  return{
    providerOrigin:{lon:c[idx][0],lat:c[idx][1],label:'School-zone exit'},
    prefix:{
      geometry:{type:'LineString',coordinates:prefixCoords},
      distance:prefixDistance,
      duration:(seed.duration||0)*ratio
    },
    originZones:oz
  };
}
function stitchPrefix(prefix,r){
  if(!prefix)return r;
  const a=prefix.geometry.coordinates.slice();
  const b=r.geometry.coordinates.slice();
  if(a.length&&b.length){
    const p=a[a.length-1],q=b[0];
    if(Math.abs(p[0]-q[0])<1e-5&&Math.abs(p[1]-q[1])<1e-5)b.shift();
  }
  return{
    ...r,
    geometry:{type:'LineString',coordinates:[...a,...b]},
    distance:(prefix.distance||0)+(r.distance||0),
    duration:(prefix.duration||0)+(r.duration||0)
  };
}
async function mergeSchoolsForRoute(r){
  try{
    const extra=await loadSchools(r);
    schools=uniqueSchools([...schools,...extra]);
  }catch(e){console.warn('Additional school lookup unavailable',e)}
}
async function providerAttempt(provider,a,b,blocked,keys){
  routingDiagnostics.attempts++;
  if(provider==='GraphHopper'){
    routingDiagnostics.provider='GraphHopper';
    return graphHopperRoute(a,b,blocked,keys.graphhopper);
  }
  routingDiagnostics.provider='openrouteservice';
  return orsRoute(a,b,blocked,keys.ors);
}
async function strictProviderRoute(a,b,seed,keys){
  const prepared=prepareProviderOrigin(seed,a);
  const providerOrigin=prepared.providerOrigin;
  let blocked=blockedForRoute(seed);
  blocked=uniqueSchools([...blocked,...prepared.originZones]).slice(0,42);

  const providers=[];
  if(keys.graphhopper)providers.push('GraphHopper');
  if(keys.ors)providers.push('ORS');
  if(!providers.length){
    showApiSettings?.();
    throw Error('A GraphHopper or OpenRouteService API key is required for strict school avoidance');
  }

  let errors=[];
  for(const provider of providers){
    let currentBlocked=[...blocked];
    for(let pass=0;pass<4;pass++){
      progress(
        55+pass*8,
        provider==='GraphHopper'?'GraphHopper school-safe routing':'ORS fallback routing',
        `${currentBlocked.length} blocked school area${currentBlocked.length===1?'':'s'} · pass ${pass+1}/4`
      );
      try{
        let r=await providerAttempt(provider,providerOrigin,b,currentBlocked,keys);
        r=stitchPrefix(prepared.prefix,r);
        r.__providerOriginEscaped=!!prepared.prefix;
        await mergeSchoolsForRoute(r);
        const hits=schoolHitInfos(r);
        if(!hits.length){
          routingDiagnostics.detail=`${provider} returned a route that passed independent validation`;
          return r;
        }
        const before=currentBlocked.length;
        currentBlocked=blockedForRoute(r,currentBlocked);
        currentBlocked=uniqueSchools([...currentBlocked,...prepared.originZones]).slice(0,42);
        if(currentBlocked.length===before){
          errors.push(`${provider}: ${hits.length} school conflict${hits.length===1?'':'s'} remained`);
          break;
        }
      }catch(e){
        errors.push(`${provider}: ${e.message}`);
        break;
      }
    }
  }
  throw Error(errors.join(' · ')||'Routing providers returned no validated route');
}
function routePointAlongCandidate(s,bearingDeg,radiusM){
  const dLat=radiusM/110540;
  const dLon=radiusM/Math.max(20000,111320*Math.cos(s.lat*Math.PI/180));
  const a=bearingDeg*Math.PI/180;
  return{lon:s.lon+dLon*Math.sin(a),lat:s.lat+dLat*Math.cos(a)};
}
function bearingDegrees(a,b){
  const p1=a.lat*Math.PI/180,p2=b.lat*Math.PI/180,dl=(b.lon-a.lon)*Math.PI/180;
  const y=Math.sin(dl)*Math.cos(p2);
  const x=Math.cos(p1)*Math.sin(p2)-Math.sin(p1)*Math.cos(p2)*Math.cos(dl);
  return(Math.atan2(y,x)*180/Math.PI+360)%360;
}
function chooseBlockingSchools(seed,b){
  const hits=schoolHitInfos(seed);
  const list=[];
  for(const h of hits.slice().reverse())list.push(h.s);
  const near=schools.slice().sort((x,y)=>
    distanceMeters(b,{lat:x.lat,lon:x.lon})-distanceMeters(b,{lat:y.lat,lon:y.lon})
  ).slice(0,5);
  return uniqueSchools([...list,...near]).slice(0,6);
}
async function safeStopFallback(a,b,seed,keys){
  const blockers=chooseBlockingSchools(seed,b);
  if(!blockers.length)return null;

  progress(88,'Finding nearest safe stop','Testing reachable road points just outside the red zone');
  let best=null;
  const maxRequests=10;
  let requests=0;

  for(const s of blockers){
    const toward=bearingDegrees({lat:s.lat,lon:s.lon},b);
    const angles=[toward,toward+25,toward-25,toward+55,toward-55,toward+90,toward-90,toward+180];
    const radii=[VALIDATION_RADIUS_M+20,VALIDATION_RADIUS_M+45];

    for(const radius of radii){
      for(const angle of angles){
        if(requests>=maxRequests)break;
        const p=routePointAlongCandidate(s,(angle+360)%360,radius);

        if(schools.some(x=>distanceMeters(p,{lat:x.lat,lon:x.lon})<=VALIDATION_RADIUS_M+8))continue;

        try{
          const baseline=await route(a,p,[],true);
          await mergeSchoolsForRoute(baseline[0]);
          let r=null;
          for(const br of baseline){
            if(!schoolHitInfos(br).length){r=br;break}
          }
          if(!r){
            requests++;
            r=await strictProviderRoute(a,p,baseline[0],keys);
          }
          if(r&&schoolHitInfos(r).length===0){
            const end=r.geometry.coordinates[r.geometry.coordinates.length-1];
            const actualEnd={lon:end[0],lat:end[1]};
            const toDest=distanceMeters(actualEnd,b);
            const circleClearance=distanceMeters(actualEnd,{lat:s.lat,lon:s.lon})-VALIDATION_RADIUS_M;
            const score=toDest+Math.max(0,circleClearance)*0.12;
            const cand={r,point:actualEnd,school:s.name,toDest,score};
            if(!best||cand.score<best.score)best=cand;
          }
        }catch(e){
          console.warn('Safe stop candidate failed',e);
        }
      }
      if(requests>=maxRequests)break;
    }
    if(requests>=maxRequests)break;
  }

  if(!best)return null;
  best.r._safeStop={
    original:b,
    point:best.point,
    school:best.school,
    distanceToDestination:best.toDest
  };
  return best.r;
}

async function avoidRoute(a,b,alternatives){
  routingDiagnostics={provider:'',detail:'',attempts:0,originZones:originZoneList().length};

  if(!$('avoid').checked){
    const r=alternatives.slice().sort((x,y)=>x.duration-y.duration)[0];
    return{r,n:0};
  }

  const sorted=alternatives.slice().sort((x,y)=>x.duration-y.duration);
  for(const r of sorted){
    if(!schoolHitInfos(r).length){
      routingDiagnostics.provider='OSRM';
      routingDiagnostics.detail='Normal route already passed school-zone validation';
      return{r,n:0};
    }
  }

  const keys=getRoutingApiKeys?.()||{graphhopper:'',ors:''};
  if(!keys.graphhopper&&!keys.ors){
    showApiSettings?.();
    return{
      r:null,
      n:schoolHitInfos(sorted[0]).length,
      diagnostic:'Routing API key required. Add a GraphHopper key (recommended) or ORS key in Routing API Settings.',
      needsApiKey:true
    };
  }

  let providerError='';
  try{
    const r=await strictProviderRoute(a,b,sorted[0],keys);
    if(r&&!schoolHitInfos(r).length)return{r,n:0};
  }catch(e){
    providerError=e.message;
    routingDiagnostics.detail=e.message;
  }

  try{
    const safe=await safeStopFallback(a,b,sorted[0],keys);
    if(safe&&!schoolHitInfos(safe).length){
      routingDiagnostics.detail=(providerError?providerError+' · ':'')+'Safe-stop fallback succeeded';
      return{r:safe,n:0,safeStop:true};
    }
  }catch(e){
    routingDiagnostics.detail=(providerError?providerError+' · ':'')+'Safe stop failed: '+e.message;
  }

  return{
    r:null,
    n:Math.max(1,schoolHitInfos(sorted[0]).length),
    diagnostic:routingDiagnostics.detail||providerError||'No validated route or reachable safe stop was found'
  };
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
      color:'#D93025',weight:2.5,
      fillColor:'#EA4335',fillOpacity:.13
    }).bindPopup('<b>'+s.name+'</b><br>1,000 ft school exclusion zone').addTo(schoolLayer);
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

  const end=r._safeStop?r._safeStop.point:b;
  L.marker([end.lat,end.lon]).bindPopup(
    r._safeStop
      ?'<b>SAFE STOP</b><br>Closest validated reachable point outside a school zone.'
      :'Destination'
  ).addTo(markerLayer);

  map.fitBounds(ll,{padding:[40,40]});
  drawSchools(r);
}
function miles(m){return(m/1609.344).toFixed(1)+' mi'}
function time(s){
  const m=Math.round(s/60);
  return m<60?m+' min':Math.floor(m/60)+'h '+m%60+'m';
}
