/* v11.5 hotfix: allow a trip that begins inside a school circle to EXIT that circle once. After the first exit, re-entry is still forbidden. */
(function installOriginEscapeHotfix(){
  if(typeof schoolHitInfos!=='function'||typeof initialBlocked!=='function'||typeof distanceMeters!=='function'||typeof pointToSegmentMeters!=='function'){
    setTimeout(installOriginEscapeHotfix,100);return;
  }
  if(window.__originEscapeHotfixInstalled)return;
  window.__originEscapeHotfixInstalled=true;

  function originInside(s){
    return !!(activeOrigin&&Number.isFinite(activeOrigin.lat)&&Number.isFinite(activeOrigin.lon)&&distanceMeters(activeOrigin,{lat:s.lat,lon:s.lon})<=VALIDATION_RADIUS_M);
  }
  function touches(s,a,b){
    return pointToSegmentMeters(s.lon,s.lat,a[0],a[1],b[0],b[1])<=VALIDATION_RADIUS_M;
  }
  function violation(r,s){
    const c=r.geometry.coordinates;if(c.length<2)return null;
    if(originInside(s)){
      let firstOutside=-1;
      for(let i=0;i<c.length;i++){
        const p={lon:c[i][0],lat:c[i][1]};
        if(distanceMeters(p,{lat:s.lat,lon:s.lon})>VALIDATION_RADIUS_M+12){firstOutside=i;break;}
      }
      if(firstOutside<0)return {s,segmentIndex:0,reason:'origin-zone-never-exited'};
      for(let i=Math.max(0,firstOutside-1);i<c.length-1;i++){
        if(i===firstOutside-1)continue;
        if(touches(s,c[i],c[i+1]))return {s,segmentIndex:i,reason:'origin-zone-reentry'};
      }
      return null;
    }
    for(let i=0;i<c.length-1;i++)if(touches(s,c[i],c[i+1]))return {s,segmentIndex:i,reason:'intersection'};
    return null;
  }

  schoolHitInfos=function(r){
    if(!r)return[];
    const b=routeBoundsFast(r),padLat=VALIDATION_RADIUS_M/110540,padLon=VALIDATION_RADIUS_M/Math.max(20000,metersPerLon((b.minLat+b.maxLat)/2));
    const hits=[];
    for(const s of schools){
      if(s.lon<b.minLon-padLon||s.lon>b.maxLon+padLon||s.lat<b.minLat-padLat||s.lat>b.maxLat+padLat)continue;
      const v=violation(r,s);if(v)hits.push(v);
    }
    hits.sort((a,b)=>a.segmentIndex-b.segmentIndex);return hits;
  };

  hitList=function(r){if(!$('avoid').checked||!r)return[];return schoolHitInfos(r).map(x=>x.s)};

  initialBlocked=function(route){
    const originIds=new Set(schools.filter(originInside).map(s=>s.id));
    let blocked=[];
    for(const h of schoolHitInfos(route)){
      if(originIds.has(h.s.id))continue;
      blocked.push(h.s);
      blocked.push(...schoolNeighbors(h.s,schools,1000).filter(s=>!originIds.has(s.id)));
    }
    return uniqueSchools(blocked).slice(0,55);
  };

  const observer=new MutationObserver(()=>{
    try{
      if(AR&&$('sum').style.display!=='none'){
        const n=schools.filter(originInside).length;
        if(n&&!AR._safeApproach)$('sumSub').innerHTML='<span class="valid">Validated · exited starting school zone and did not re-enter</span>';
      }
    }catch(_){}
  });
  observer.observe(document.body,{subtree:true,attributes:true,attributeFilter:['style']});
})();
