/* v10.1 STRICT school-zone routing.
   A route is valid only when its geometry has ZERO intersections
   with every mapped 1,000 ft school buffer. */

function hitList(r){
  if(!$('avoid').checked || !r) return [];
  const line=turf.lineString(r.geometry.coordinates);
  return schools.filter(s=>{
    try{return turf.booleanIntersects(line,zone(s))}
    catch(_){return false}
  });
}

function orderedHits(r){
  const line=turf.lineString(r.geometry.coordinates);
  return hitList(r).map(s=>{
    let loc=0;
    try{
      loc=+turf.nearestPointOnLine(
        line,turf.point([s.lon,s.lat]),{units:'kilometers'}
      ).properties.location||0;
    }catch(_){}
    return{s,loc};
  }).sort((a,b)=>a.loc-b.loc);
}

function cluster(r){
  const h=orderedHits(r);
  if(!h.length)return null;

  const first=h[0].loc;
  const grp=h.filter(x=>x.loc-first<1.0);

  const lat=grp.reduce((a,x)=>a+x.s.lat,0)/grp.length;
  const lon=grp.reduce((a,x)=>a+x.s.lon,0)/grp.length;
  const center=turf.point([lon,lat]);

  let radius=R;
  for(const x of grp){
    radius=Math.max(
      radius,
      turf.distance(center,turf.point([x.s.lon,x.s.lat]),{units:'kilometers'})*1000+R
    );
  }

  return{
    center,
    radius,
    start:first,
    end:grp[grp.length-1].loc,
    count:grp.length,
    schools:grp.map(x=>x.s)
  };
}

function addUniquePattern(out,seen,pts){
  const key=pts.map(p=>p.lon.toFixed(5)+','+p.lat.toFixed(5)).join('|');
  if(seen.has(key))return;
  seen.add(key);
  out.push(pts);
}

function candidateWaypoints(cl,r,pass){
  const line=turf.lineString(r.geometry.coordinates);
  const len=turf.length(line,{units:'kilometers'});
  const before=turf.along(line,Math.max(0,cl.start-.55),{units:'kilometers'});
  const after=turf.along(line,Math.min(len,cl.end+.55),{units:'kilometers'});

  let heading=turf.bearing(before,after);
  if(!Number.isFinite(heading))heading=0;

  const out=[],seen=new Set();

  const margins = pass < 2 ? [360,600] :
                  pass < 5 ? [500,800,1100] :
                             [700,1050,1450,1850];

  for(const side of [1,-1]){
    for(const margin of margins){
      const d=(cl.radius+margin)/1000;

      const bearings=[
        heading+side*135,
        heading+side*90,
        heading+side*45
      ];

      const chain=bearings.map(br=>{
        const p=turf.destination(cl.center,d,br,{units:'kilometers'}).geometry.coordinates;
        return{lon:p[0],lat:p[1]};
      });
      addUniquePattern(out,seen,chain);

      if(pass>=2){
        const wide=[150,120,90,60,30].map(angle=>{
          const p=turf.destination(
            cl.center,
            (cl.radius+margin+220)/1000,
            heading+side*angle,
            {units:'kilometers'}
          ).geometry.coordinates;
          return{lon:p[0],lat:p[1]};
        });
        addUniquePattern(out,seen,wide);
      }
    }
  }

  if(cl.count===1 && cl.schools[0].anchors){
    const s=cl.schools[0];
    for(const side of [1,-1]){
      const desired=[heading+side*135,heading+side*90,heading+side*45];
      const chain=[];
      for(const d of desired){
        let best=null,err=999;
        for(const a of s.anchors){
          const delta=Math.abs((((a.bearing-d)%360)+540)%360-180);
          if(delta<err){err=delta;best=a}
        }
        if(best)chain.push({lon:best.lon,lat:best.lat});
      }
      if(chain.length>=2)addUniquePattern(out,seen,chain);
    }
  }

  return out.slice(0,18);
}

function candidateScore(c){
  const n=hitList(c.r).length;
  return n*1e10+(c.r.duration||0)+c.wps.length*15;
}

async function avoidRoute(a,b,alternatives){
  if(!$('avoid').checked){
    const r=alternatives.slice().sort((x,y)=>x.duration-y.duration)[0];
    return{r,n:0};
  }

  let seeds=alternatives.map(r=>({r,wps:[]}));
  seeds.sort((x,y)=>candidateScore(x)-candidateScore(y));

  for(const seed of seeds){
    if(hitList(seed.r).length===0)return{r:seed.r,n:0};
  }

  for(let pass=0;pass<11;pass++){
    seeds.sort((x,y)=>candidateScore(x)-candidateScore(y));
    const active=seeds.slice(0,Math.min(4,seeds.length));

    const bestHits=hitList(active[0].r);
    progress(
      Math.min(92,55+pass*3.4),
      'Avoiding school zones',
      bestHits.length+' intersection'+(bestHits.length===1?'':'s')+
      ' · strict pass '+(pass+1)+'/11'
    );

    const jobs=[];

    for(const seed of active){
      const cl=cluster(seed.r);
      if(!cl)continue;

      const patterns=candidateWaypoints(cl,seed.r,pass);
      for(const extra of patterns){
        const w=[...seed.wps,...extra];
        if(w.length>55)continue;

        jobs.push(
          route(a,b,w,false)
            .then(rs=>({r:rs[0],wps:w}))
        );
      }
    }

    if(!jobs.length)break;

    const done=await Promise.allSettled(jobs);
    const next=done
      .filter(x=>x.status==='fulfilled')
      .map(x=>x.value);

    if(!next.length)break;

    const clean=next
      .filter(c=>hitList(c.r).length===0)
      .sort((x,y)=>x.r.duration-y.r.duration);

    if(clean.length)return{r:clean[0].r,n:0};

    next.sort((x,y)=>candidateScore(x)-candidateScore(y));
    seeds=next.slice(0,6);
  }

  return{r:null,n:hitList(seeds[0]?.r).length||1};
}

function drawSchools(r){
  schoolLayer.clearLayers();
  if(!r)return;

  const line=turf.lineString(r.geometry.coordinates);

  for(const s of schools){
    let d=999;
    try{
      d=turf.pointToLineDistance(
        turf.point([s.lon,s.lat]),
        line,
        {units:'kilometers'}
      );
    }catch(_){}

    if(d>1.35)continue;

    L.geoJSON(zone(s),{
      style:{
        color:'#d93025',
        weight:2,
        fillColor:'#ea4335',
        fillOpacity:.16
      }
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

  L.polyline(ll,{
    color:'#ffffff',
    weight:15,
    opacity:.98,
    lineCap:'round',
    lineJoin:'round'
  }).addTo(routeLayer);

  L.polyline(ll,{
    color:'#0057FF',
    weight:9,
    opacity:1,
    lineCap:'round',
    lineJoin:'round'
  }).addTo(routeLayer);

  L.circleMarker([a.lat,a.lon],{
    radius:8,
    color:'#fff',
    weight:3,
    fillColor:'#0057FF',
    fillOpacity:1
  }).addTo(markerLayer);

  L.marker([b.lat,b.lon]).addTo(markerLayer);

  map.fitBounds(ll,{padding:[38,38]});
  drawSchools(r);
}

function miles(m){return(m/1609.344).toFixed(1)+' mi'}
function time(s){
  const m=Math.round(s/60);
  return m<60?m+' min':Math.floor(m/60)+'h '+m%60+'m'
}
