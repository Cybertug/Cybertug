/* School Zone GPS v10.2 PERFORMANCE + STRICT
   - No Turf polygon intersection in routing loop.
   - Uses fast line-to-circle distance math against the exact same
     1,000 ft radius drawn by Leaflet.
   - Small batches of route candidates + browser yielding.
   - Never returns a route with a school-zone crossing as valid.
*/

const VALIDATION_RADIUS_M = 304.8;
const routeHitCache = new WeakMap();

function yieldBrowser(){
  return new Promise(resolve=>{
    if(typeof requestAnimationFrame==='function'){
      requestAnimationFrame(()=>setTimeout(resolve,0));
    }else{
      setTimeout(resolve,0);
    }
  });
}

function metersPerLon(lat){
  return 111320*Math.cos(lat*Math.PI/180);
}

function pointToSegmentMeters(sLon,sLat,aLon,aLat,bLon,bLat){
  const mx=metersPerLon(sLat);
  const my=110540;

  const ax=(aLon-sLon)*mx;
  const ay=(aLat-sLat)*my;
  const bx=(bLon-sLon)*mx;
  const by=(bLat-sLat)*my;

  const vx=bx-ax,vy=by-ay;
  const vv=vx*vx+vy*vy;

  if(vv<0.000001)return Math.hypot(ax,ay);

  let t=-(ax*vx+ay*vy)/vv;
  if(t<0)t=0;
  else if(t>1)t=1;

  const x=ax+t*vx;
  const y=ay+t*vy;
  return Math.hypot(x,y);
}

function routeBoundsFast(r){
  if(r.__fastBounds)return r.__fastBounds;
  const c=r.geometry.coordinates;
  let minLon=Infinity,maxLon=-Infinity,minLat=Infinity,maxLat=-Infinity;
  for(let i=0;i<c.length;i++){
    const p=c[i];
    if(p[0]<minLon)minLon=p[0];
    if(p[0]>maxLon)maxLon=p[0];
    if(p[1]<minLat)minLat=p[1];
    if(p[1]>maxLat)maxLat=p[1];
  }
  const b={minLon,maxLon,minLat,maxLat};
  try{Object.defineProperty(r,'__fastBounds',{value:b,enumerable:false})}catch(_){}
  return b;
}

function schoolHitInfos(r){
  const cached=routeHitCache.get(r);
  if(cached && cached.schoolsRef===schools)return cached.hits;

  const coords=r.geometry.coordinates;
  const b=routeBoundsFast(r);
  const padLat=VALIDATION_RADIUS_M/110540;
  const midLat=(b.minLat+b.maxLat)/2;
  const padLon=VALIDATION_RADIUS_M/Math.max(20000,metersPerLon(midLat));

  const hits=[];

  for(let si=0;si<schools.length;si++){
    const s=schools[si];

    if(
      s.lon<b.minLon-padLon || s.lon>b.maxLon+padLon ||
      s.lat<b.minLat-padLat || s.lat>b.maxLat+padLat
    ) continue;

    let hitSegment=-1;
    let minDist=Infinity;

    for(let i=0;i<coords.length-1;i++){
      const a=coords[i],d=coords[i+1];

      const segPadLon=padLon,segPadLat=padLat;
      if(
        s.lon<Math.min(a[0],d[0])-segPadLon ||
        s.lon>Math.max(a[0],d[0])+segPadLon ||
        s.lat<Math.min(a[1],d[1])-segPadLat ||
        s.lat>Math.max(a[1],d[1])+segPadLat
      ) continue;

      const dist=pointToSegmentMeters(
        s.lon,s.lat,a[0],a[1],d[0],d[1]
      );

      if(dist<minDist)minDist=dist;

      if(dist<=VALIDATION_RADIUS_M){
        hitSegment=i;
        minDist=dist;
        break;
      }
    }

    if(hitSegment>=0){
      hits.push({s,segmentIndex:hitSegment,distance:minDist});
    }
  }

  hits.sort((x,y)=>x.segmentIndex-y.segmentIndex);
  routeHitCache.set(r,{schoolsRef:schools,hits});
  return hits;
}

function hitList(r){
  if(!$('avoid').checked || !r)return[];
  return schoolHitInfos(r).map(x=>x.s);
}

function orderedHits(r){
  return schoolHitInfos(r).map(x=>({
    s:x.s,
    loc:x.segmentIndex,
    segmentIndex:x.segmentIndex,
    distance:x.distance
  }));
}

function haversineMeters(aLon,aLat,bLon,bLat){
  const R0=6371000;
  const p1=aLat*Math.PI/180,p2=bLat*Math.PI/180;
  const dp=(bLat-aLat)*Math.PI/180;
  const dl=(bLon-aLon)*Math.PI/180;
  const h=Math.sin(dp/2)**2+
    Math.cos(p1)*Math.cos(p2)*Math.sin(dl/2)**2;
  return 2*R0*Math.asin(Math.min(1,Math.sqrt(h)));
}

function bearingFast(a,b){
  const p1=a[1]*Math.PI/180,p2=b[1]*Math.PI/180;
  const dl=(b[0]-a[0])*Math.PI/180;
  const y=Math.sin(dl)*Math.cos(p2);
  const x=Math.cos(p1)*Math.sin(p2)-
    Math.sin(p1)*Math.cos(p2)*Math.cos(dl);
  return Math.atan2(y,x)*180/Math.PI;
}

function destinationFast(lon,lat,distM,bearingDeg){
  const R0=6371000;
  const br=bearingDeg*Math.PI/180;
  const p1=lat*Math.PI/180;
  const l1=lon*Math.PI/180;
  const ad=distM/R0;

  const p2=Math.asin(
    Math.sin(p1)*Math.cos(ad)+
    Math.cos(p1)*Math.sin(ad)*Math.cos(br)
  );

  const l2=l1+Math.atan2(
    Math.sin(br)*Math.sin(ad)*Math.cos(p1),
    Math.cos(ad)-Math.sin(p1)*Math.sin(p2)
  );

  return{
    lon:l2*180/Math.PI,
    lat:p2*180/Math.PI
  };
}

function conflictCluster(r){
  const h=schoolHitInfos(r);
  if(!h.length)return null;

  const first=h[0];
  const group=[first];

  for(let i=1;i<h.length;i++){
    const d=haversineMeters(
      first.s.lon,first.s.lat,h[i].s.lon,h[i].s.lat
    );
    if(d<=1350)group.push(h[i]);
  }

  const lat=group.reduce((a,x)=>a+x.s.lat,0)/group.length;
  const lon=group.reduce((a,x)=>a+x.s.lon,0)/group.length;

  let radius=VALIDATION_RADIUS_M;
  for(const x of group){
    radius=Math.max(
      radius,
      haversineMeters(lon,lat,x.s.lon,x.s.lat)+VALIDATION_RADIUS_M
    );
  }

  return{
    lon,lat,radius,
    segmentIndex:first.segmentIndex,
    schools:group.map(x=>x.s)
  };
}

function detourPatterns(r,cl,pass){
  const c=r.geometry.coordinates;
  const i=cl.segmentIndex;

  const before=c[Math.max(0,i-6)];
  const after=c[Math.min(c.length-1,i+7)];
  let heading=bearingFast(before,after);
  if(!Number.isFinite(heading))heading=0;

  const margins=pass<2?[380,700]:
                pass<4?[550,950]:
                       [750,1200,1650];

  const patterns=[];

  for(const side of [1,-1]){
    for(const margin of margins){
      const radius=cl.radius+margin;

      const arc=[135,90,45].map(angle=>
        destinationFast(
          cl.lon,cl.lat,radius,
          heading+side*angle
        )
      );
      patterns.push(arc);
    }
  }

  if(cl.schools.length===1 && cl.schools[0].anchors){
    const s=cl.schools[0];
    for(const side of [1,-1]){
      const wanted=[heading+side*135,heading+side*90,heading+side*45];
      const chain=[];

      for(const target of wanted){
        let best=null,bestDelta=999;
        for(const a of s.anchors){
          let delta=Math.abs((((a.bearing-target)%360)+540)%360-180);
          if(delta<bestDelta){bestDelta=delta;best=a}
        }
        if(best)chain.push({lon:best.lon,lat:best.lat});
      }

      if(chain.length===3)patterns.push(chain);
    }
  }

  const seen=new Set(),out=[];
  for(const p of patterns){
    const key=p.map(x=>x.lon.toFixed(4)+','+x.lat.toFixed(4)).join('|');
    if(seen.has(key))continue;
    seen.add(key);
    out.push(p);
    if(out.length>=6)break;
  }
  return out;
}

function scoreRouteCandidate(c){
  const conflicts=schoolHitInfos(c.r).length;
  return conflicts*1e9+(c.r.duration||0)+c.wps.length*8;
}

async function routeCandidatesInSmallBatches(a,b,baseWps,patterns){
  const results=[];

  for(let i=0;i<patterns.length;i+=2){
    const batch=patterns.slice(i,i+2);

    const settled=await Promise.allSettled(
      batch.map(extra=>{
        const wps=[...baseWps,...extra];
        return route(a,b,wps,false)
          .then(rs=>({r:rs[0],wps}));
      })
    );

    for(const x of settled){
      if(x.status==='fulfilled')results.push(x.value);
    }

    await yieldBrowser();
  }

  return results;
}

async function avoidRoute(a,b,alternatives){
  if(!$('avoid').checked){
    const r=alternatives.slice().sort((x,y)=>x.duration-y.duration)[0];
    return{r,n:0};
  }

  let current=null;
  for(const r of alternatives){
    await yieldBrowser();
    const n=schoolHitInfos(r).length;
    if(n===0)return{r,n:0};

    const c={r,wps:[]};
    if(!current || scoreRouteCandidate(c)<scoreRouteCandidate(current)){
      current=c;
    }
  }

  for(let pass=0;pass<7;pass++){
    await yieldBrowser();

    const conflicts=schoolHitInfos(current.r);
    if(!conflicts.length)return{r:current.r,n:0};

    progress(
      58+pass*5,
      'Avoiding school zones',
      conflicts.length+' intersection'+(conflicts.length===1?'':'s')+
      ' · optimized pass '+(pass+1)+'/7'
    );

    const cl=conflictCluster(current.r);
    if(!cl)break;

    const patterns=detourPatterns(current.r,cl,pass);
    const candidates=await routeCandidatesInSmallBatches(
      a,b,current.wps,patterns
    );

    if(!candidates.length)break;

    const clean=[];
    for(const cand of candidates){
      await yieldBrowser();
      if(schoolHitInfos(cand.r).length===0)clean.push(cand);
    }

    if(clean.length){
      clean.sort((x,y)=>x.r.duration-y.r.duration);
      return{r:clean[0].r,n:0};
    }

    candidates.sort((x,y)=>scoreRouteCandidate(x)-scoreRouteCandidate(y));
    const best=candidates[0];
    current=best;
  }

  const n=current?schoolHitInfos(current.r).length:1;
  return{r:null,n:Math.max(1,n)};
}

function drawSchools(r){
  schoolLayer.clearLayers();
  if(!r)return;

  const b=routeBoundsFast(r);
  const padLat=1200/110540;
  const midLat=(b.minLat+b.maxLat)/2;
  const padLon=1200/Math.max(20000,metersPerLon(midLat));

  for(const s of schools){
    if(
      s.lon<b.minLon-padLon || s.lon>b.maxLon+padLon ||
      s.lat<b.minLat-padLat || s.lat>b.maxLat+padLat
    )continue;

    L.circle([s.lat,s.lon],{
      radius:VALIDATION_RADIUS_M,
      color:'#D93025',
      weight:2.5,
      fillColor:'#EA4335',
      fillOpacity:.13
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
    color:'#16213E',
    weight:15,
    opacity:.78,
    lineCap:'round',
    lineJoin:'round'
  }).addTo(routeLayer);

  L.polyline(ll,{
    color:'#FFFFFF',
    weight:11,
    opacity:1,
    lineCap:'round',
    lineJoin:'round'
  }).addTo(routeLayer);

  L.polyline(ll,{
    color:'#006CFF',
    weight:7,
    opacity:1,
    lineCap:'round',
    lineJoin:'round'
  }).addTo(routeLayer);

  L.circleMarker([a.lat,a.lon],{
    radius:8,
    color:'#fff',
    weight:3,
    fillColor:'#006CFF',
    fillOpacity:1
  }).addTo(markerLayer);

  L.marker([b.lat,b.lon]).addTo(markerLayer);

  map.fitBounds(ll,{padding:[40,40]});
  drawSchools(r);
}

function miles(m){return(m/1609.344).toFixed(1)+' mi'}
function time(s){
  const m=Math.round(s/60);
  return m<60?m+' min':Math.floor(m/60)+'h '+m%60+'m'
}
