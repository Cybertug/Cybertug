/* School Zone GPS v11.6
   Native BRouter no-go circles + origin-zone escape handling.
   If the trip STARTS inside a school circle, the route may exit that circle once,
   but after leaving it cannot re-enter. All other school-circle intersections remain forbidden.
*/
const VALIDATION_RADIUS_M=304.8;
const routeHitCache=new WeakMap();
let routingDiagnostics={engine:'',detail:'',originZones:0};

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
function originInsideSchool(s){
  if(!activeOrigin||!Number.isFinite(activeOrigin.lat)||!Number.isFinite(activeOrigin.lon))return false;
  return distanceMeters(activeOrigin,{lat:s.lat,lon:s.lon})<=VALIDATION_RADIUS_M;
}
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
      if(distanceMeters(p,{lat:s.lat,lon:s.lon})>VALIDATION_RADIUS_M+12){firstOutside=i;break;}
    }
    if(firstOutside<0)return {s,segmentIndex:0,distance:0,reason:'origin-zone-never-exited'};
    for(let i=Math.max(0,firstOutside-1);i<c.length-1;i++){
      const a=c[i],b=c[i+1];
      if(i===firstOutside-1)continue;
      if(segmentTouchesSchool(s,a,b))return {s,segmentIndex:i,distance:0,reason:'origin-zone-reentry'};
    }
    return null;
  }
  for(let i=0;i<c.length-1;i++){
    const a=c[i],b=c[i+1];
    if(segmentTouchesSchool(s,a,b))return {s,segmentIndex:i,distance:0,reason:'intersection'};
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
    if(s.lon<b.minLon-padLon||s.lon>b.maxLon+padLon||s.lat<b.minLat-padLat||s.lat>b.maxLat+padLat)continue;
    const v=schoolViolation(r,s);if(v)hits.push(v);
  }
  hits.sort((a,b)=>a.segmentIndex-b.segmentIndex);
  routeHitCache.set(r,{schoolsRef:schools,originRef:activeOrigin,hits});
  return hits;
}
function hitList(r){if(!$('avoid').checked||!r)return[];return schoolHitInfos(r).map(x=>x.s)}
function originZoneList(){return schools.filter(originInsideSchool)}
function uniqueSchools(list){
  const m=new Map();
  for(const s of list){const k=s.id||s.type+':'+s.name+':'+s.lat.toFixed(5)+':'+s.lon.toFixed(5);m.set(k,s)}
  return[...m.values()];
}
function schoolNeighbors(seed,list,maxM=1000){return list.filter(s=>distanceMeters({lat:seed.lat,lon:seed.lon},{lat:s.lat,lon:s.lon})<=maxM)}
function initialBlocked(route){
  const originIds=new Set(originZoneList().map(s=>s.id));
  let blocked=[];
  for(const h of schoolHitInfos(route)){
    if(originIds.has(h.s.id))continue;
    blocked.push(h.s);
    for(const n of schoolNeighbors(h.s,schools,1000)){if(!originIds.has(n.id))blocked.push(n)}
  }
  return uniqueSchools(blocked).slice(0,60);
}
function parseBrouterGeoJson(data){
  const feat=(data.features||[]).find(f=>f.geometry?.type==='LineString');
  if(!feat)throw Error('BRouter returned no LineString route');
  const coords=(feat.geometry.coordinates||[]).map(p=>[+p[0],+p[1]]).filter(p=>Number.isFinite(p[0])&&Number.isFinite(p[1]));
  if(coords.length<2)throw Error('BRouter returned empty route geometry');
  const p=feat.properties||{};
  return{geometry:{type:'LineString',coordinates:coords},distance:Number(p['track-length'])||0,duration:Number(p['total-time'])||0,brouter:true,brouterProperties:p};
}
async function brouterNativeRoute(a,b,blocked,alternativeidx=0){
  const u=new URL('https://brouter.de/brouter');
  u.searchParams.set('lonlats',`${a.lon},${a.lat}|${b.lon},${b.lat}`);
  u.searchParams.set('profile','car-fast');
  u.searchParams.set('alternativeidx',String(alternativeidx));
  u.searchParams.set('format','geojson');
  u.searchParams.set('timode','4');
  if(blocked.length)u.searchParams.set('nogos',blocked.map(s=>`${(+s.lon).toFixed(6)},${(+s.lat).toFixed(6)},${VALIDATION_RADIUS_M.toFixed(1)}`).join('|'));
  routingDiagnostics.engine='BRouter';
  const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),18000);
  try{
    const resp=await fetch(u.toString(),{method:'GET',mode:'cors',headers:{'Accept':'application/json, application/geo+json'},signal:controller.signal});
    if(!resp.ok){let body='';try{body=(await resp.text()).slice(0,220)}catch(_){}throw Error(`BRouter HTTP ${resp.status}${body?' · '+body:''}`)}
    return parseBrouterGeoJson(await resp.json());
  }catch(e){
    if(e.name==='AbortError')throw Error('BRouter timed out');
    if(/Failed to fetch/i.test(e.message))throw Error('BRouter browser request blocked or unavailable');
    throw e;
  }finally{clearTimeout(timer)}
}
async function mergeSchoolsForRoute(r){
  try{const extra=await loadSchools(r);schools=uniqueSchools([...schools,...extra])}catch(e){console.warn('Additional school lookup unavailable',e)}
}
async function brouterAvoid(a,b,seedRoute){
  let blocked=initialBlocked(seedRoute);const originZones=originZoneList();routingDiagnostics.originZones=originZones.length;
  if(!schoolHitInfos(seedRoute).length)return seedRoute;
  let lastError=null;
  for(let pass=0;pass<5;pass++){
    progress(56+pass*7,'Routing around school zones',`${blocked.length} native no-go circle${blocked.length===1?'':'s'}${originZones.length?` · ${originZones.length} origin-zone escape allowed`:''} · pass ${pass+1}/5`);
    try{
      const r=await brouterNativeRoute(a,b,blocked,pass%2);await mergeSchoolsForRoute(r);
      const hits=schoolHitInfos(r);if(!hits.length){routingDiagnostics.detail=`BRouter native no-go routing passed${originZones.length?'; origin-zone exit handled':''}`;return r}
      let added=0;const originIds=new Set(originZoneList().map(s=>s.id));
      for(const h of hits){
        for(const s of [h.s,...schoolNeighbors(h.s,schools,1000)]){
          if(originIds.has(s.id))continue;if(blocked.length>=75)break;
          if(!blocked.some(x=>x.id===s.id)){blocked.push(s);added++}
        }
      }
      if(!added){lastError=Error(`${hits.length} school-zone conflict${hits.length===1?'':'s'} remained after native no-go routing`);break}
    }catch(e){lastError=e;console.warn('BRouter pass failed',e);break}
    await new Promise(r=>setTimeout(r,180));
  }
  if(lastError)throw lastError;return null;
}
function bearing(a,b){
  const p1=a.lat*Math.PI/180,p2=b.lat*Math.PI/180,dl=(b.lon-a.lon)*Math.PI/180;
  const y=Math.sin(dl)*Math.cos(p2);const x=Math.cos(p1)*Math.sin(p2)-Math.sin(p1)*Math.cos(p2)*Math.cos(dl);
  return(Math.atan2(y,x)*180/Math.PI+360)%360;
}
function destinationPoint(lon,lat,distM,bearingDeg){
  const R0=6371000,br=bearingDeg*Math.PI/180,p1=lat*Math.PI/180,l1=lon*Math.PI/180,d=distM/R0;
  const p2=Math.asin(Math.sin(p1)*Math.cos(d)+Math.cos(p1)*Math.sin(d)*Math.cos(br));
  const l2=l1+Math.atan2(Math.sin(br)*Math.sin(d)*Math.cos(p1),Math.cos(d)-Math.sin(p1)*Math.sin(p2));
  return{lon:l2*180/Math.PI,lat:p2*180/Math.PI};
}
async function localFallback(a,b,base){
  let current=base,wps=[];
  for(let pass=0;pass<7;pass++){
    const hits=schoolHitInfos(current);if(!hits.length)return current;const h=hits[0];
    progress(88+pass,'Local fallback',`${hits.length} conflict${hits.length===1?'':'s'} · fallback pass ${pass+1}/7`);
    const c=current.geometry.coordinates,i=h.segmentIndex;
    const pa={lon:c[Math.max(0,i-8)][0],lat:c[Math.max(0,i-8)][1]},pb={lon:c[Math.min(c.length-1,i+10)][0],lat:c[Math.min(c.length-1,i+10)][1]},hd=bearing(pa,pb);
    const candidates=[];
    for(const side of [1,-1]){
      const d=VALIDATION_RADIUS_M+900+pass*350;
      const extra=[135,90,45].map(ang=>destinationPoint(h.s.lon,h.s.lat,d,hd+side*ang));
      try{const rs=await route(a,b,[...wps,...extra],false);if(rs?.[0])candidates.push({r:rs[0],wps:[...wps,...extra]})}catch(_){}
      await new Promise(r=>setTimeout(r,0));
    }
    if(!candidates.length)break;
    candidates.sort((x,y)=>schoolHitInfos(x.r).length-schoolHitInfos(y.r).length||x.r.duration-y.r.duration);
    current=candidates[0].r;wps=candidates[0].wps;
  }
  return schoolHitInfos(current).length?null:current;
}
function destinationConflict(b){
  let nearest=null,d=Infinity;
  for(const s of schools){const x=distanceMeters(b,{lat:s.lat,lon:s.lon});if(x<d){d=x;nearest=s}}
  return nearest&&d<=VALIDATION_RADIUS_M?{s:nearest,d}:null;
}
function safeApproachPoint(a,b,conf){const h=bearing({lat:conf.s.lat,lon:conf.s.lon},a);return destinationPoint(conf.s.lon,conf.s.lat,VALIDATION_RADIUS_M+140,h)}
async function avoidRoute(a,b,alternatives){
  routingDiagnostics={engine:'',detail:'',originZones:0};
  if(!$('avoid').checked){const r=alternatives.slice().sort((x,y)=>x.duration-y.duration)[0];return{r,n:0}}
  const sorted=alternatives.slice().sort((x,y)=>x.duration-y.duration);routingDiagnostics.originZones=originZoneList().length;
  for(const r of sorted){
    if(!schoolHitInfos(r).length){routingDiagnostics.engine='OSRM';routingDiagnostics.detail=routingDiagnostics.originZones?`Normal route valid after exiting ${routingDiagnostics.originZones} origin school zone${routingDiagnostics.originZones===1?'':'s'}`:'Normal route already has zero school-zone crossings';return{r,n:0}}
  }
  const dc=destinationConflict(b);
  if(dc){
    const safe=safeApproachPoint(a,b,dc);const targetAlts=await route(a,safe,[],true);await mergeSchoolsForRoute(targetAlts[0]);
    for(const r of targetAlts){if(!schoolHitInfos(r).length){r._safeApproach={original:b,point:safe,school:dc.s.name};return{r,n:0,safeApproach:true}}}
    try{const br=await brouterAvoid(a,safe,targetAlts[0]);if(br){br._safeApproach={original:b,point:safe,school:dc.s.name};return{r:br,n:0,safeApproach:true}}}catch(e){routingDiagnostics.detail=e.message}
    return{r:null,n:1,destinationBlocked:true,school:dc.s.name,diagnostic:routingDiagnostics.detail};
  }
  let brouterError=null;
  try{const br=await brouterAvoid(a,b,sorted[0]);if(br&&!schoolHitInfos(br).length)return{r:br,n:0}}catch(e){brouterError=e;routingDiagnostics.detail=e.message;console.warn(e)}
  progress(90,'Trying fallback route',brouterError?brouterError.message:'Native no-go route unavailable');
  try{const fallback=await localFallback(a,b,sorted[0]);if(fallback&&!schoolHitInfos(fallback).length){routingDiagnostics.engine='OSRM fallback';routingDiagnostics.detail='BRouter unavailable; local detour fallback passed validation';return{r:fallback,n:0}}}catch(e){routingDiagnostics.detail=(routingDiagnostics.detail?`${routingDiagnostics.detail} · `:'')+e.message}
  return{r:null,n:Math.max(1,schoolHitInfos(sorted[0]).length),diagnostic:routingDiagnostics.detail||'No clean route returned by available routing engines',originZones:routingDiagnostics.originZones};
}
function drawSchools(r){
  schoolLayer.clearLayers();if(!r)return;
  const b=routeBoundsFast(r),padLat=1400/110540,padLon=1400/Math.max(20000,metersPerLon((b.minLat+b.maxLat)/2));
  for(const s of schools){
    if(s.lon<b.minLon-padLon||s.lon>b.maxLon+padLon||s.lat<b.minLat-padLat||s.lat>b.maxLat+padLat)continue;
    L.circle([s.lat,s.lon],{radius:VALIDATION_RADIUS_M,color:'#D93025',weight:2.5,fillColor:'#EA4335',fillOpacity:.13})
      .bindPopup('<b>'+s.name+'</b><br>1,000 ft school zone'+(originInsideSchool(s)?'<br><small>Trip starts inside this zone; exit-only handling is applied.</small>':''))
      .addTo(schoolLayer);
  }
}
function drawRoute(r,a,b){
  routeLayer.clearLayers();markerLayer.clearLayers();if(!r)return;
  const ll=r.geometry.coordinates.map(p=>[p[1],p[0]]);
  L.polyline(ll,{color:'#082d67',weight:16,opacity:.72,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.polyline(ll,{color:'#fff',weight:12,opacity:1,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.polyline(ll,{color:'#0b69ff',weight:8,opacity:1,lineCap:'round',lineJoin:'round'}).addTo(routeLayer);
  L.circleMarker([a.lat,a.lon],{radius:8,color:'#fff',weight:3,fillColor:'#0b69ff',fillOpacity:1}).addTo(markerLayer);
  const end=r._safeApproach?r._safeApproach.point:b;L.marker([end.lat,end.lon]).addTo(markerLayer);
  map.fitBounds(ll,{padding:[40,40]});drawSchools(r);
}
function miles(m){return(m/1609.344).toFixed(1)+' mi'}
function time(s){const m=Math.round(s/60);return m<60?m+' min':Math.floor(m/60)+'h '+m%60+'m'}
