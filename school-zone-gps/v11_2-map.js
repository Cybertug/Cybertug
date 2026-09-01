/* School Zone GPS v11.2 — Google-like vector presentation with automatic raster fallback */
(function(){
  if(!window.maplibregl) throw new Error('MapLibre was not loaded');

  let uid=0, loaded=false, vectorReady=false, fallbackUsed=false;
  const pending=[];
  let deviceHeading=null, smoothedHeading=null, navMarker=null;
  let styleTimer=null;

  function nextId(p){ return 'sz-'+p+'-'+(++uid); }

  const rasterFallback={
    version:8,
    sources:{
      esri:{
        type:'raster',
        tiles:['https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}'],
        tileSize:256,
        attribution:'Tiles © Esri'
      }
    },
    layers:[
      {id:'background',type:'background',paint:{'background-color':'#eef3f7'}},
      {id:'esri',type:'raster',source:'esri'}
    ]
  };

  function polygonCircle(lat,lon,radiusM,steps=56){
    const coords=[],dLat=radiusM/110540;
    const dLon=radiusM/Math.max(20000,111320*Math.cos(lat*Math.PI/180));
    for(let i=0;i<=steps;i++){
      const a=2*Math.PI*i/steps;
      coords.push([lon+dLon*Math.cos(a),lat+dLat*Math.sin(a)]);
    }
    return {type:'Feature',properties:{},geometry:{type:'Polygon',coordinates:[coords]}};
  }

  function safePaint(map,id,prop,val){
    try{ map.setPaintProperty(id,prop,val); }catch(_){}
  }

  function googleLikeTuning(map){
    const style=map.getStyle();
    if(!style?.layers)return;
    for(const layer of style.layers){
      const id=(layer.id||'').toLowerCase();

      if(layer.type==='background') safePaint(map,layer.id,'background-color','#f5f5f2');

      if(layer.type==='fill'){
        if(/water/.test(id)) safePaint(map,layer.id,'fill-color','#b9d8f0');
        else if(/park|grass|wood|forest|green|landcover/.test(id)) safePaint(map,layer.id,'fill-color','#d8ead2');
        else if(/hospital|school|college|university/.test(id)) safePaint(map,layer.id,'fill-color','#f4e7df');
        else if(/industrial/.test(id)) safePaint(map,layer.id,'fill-color','#eee9e5');
        else if(/residential|landuse/.test(id)) safePaint(map,layer.id,'fill-color','#f3f3f1');
        else if(/building/.test(id)) safePaint(map,layer.id,'fill-color','#e8e4df');
      }

      if(layer.type==='line'){
        if(/motorway|freeway|trunk/.test(id)){
          safePaint(map,layer.id,'line-color','#f4b740');
        }else if(/primary/.test(id)){
          safePaint(map,layer.id,'line-color','#f7d98a');
        }else if(/secondary/.test(id)){
          safePaint(map,layer.id,'line-color','#fff1c7');
        }else if(/road|street|minor|tertiary/.test(id)){
          safePaint(map,layer.id,'line-color','#ffffff');
        }
      }

      if(layer.type==='symbol'){
        if(/road|street/.test(id)){
          safePaint(map,layer.id,'text-color','#5f6368');
          safePaint(map,layer.id,'text-halo-color','#ffffff');
          safePaint(map,layer.id,'text-halo-width',1.2);
        }else if(/place|city|town|village|poi/.test(id)){
          safePaint(map,layer.id,'text-color','#3c4043');
          safePaint(map,layer.id,'text-halo-color','#ffffff');
          safePaint(map,layer.id,'text-halo-width',1.1);
        }
      }
    }
  }

  function add3DBuildings(map){
    if(map.getLayer('sz-3d-buildings'))return;
    try{
      const style=map.getStyle();
      const building=style.layers.find(l=>l['source-layer']==='building');
      if(!building)return;
      const before=style.layers.find(l=>l.type==='symbol')?.id;
      map.addLayer({
        id:'sz-3d-buildings',
        type:'fill-extrusion',
        source:building.source,
        'source-layer':'building',
        minzoom:15,
        paint:{
          'fill-extrusion-color':'#ddd9d4',
          'fill-extrusion-height':['coalesce',['get','render_height'],['get','height'],6],
          'fill-extrusion-base':['coalesce',['get','render_min_height'],0],
          'fill-extrusion-opacity':0.78
        }
      },before);
    }catch(e){ console.warn('3D buildings unavailable',e); }
  }

  class Group{
    constructor(){this.items=[]}
    addTo(){return this}
    _add(o){
      this.items.push(o);
      if(loaded)this._render(o);
      else pending.push(()=>this.items.includes(o)&&this._render(o));
    }
    _render(o){
      if(o._rendered)return;
      o._rendered=true;
      const m=window.__szMap;

      if(o.kind==='marker'||o.kind==='circleMarker'){
        let marker;
        if(o.kind==='circleMarker'){
          const el=document.createElement('div'),r=o.options.radius||7;
          Object.assign(el.style,{
            width:(r*2)+'px',height:(r*2)+'px',borderRadius:'50%',
            background:o.options.fillColor||'#1a73e8',
            border:(o.options.weight||2)+'px solid '+(o.options.color||'#fff'),
            boxSizing:'border-box'
          });
          marker=new maplibregl.Marker({element:el,anchor:'center'}).setLngLat([o.lon,o.lat]);
        }else{
          marker=new maplibregl.Marker({color:'#ea4335'}).setLngLat([o.lon,o.lat]);
        }
        if(o.popup)marker.setPopup(new maplibregl.Popup({offset:18}).setHTML(o.popup));
        marker.addTo(m);o._marker=marker;return;
      }

      const sid=nextId('src'),lid=nextId('lyr');
      let data,layer;
      if(o.kind==='polyline'){
        data={type:'Feature',properties:{},geometry:{type:'LineString',coordinates:o.coords.map(p=>[p[1],p[0]])}};
        layer={id:lid,type:'line',source:sid,layout:{'line-cap':'round','line-join':'round'},paint:{
          'line-color':o.options.color||'#1a73e8',
          'line-width':o.options.weight||6,
          'line-opacity':o.options.opacity??1
        }};
      }else if(o.kind==='circle'){
        data=polygonCircle(o.lat,o.lon,o.options.radius||304.8,56);
        layer={id:lid,type:'fill',source:sid,paint:{
          'fill-color':o.options.fillColor||'#ea4335',
          'fill-opacity':o.options.fillOpacity??.13,
          'fill-outline-color':o.options.color||'#d93025'
        }};
      }else if(o.kind==='geojson'){
        data=o.data;
        layer={id:lid,type:'fill',source:sid,paint:{
          'fill-color':o.options.fillColor||'#ea4335',
          'fill-opacity':o.options.fillOpacity??.13,
          'fill-outline-color':o.options.color||'#d93025'
        }};
      }
      if(!data)return;
      try{
        m.addSource(sid,{type:'geojson',data});
        m.addLayer(layer);
        o._sourceId=sid;o._layerId=lid;
      }catch(e){ console.warn('overlay render failed',e); }
    }
    clearLayers(){
      const m=window.__szMap;
      for(const o of this.items){
        try{if(o._marker)o._marker.remove()}catch(_){}
        try{if(o._layerId&&m.getLayer(o._layerId))m.removeLayer(o._layerId)}catch(_){}
        try{if(o._sourceId&&m.getSource(o._sourceId))m.removeSource(o._sourceId)}catch(_){}
      }
      this.items=[];
    }
  }

  function shape(kind,p){
    return Object.assign({
      kind,popup:null,_rendered:false,
      bindPopup(html){this.popup=html;return this},
      addTo(group){group._add(this);return this}
    },p);
  }

  function completeLoad(map){
    if(loaded)return;
    loaded=true;
    clearTimeout(styleTimer);
    while(pending.length){
      try{pending.shift()()}catch(e){console.warn(e)}
    }
  }

  function activateFallback(map){
    if(fallbackUsed)return;
    fallbackUsed=true;
    vectorReady=false;
    window.__SZ_MAP_MODE='stable';
    try{map.setStyle(rasterFallback)}catch(e){console.warn(e)}
  }

  window.L={
    map(id){
      const map=new maplibregl.Map({
        container:id,
        style:'https://tiles.openfreemap.org/styles/bright',
        center:[-82.46,27.95],
        zoom:10,
        pitch:0,
        bearing:0,
        maxPitch:70,
        attributionControl:true,
        antialias:true
      });
      window.__szMap=map;
      window.__SZ_MAP_MODE='vector';

      map.addControl(new maplibregl.NavigationControl({
        showCompass:true,showZoom:true,visualizePitch:true
      }),'top-right');

      styleTimer=setTimeout(()=>{
        if(!loaded){
          console.warn('Vector style timed out; falling back to raster.');
          activateFallback(map);
        }
      },6500);

      map.on('style.load',()=>{
        if(!fallbackUsed){
          vectorReady=true;
          window.__SZ_MAP_MODE='vector';
          googleLikeTuning(map);
          add3DBuildings(map);
        }
        completeLoad(map);
      });

      map.on('error',e=>{
        console.warn('Map error',e?.error||e);
        if(!loaded)activateFallback(map);
      });

      map.setView=function(latlng,zoom){
        map.easeTo({center:[latlng[1],latlng[0]],zoom:zoom??map.getZoom(),duration:260});
        return map;
      };

      const nativeFit=map.fitBounds.bind(map);
      map.fitBounds=function(points,opts={}){
        if(window.__navFollowing)return map;
        const b=new maplibregl.LngLatBounds();
        for(const p of points)b.extend([p[1],p[0]]);
        nativeFit(b,{
          padding:Array.isArray(opts.padding)?opts.padding[0]:(opts.padding||40),
          duration:450,
          maxZoom:15.5
        });
        return map;
      };
      return map;
    },
    tileLayer(){return{addTo(){return this},on(){return this}}},
    layerGroup(){return new Group()},
    polyline(coords,options={}){return shape('polyline',{coords,options})},
    circle(latlng,options={}){return shape('circle',{lat:latlng[0],lon:latlng[1],options})},
    circleMarker(latlng,options={}){return shape('circleMarker',{lat:latlng[0],lon:latlng[1],options})},
    marker(latlng,options={}){return shape('marker',{lat:latlng[0],lon:latlng[1],options})},
    geoJSON(data,options={}){return shape('geojson',{data,options:options.style||options})}
  };

  function norm(x){x%=360;if(x<0)x+=360;return x}
  function smooth(target){
    target=norm(target);
    if(smoothedHeading==null){smoothedHeading=target;return target}
    const d=((target-smoothedHeading+540)%360)-180;
    smoothedHeading=norm(smoothedHeading+d*.2);
    return smoothedHeading;
  }

  window.__requestHeadingPermission=async function(){
    try{
      if(typeof DeviceOrientationEvent!=='undefined'&&typeof DeviceOrientationEvent.requestPermission==='function'){
        const r=await DeviceOrientationEvent.requestPermission();
        if(r!=='granted')return false;
      }
      const handler=e=>{
        let h=null;
        if(Number.isFinite(e.webkitCompassHeading))h=e.webkitCompassHeading;
        else if(e.absolute&&Number.isFinite(e.alpha)){
          const angle=screen.orientation&&Number.isFinite(screen.orientation.angle)?screen.orientation.angle:0;
          h=norm(360-e.alpha+angle);
        }
        if(h!=null){
          deviceHeading=smooth(h);
          if(window.__navFollowing&&window.__lastNavPos){
            window.__updateNavCamera(
              window.__lastNavPos.lat,window.__lastNavPos.lon,
              deviceHeading,window.__lastNavPos.speed,true
            );
          }
        }
      };
      window.addEventListener('deviceorientationabsolute',handler,true);
      window.addEventListener('deviceorientation',handler,true);
      return true;
    }catch(e){console.warn('heading permission failed',e);return false}
  };

  window.__setNavMarker=function(lon,lat,heading=0){
    const m=window.__szMap;
    if(!navMarker){
      const el=document.createElement('div');
      el.className='navArrow';
      el.innerHTML='<div class="navArrowInner"></div>';
      navMarker=new maplibregl.Marker({
        element:el,anchor:'center',rotationAlignment:'map'
      }).setLngLat([lon,lat]).addTo(m);
    }
    navMarker.setLngLat([lon,lat]);
    try{navMarker.setRotation(heading||0)}catch(_){}
  };

  window.__updateNavCamera=function(lat,lon,heading,speed=0,fromCompass=false){
    const m=window.__szMap;
    window.__lastNavPos={lat,lon,speed};
    const chosen=Number.isFinite(deviceHeading)
      ?deviceHeading
      :(Number.isFinite(heading)?smooth(heading):m.getBearing());
    const zoom=speed>27?15.7:speed>16?16.2:speed>8?16.8:speed>3?17.4:18.1;
    const pitch=window.__SZ_MAP_MODE==='vector'?(speed>2?60:54):0;

    window.__setNavMarker(lon,lat,chosen);
    m.easeTo({
      center:[lon,lat],
      zoom,pitch,
      bearing:window.__SZ_MAP_MODE==='vector'?chosen:0,
      padding:{top:130,bottom:300,left:24,right:24},
      duration:fromCompass?160:360,
      essential:true
    });
  };

  window.__enterNavVisual=function(){
    window.__navFollowing=true;
    document.body.classList.add('navMode');
    try{
      window.__szMap.easeTo({
        pitch:window.__SZ_MAP_MODE==='vector'?60:0,
        zoom:17.3,
        duration:380
      });
    }catch(_){}
  };

  window.__exitNavVisual=function(){
    window.__navFollowing=false;
    document.body.classList.remove('navMode');
    try{window.__szMap.easeTo({pitch:0,bearing:0,duration:350})}catch(_){}
  };
})();