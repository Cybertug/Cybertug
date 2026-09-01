/* School Zone GPS v13 routing patch.
   ORS public avoid_polygons has a 20 km height/width restriction. v12 sent school
   polygons from the entire trip in one request, so long Florida trips failed.

   v13 keeps the baseline route, repairs one local school conflict at a time, and
   sends ORS only the school polygons around that conflict. The complete stitched
   route is independently revalidated after every repair. */
(function(){
  function point(c){return{lon:c[0],lat:c[1]}}
  function segDistance(c,i,j){
    let d=0;
    i=Math.max(0,i);j=Math.min(c.length-1,j);
    for(let k=i;k<j;k++)d+=distanceMeters(point(c[k]),point(c[k+1]));
    return d;
  }
  function routeDistance(c){return segDistance(c,0,c.length-1)}
  function indexBack(c,from,meters){
    let d=0,i=Math.max(0,Math.min(c.length-1,from));
    while(i>0&&d<meters){d+=distanceMeters(point(c[i]),point(c[i-1]));i--}
    return i;
  }
  function indexForward(c,from,meters){
    let d=0,i=Math.max(0,Math.min(c.length-1,from));
    while(i<c.length-1&&d<meters){d+=distanceMeters(point(c[i]),point(c[i+1]));i++}
    return i;
  }
  function clearOf(c,list,margin=70){
    const p=point(c);
    return list.every(s=>distanceMeters(p,{lat:s.lat,lon:s.lon})>VALIDATION_RADIUS_M+margin);
  }
  function trimLocalCluster(seed,radius){
    let list=uniqueSchools([seed,...schoolNeighbors(seed,radius)]);
    list.sort((a,b)=>distanceMeters({lat:seed.lat,lon:seed.lon},{lat:a.lat,lon:a.lon})-
                     distanceMeters({lat:seed.lat,lon:seed.lon},{lat:b.lat,lon:b.lon}));
    list=list.slice(0,28);
    while(list.length>1){
      const ext=bboxKm(list);
      if(ext.w<=17.5&&ext.h<=17.5)break;
      list.pop();
    }
    return list;
  }
  function destinationInsideSchool(b){
    return schools.find(s=>distanceMeters(b,{lat:s.lat,lon:s.lon})<=VALIDATION_RADIUS_M+5)||null;
  }
  function replaceSection(current,i0,i1,detour){
    const old=current.geometry.coordinates;
    let mid=detour.geometry.coordinates.slice();
    if(mid.length&&old[i0]){
      const a=mid[0],b=old[i0];
      if(Math.abs(a[0]-b[0])<1e-5&&Math.abs(a[1]-b[1])<1e-5)mid.shift();
    }
    const coords=[...old.slice(0,i0+1),...mid,...old.slice(i1+1)];
    const oldSection=segDistance(old,i0,i1);
    const oldTotal=Number.isFinite(current.distance)&&current.distance>0?current.distance:routeDistance(old);
    const newSection=Number.isFinite(detour.distance)&&detour.distance>0?detour.distance:routeDistance(detour.geometry.coordinates);
    const newTotal=Math.max(1,oldTotal-oldSection+newSection);
    const secondsPerMeter=Number.isFinite(current.duration)&&current.duration>0&&oldTotal>0?current.duration/oldTotal:0.07;
    const oldSectionSeconds=oldSection*secondsPerMeter;
    const newDuration=Math.max(1,(current.duration||oldTotal*secondsPerMeter)-oldSectionSeconds+(detour.duration||newSection*secondsPerMeter));
    return{
      ...current,
      geometry:{type:'LineString',coordinates:coords},
      distance:newTotal,
      duration:newDuration,
      provider:'openrouteservice · local school detours'
    };
  }
  function schoolKey(s){return s.id||`${s.type||''}:${s.name||''}:${(+s.lat).toFixed(5)}:${(+s.lon).toFixed(5)}`}

  window.strictProviderRoute=async function(a,b,seed,keys){
    const key=(keys?.ors||getRoutingApiKeys?.().ors||'').trim();
    if(!key){
      showApiSettings?.();
      throw Error('OpenRouteService API key is required');
    }

    routingDiagnostics.provider='openrouteservice';
    routingDiagnostics.attempts=0;

    let current={
      ...seed,
      geometry:{type:'LineString',coordinates:seed.geometry.coordinates.map(p=>[+p[0],+p[1]])},
      provider:'baseline + ORS local detours'
    };
    await mergeSchoolsForRoute(current);

    const destBlock=destinationInsideSchool(b);
    if(destBlock){
      throw Error(`Destination is inside the 1,000 ft zone for ${destBlock.name}; searching for a Safe Stop`);
    }

    const attemptsBySchool=new Map();
    const MAX_REPAIRS=20;

    for(let pass=0;pass<MAX_REPAIRS;pass++){
      const hits=schoolHitInfos(current);
      if(!hits.length){
        routingDiagnostics.detail=`ORS local-detour routing passed independent validation after ${pass} repair${pass===1?'':'s'}`;
        return current;
      }

      const hit=hits[0],s=hit.s,k=schoolKey(s);
      const tries=(attemptsBySchool.get(k)||0)+1;
      attemptsBySchool.set(k,tries);
      if(tries>3)throw Error(`Could not create a clean road detour around ${s.name}`);

      const c=current.geometry.coordinates;
      const flank=Math.min(4300,1700+(tries-1)*1100);
      const localRadius=Math.min(6500,3600+(tries-1)*1200);
      const cluster=trimLocalCluster(s,localRadius);

      let i0=indexBack(c,Math.max(0,hit.segmentIndex),flank);
      let i1=indexForward(c,Math.min(c.length-1,hit.segmentIndex+1),flank);

      while(i0>0&&!clearOf(c[i0],cluster,90))i0--;
      while(i1<c.length-1&&!clearOf(c[i1],cluster,90))i1++;

      if(i0>=i1)throw Error(`Could not isolate a local detour around ${s.name}`);
      if(i1===c.length-1&&!clearOf(c[i1],cluster,5)){
        throw Error(`Destination cannot be reached without entering the zone for ${s.name}; searching for a Safe Stop`);
      }

      const start=point(c[i0]),end=point(c[i1]);
      routingDiagnostics.attempts++;
      progress(
        Math.min(86,56+pass*2),
        'ORS school-zone detour',
        `${s.name} · local repair ${pass+1} · ${cluster.length} nearby school zone${cluster.length===1?'':'s'}`
      );

      let detour;
      try{
        detour=await orsRoute(start,end,cluster,key);
      }catch(e){
        throw Error(`ORS local detour failed near ${s.name}: ${e.message}`);
      }

      current=replaceSection(current,i0,i1,detour);
      await mergeSchoolsForRoute(current);

      /* Independent validation decides whether the next pass is needed. */
      const remaining=schoolHitInfos(current);
      if(!remaining.length){
        routingDiagnostics.detail=`ORS repaired ${pass+1} school conflict${pass===0?'':'s'} and the full route passed validation`;
        return current;
      }
    }

    const left=schoolHitInfos(current);
    throw Error(`ORS reached the local-detour safety limit with ${left.length} school conflict${left.length===1?'':'s'} remaining`);
  };
})();