$('go').onclick=async()=>{
  const oq=$('o').value.trim(),dq=$('d').value.trim();
  if(!dq)return stat('Enter a destination. The start can use your current GPS location.','warn');
  $('go').disabled=true;$('summary').style.display='none';$('nav').style.display='none';resetProgressColor();startProgress();
  try{
    setProgress(8,'Resolving addresses','Checking origin and destination');
    const a=(!oq||oq==='Current location')?await getGpsPosition():await resolve(oq,SO),b=await resolve(dq,SD);SO=a;AD=b;if(!oq||oq==='Current location')$('o').value='Current location';
    setProgress(20,'Calculating preliminary route','Finding the fastest normal route');
    const pre=(await routes(a,b,true)).sort((x,y)=>x.duration-y.duration)[0];
    setProgress(38,'Loading school databases','Florida school grounds + current NCES public/private schools');
    schools=await loadRelevantSchools(pre);drawS();refreshEndpointExemptions(a,b);
    setProgress(60,'Building exclusion zones',schools.length+' nearby schools loaded');
    const opts=routeOptions();
    setProgress(68,opts.schools?'Calculating Avoid Schools route':'Calculating route',opts.schools?'School zones will be blocked inside the routing engine':'Applying selected route preferences');
    let r=await calculateAvoidingSchools(a,b,pre,opts);
    setProgress(91,'Final validation','Checking the selected road path against school zones');
    const more=opts.schools?await loadRelevantSchools(r):[],m=new Map();[...schools,...more].forEach(s=>m.set(schoolKey(s),s));schools=dedupeSchools([...m.values()]);drawS();refreshEndpointExemptions(a,b);
    if(opts.schools&&avoidableHits(r,a,b).length){setProgress(94,'Final school reroute','New school zones were detected around the detour');r=await calculateAvoidingSchools(a,b,r,opts);if(avoidableHits(r,a,b).length)throw Error('Could not validate a route outside all detected school zones.')}
    setProgress(98,'Drawing route','Preparing navigation view');AR=r;drawR(r,a,b);
    $('sumMain').textContent=fmtTime(r.duration)+' · '+fmtMiles(r.distance);
    $('sumSub').textContent=(routeOptions().schools?'Avoid Schools ON · ':'')+'validated against '+schools.length+' nearby school zone'+(schools.length===1?'':'s')+((startExemptKeys.size||destExemptKeys.size)?' · start/end zone exception applied':'');
    $('summary').style.display='block';endProgress(true);stat('Route ready. Navigation view opened.','ok');setTimeout(openNav,350)
  }catch(e){console.error(e);failProgress(e.message||String(e));stat('Could not calculate route: '+(e.message||String(e)),'warn')}
  finally{$('go').disabled=false}
};
async function rerouteFromGps(lat,lon){
  if(isRerouting||!AD||Date.now()-lastGpsReroute<18000)return;isRerouting=true;lastGpsReroute=Date.now();const here={lat,lon,label:'Current location'};SO=here;
  try{stat('Off route — recalculating from your current GPS location…','warn');const pre=(await routes(here,AD,true)).sort((x,y)=>x.duration-y.duration)[0];schools=await loadRelevantSchools(pre);drawS();refreshEndpointExemptions(here,AD);const r=await calculateAvoidingSchools(here,AD,pre,routeOptions());if(!r)throw Error('No school-safe reroute found.');AR=r;drawR(r,here,AD);$('eta').textContent=eta(r.duration);$('remain').textContent=fmtMiles(r.distance);$('traveltime').textContent=fmtTime(r.duration);stat('Route recalculated from your current location.','ok')}
  catch(e){stat('Reroute failed: '+(e.message||String(e)),'warn')}finally{isRerouting=false}
}
$('myLoc').onclick=()=>useMyLocation();$('googleEnable').onclick=()=>enableGoogle();
const savedGoogleKey=localStorage.getItem('schoolGpsGoogleKey');if(savedGoogleKey){$('googleKey').value=savedGoogleKey;$('googleStatus').textContent='Saved Google Maps key found. Press Enable Google to activate it.'}
$('optBtn').onclick=()=>{$('optionsPanel').style.display=$('optionsPanel').style.display==='block'?'none':'block'};
$('sw').onclick=()=>{let x=$('o').value;$('o').value=$('d').value;$('d').value=x;let q=SO;SO=SD;SD=q};
$('navb').onclick=openNav;
$('exit').onclick=()=>{$('nav').style.display='none';$('panel').style.display='block';$('summary').style.display=AR?'block':'none';if(W!==null){navigator.geolocation.clearWatch(W);W=null;$('gps').textContent='Start GPS'}};
$('gps').onclick=()=>{
  if(!navigator.geolocation)return stat('GPS unavailable in this browser.','warn');if(W!==null)return;$('gps').textContent='GPS Active';
  W=navigator.geolocation.watchPosition(p=>{const a=p.coords.latitude,b=p.coords.longitude,acc=p.coords.accuracy||0;currentPos={lat:a,lon:b,label:'Current location',accuracy:acc};SO=currentPos;gl.clearLayers();L.circleMarker([a,b],{radius:8,color:'#1d4ed8',fillColor:'#3b82f6',fillOpacity:1,weight:3}).addTo(gl);if(acc)L.circle([a,b],{radius:acc,color:'#60a5fa',weight:1,fillOpacity:.05}).addTo(gl);drawGoogleGps(a,b,acc);setMapView(a,b,16);const off=routeOffDistanceMeters(a,b);if(Number.isFinite(off)&&off>120)rerouteFromGps(a,b)},e=>{stat('GPS error: '+e.message,'warn');$('gps').textContent='Start GPS';W=null},{enableHighAccuracy:true,maximumAge:2000,timeout:15000})
};
