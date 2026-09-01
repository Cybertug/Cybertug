function schoolZoneRadiusMeters(s){
  try{const z=zone(s),c=turf.centroid(z),coords=turf.coordAll(z);let mx=0;for(const p of coords)mx=Math.max(mx,turf.distance(c,turf.point(p),{units:'kilometers'})*1000);return Math.max(R,mx)}catch(_){return R}
}
function detourChain(s,route,side,extra=0){
  const z=zone(s),center=turf.centroid(z),line=turf.lineString(route.geometry.coordinates);const snap=turf.nearestPointOnLine(line,center,{units:'kilometers'});const loc=+snap.properties.location||0,len=turf.length(line,{units:'kilometers'});const before=turf.along(line,Math.max(0,loc-.45),{units:'kilometers'});const after=turf.along(line,Math.min(len,loc+.45),{units:'kilometers'});let br=turf.bearing(before,after);if(!Number.isFinite(br))br=0;const d=schoolZoneRadiusMeters(s)+260+extra;const bearings=[br+180+side*35,br+side*90,br+side*35];return bearings.map(x=>{const p=turf.destination(center,d/1000,x,{units:'kilometers'}).geometry.coordinates;return{lon:p[0],lat:p[1]}})
}
async function strict(a,b){
  let rs=await routes(a,b,true);let clean=rs.filter(r=>!avoidableHits(r,a,b).length).sort((x,y)=>x.duration-y.duration);if(clean.length)return clean[0];let best=rs.sort((x,y)=>avoidableHits(x,a,b).length-avoidableHits(y,a,b).length||x.duration-y.duration)[0],wps=[];
  for(let pass=0;pass<7;pass++){const h=avoidableHits(best,a,b);if(!h.length)return best;const target=h[0],attempts=[];for(const side of[1,-1])for(const extra of[0,250,500]){const chain=detourChain(target,best,side,extra);attempts.push(routes(a,b,false,[...wps,...chain]).then(x=>({r:x[0],chain,n:avoidableHits(x[0],a,b).length})))}const settled=await Promise.allSettled(attempts),cand=settled.filter(x=>x.status==='fulfilled').map(x=>x.value);if(!cand.length)break;cand.sort((x,y)=>x.n-y.n||x.r.duration-y.r.duration);const win=cand[0];if(win.n<h.length){wps.push(...win.chain);best=win.r}else break}
  return avoidableHits(best,a,b).length?null:best
}
function drawR(r,a,b){rl.clearLayers();ml.clearLayers();const ll=r.geometry.coordinates.map(c=>[c[1],c[0]]);L.polyline(ll,{color:'#111827',weight:6}).addTo(rl);L.marker([a.lat,a.lon]).bindPopup('Start').addTo(ml);L.marker([b.lat,b.lon]).bindPopup('Destination').addTo(ml);if(!googleActive)map.fitBounds(ll,{padding:[30,30]});drawGoogleRoute(r,a,b)}
function fmtMiles(m){const u=routeOptions().units,metric=u==='km'||(u==='auto'&&!/^en-US/i.test(navigator.language||'en-US'));return metric?(m/1000).toFixed(1)+' km':(m/1609.344).toFixed(1)+' mi'}
function fmtTime(sec){const m=Math.round(sec/60);return m<60?m+' min':Math.floor(m/60)+'h '+m%60+'m'}
function eta(sec){return new Date(Date.now()+sec*1000).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})}
function openNav(){if(!AR)return;$('panel').style.display='none';$('summary').style.display='none';$('nav').style.display='block';$('next').textContent='Follow highlighted route';$('nd').textContent='Press Start GPS for live position.';$('eta').textContent=eta(AR.duration);$('remain').textContent=fmtMiles(AR.distance);$('traveltime').textContent=fmtTime(AR.duration)}
