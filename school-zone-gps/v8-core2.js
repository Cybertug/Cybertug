function decodePolyline6(str){
  let index=0,lat=0,lon=0,out=[];
  while(index<str.length){
    let result=0,shift=0,b;
    do{b=str.charCodeAt(index++)-63;result|=(b&0x1f)<<shift;shift+=5}while(b>=0x20);
    lat+=(result&1)?~(result>>1):(result>>1);
    result=0;shift=0;
    do{b=str.charCodeAt(index++)-63;result|=(b&0x1f)<<shift;shift+=5}while(b>=0x20);
    lon+=(result&1)?~(result>>1):(result>>1);
    out.push([lon/1e6,lat/1e6])
  }
  return out
}
function zoneRings(list){
  const rings=[];
  for(const s of list){
    try{
      let z=zone(s);z=turf.rewind(z,{reverse:false});z=turf.simplify(z,{tolerance:0.00018,highQuality:false});const g=z.geometry;
      const addRing=r=>{if(!r||r.length<4)return;const clean=r.map(p=>[+p[0].toFixed(6),+p[1].toFixed(6)]);const a=clean[0],b=clean[clean.length-1];if(a[0]!==b[0]||a[1]!==b[1])clean.push([...a]);rings.push(clean)};
      if(g.type==='Polygon')addRing(g.coordinates[0]);else if(g.type==='MultiPolygon')g.coordinates.forEach(p=>addRing(p[0]))
    }catch(e){console.warn('Could not build exclusion polygon for',s.name,e)}
  }
  return rings
}
function valhallaToRoute(data){
  const trip=data?.trip;if(!trip||!trip.legs?.length)throw Error(data?.error||data?.error_code||'Valhalla returned no route');let coords=[],maneuvers=[];
  for(const leg of trip.legs){const c=decodePolyline6(leg.shape||'');if(coords.length&&c.length&&coords[coords.length-1][0]===c[0][0]&&coords[coords.length-1][1]===c[0][1])c.shift();coords.push(...c);maneuvers.push(...(leg.maneuvers||[]))}
  return{geometry:{type:'LineString',coordinates:coords},duration:+trip.summary.time||0,distance:(+trip.summary.length||0)*1609.344,maneuvers,provider:'Valhalla'}
}
async function valhallaRoute(a,b,excluded=[],opts=routeOptions()){
  const payload={locations:[{lat:a.lat,lon:a.lon,type:'break'},{lat:b.lat,lon:b.lon,type:'break'}],costing:'auto',units:'miles',language:'en-US',directions_type:'instructions',costing_options:{auto:{use_highways:opts.highways?0:1,use_tolls:opts.tolls?0:1,use_ferry:opts.ferries?0:1}}};
  const rings=zoneRings(excluded);if(rings.length)payload.exclude_polygons=rings;
  const data=await j('https://valhalla1.openstreetmap.de/route',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)},35000);
  if(data?.error_code||data?.error)throw Error(data.error||data.error_code);return valhallaToRoute(data)
}
function schoolKey(s){return s.id||((s.name||'school')+'|'+s.lat.toFixed(5)+'|'+s.lon.toFixed(5))}
async function calculateAvoidingSchools(a,b,pre,opts){
  if(!opts.schools){if(opts.highways||opts.tolls||opts.ferries)return await valhallaRoute(a,b,[],opts);return pre}
  let route=pre;const excluded=new Map();let known=new Map(schools.map(s=>[schoolKey(s),s]));
  for(let pass=0;pass<5;pass++){
    const blocking=avoidableHits(route,a,b);if(!blocking.length)return route;
    for(const s of blocking)excluded.set(schoolKey(s),s);
    setProgress(70+pass*5,'Avoiding schools','Routing around '+excluded.size+' school exclusion zone'+(excluded.size===1?'':'s'));
    try{route=await valhallaRoute(a,b,[...excluded.values()],opts)}catch(e){console.warn('Valhalla exclusion routing failed; trying waypoint fallback',e);route=await strict(a,b);if(!route)throw Error('Routing engine could not find a road path outside the school zones.')}
    const more=await loadRelevantSchools(route);for(const s of more)known.set(schoolKey(s),s);schools=dedupeSchools([...known.values()]);drawS();refreshEndpointExemptions(a,b)
  }
  if(avoidableHits(route,a,b).length)throw Error('No route found that stays outside all detected school exclusion zones.');return route
}
function rb(r,p=2.5){const c=r.geometry.coordinates;let mnx=Infinity,mxx=-Infinity,mny=Infinity,mxy=-Infinity;for(const v of c){mnx=Math.min(mnx,v[0]);mxx=Math.max(mxx,v[0]);mny=Math.min(mny,v[1]);mxy=Math.max(mxy,v[1])}const mid=(mny+mxy)/2,dp=p/111,op=p/(111*Math.max(.2,Math.cos(mid*Math.PI/180)));return[mny-dp,mnx-op,mxy+dp,mxx+op]}
const ARC_PUBLIC_BOUNDS='https://services.arcgis.com/LBbVDC0hKPAnLRpO/arcgis/rest/services/gc_schoolsbnd_jul23/FeatureServer/0/query';
const ARC_PUBLIC_POINTS='https://services1.arcgis.com/Ua5sjt3LWTPigjyD/arcgis/rest/services/Public_School_Locations_Current/FeatureServer/0/query';
const ARC_PRIVATE_POINTS='https://services1.arcgis.com/Ua5sjt3LWTPigjyD/arcgis/rest/services/Private_School_Locations_Current/FeatureServer/0/query';
const POINT_FALLBACK_M=304.8;
async function arcQuery(endpoint,bounds,outFields='NAME'){const[minLat,minLon,maxLat,maxLon]=bounds;const q=new URLSearchParams({where:'1=1',geometry:`${minLon},${minLat},${maxLon},${maxLat}`,geometryType:'esriGeometryEnvelope',inSR:'4326',spatialRel:'esriSpatialRelIntersects',outFields,returnGeometry:'true',outSR:'4326',f:'geojson'});return await j(endpoint+'?'+q.toString(),{},18000)}
function normName(x){return String(x||'').toLowerCase().replace(/[^a-z0-9]/g,'')}
function boundarySchools(fc){const out=[];for(const f of fc?.features||[]){if(!f.geometry||!['Polygon','MultiPolygon'].includes(f.geometry.type))continue;const pr=f.properties||{},hi=String(pr.HIGH_GRADE||'').toUpperCase(),lo=String(pr.LOW_GRADE||'').toUpperCase();if((hi==='N'||hi==='NA'||hi==='N/A')&&(lo==='N'||lo==='NA'||lo==='N/A'))continue;try{const c=turf.centroid(f).geometry.coordinates;out.push({id:'flb:'+String(pr.FID||pr.STATE_ID||out.length),name:pr.NAME||'School',lat:c[1],lon:c[0],g:f,source:'Florida school grounds',radiusM:R})}catch(_){}}return out}
function pointSchools(fc,prefix,source){const out=[];for(const f of fc?.features||[]){if(!f.geometry||f.geometry.type!=='Point')continue;const[lon,lat]=f.geometry.coordinates||[];if(!Number.isFinite(lon)||!Number.isFinite(lat))continue;const pr=f.properties||{};out.push({id:prefix+':'+String(pr.OBJECTID||pr.NCESSCH||pr.PPINST||out.length),name:pr.NAME||'School',lat,lon,g:null,source,radiusM:POINT_FALLBACK_M})}return out}
function dedupeSchools(items){const bounds=items.filter(s=>s.g),points=items.filter(s=>!s.g),out=[...bounds];for(const s of points){let dup=false;const sn=normName(s.name);for(const b of bounds){const bn=normName(b.name);if(sn&&bn&&sn===bn){dup=true;break}try{const d=turf.distance(turf.point([s.lon,s.lat]),turf.point([b.lon,b.lat]),{units:'kilometers'});if(d<0.18){dup=true;break}}catch(_){}}if(!dup)out.push(s)}return out}
async function loadRelevantSchools(route){const b=rb(route,2.4),tasks=[arcQuery(ARC_PUBLIC_BOUNDS,b,'FID,NAME,LOW_GRADE,HIGH_GRADE,STATE_ID'),arcQuery(ARC_PUBLIC_POINTS,b,'OBJECTID,NAME'),arcQuery(ARC_PRIVATE_POINTS,b,'OBJECTID,NAME')];const res=await Promise.allSettled(tasks),ok=res.filter(x=>x.status==='fulfilled');if(!ok.length)throw Error('School databases are temporarily unavailable.');let all=[];if(res[0].status==='fulfilled')all.push(...boundarySchools(res[0].value));if(res[1].status==='fulfilled')all.push(...pointSchools(res[1].value,'pub','NCES public school point'));if(res[2].status==='fulfilled')all.push(...pointSchools(res[2].value,'priv','NCES private school point'));return dedupeSchools(all)}
function zone(s){const src=s.g||turf.point([s.lon,s.lat]),meters=s.g?R:(s.radiusM||POINT_FALLBACK_M);return turf.buffer(src,meters/1000,{units:'kilometers',steps:32})}
function drawS(){sl.clearLayers();schools.forEach(s=>L.geoJSON(zone(s),{style:{color:'#b91c1c',weight:1,fillColor:'#ef4444',fillOpacity:.15}}).bindPopup('<b>'+s.name+'</b><br>'+(s.g?'1,000 ft from mapped school grounds':'1,000 ft approximate point fallback')+'<br><small>'+s.source+'</small>').addTo(sl));drawGoogleSchools()}
function hits(r){const l=turf.lineString(r.geometry.coordinates);return schools.filter(s=>{try{return turf.booleanIntersects(l,zone(s))}catch(_){return false}})}
function det(s,a,b,o,dist){const br=turf.bearing(turf.point([a.lon,a.lat]),turf.point([b.lon,b.lat]))+o;const p=turf.destination(turf.point([s.lon,s.lat]),dist/1000,br,{units:'kilometers'}).geometry.coordinates;return{lon:p[0],lat:p[1]}}
