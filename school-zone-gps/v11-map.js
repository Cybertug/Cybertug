/* School Zone GPS v11 — MapLibre visual/navigation engine */
(function(){
  let uid=0;
  const groups=[];
  const pending=[];
  let loaded=false;
  let navMarker=null;
  let deviceHeading=null;
  let smoothedHeading=null;

  function nextId(prefix){return 'sz-'+prefix+'-'+(++uid)}
  function circleGeo(lat,lon,radiusM,steps=48){
    const coords=[];
    const latRad=lat*Math.PI/180;
    const dLat=radiusM/110540;
    const dLon=radiusM/Math.max(20000,111320*Math.cos(latRad));
    for(let i=0;i<=steps;i++){
      const a=2*Math.PI*i/steps;
      coords.push([lon+dLon*Math.cos(a),lat+dLat*Math.sin(a)]);
    }
    return {type:'Feature',properties:{},geometry:{type:'Polygon',coordinates:[coords]}};
  }

  function add3DBuildings(map){
    if(map.getLayer('sz-3d-buildings'))return;
    try{
      const style=map.getStyle();
      const buildingLayer=style.layers.find(l=>l['source-layer']==='building');
      if(!buildingLayer)return;
      const firstSymbol=style.layers.find(l=>l.type==='symbol');
      map.addLayer({
        id:'sz-3d-buildings',type:'fill-extrusion',source:buildingLayer.source,
        'source-layer':'building',minzoom:15,
        paint:{
          'fill-extrusion-color':'#d9d9d9',
          'fill-extrusion-height':['coalesce',['get','render_height'],['get','height'],6],
          'fill-extrusion-base':['coalesce',['get','render_min_height'],0],
          'fill-extrusion-opacity':0.72
        }
      },firstSymbol?firstSymbol.id:undefined);
    }catch(e){console.warn('3D buildings unavailable',e)}
  }

  class CompatGroup{
    constructor(){this.items=[];groups.push(this)}
    addTo(){return this}
    _add(obj){
      this.items.push(obj);
      if(loaded)this._render(obj); else pending.push(()=>this.items.includes(obj)&&this._render(obj));
    }
    _render(obj){
      if(obj._rendered)return;
      obj._rendered=true;
      if(obj.kind==='marker'||obj.kind==='circleMarker'){
        let marker;
        if(obj.kind==='circleMarker'){
          const el=document.createElement('div');
          const r=obj.options.radius||7;
          Object.assign(el.style,{width:(r*2)+'px',height:(r*2)+'px',borderRadius:'50%',background:obj.options.fillColor||'#006cff',border:(obj.options.weight||2)+'px solid '+(obj.options.color||'#fff'),boxSizing:'border-box'});
          marker=new maplibregl.Marker({element:el,anchor:'center'}).setLngLat([obj.lon,obj.lat]);
        }else{
          marker=new maplibregl.Marker({color:'#d93025'}).setLngLat([obj.lon,obj.lat]);
        }
        if(obj.popup)marker.setPopup(new maplibregl.Popup({offset:18}).setHTML(obj.popup));
        marker.addTo(window.__szMap);obj._marker=marker;return;
      }
      const sourceId=nextId('src'),layerId=nextId('lyr');
      let data,layer;
      if(obj.kind==='polyline'){
        data={type:'Feature',properties:{},geometry:{type:'LineString',coordinates:obj.coords.map(p=>[p[1],p[0]])}};
        layer={id:layerId,type:'line',source:sourceId,layout:{'line-cap':'round','line-join':'round'},paint:{'line-color':obj.options.color||'#006cff','line-width':obj.options.weight||6,'line-opacity':obj.options.opacity??1}};
      }else if(obj.kind==='circle'){
        data=circleGeo(obj.lat,obj.lon,obj.options.radius||304.8,56);
        layer={id:layerId,type:'fill',source:sourceId,paint:{'fill-color':obj.options.fillColor||'#ea4335','fill-opacity':obj.options.fillOpacity??.13,'fill-outline-color':obj.options.color||'#d93025'}};
      }else if(obj.kind==='geojson'){
        data=obj.data;
        layer={id:layerId,type:'fill',source:sourceId,paint:{'fill-color':obj.options.fillColor||'#ea4335','fill-opacity':obj.options.fillOpacity??.13,'fill-outline-color':obj.options.color||'#d93025'}};
      }
      if(!data)return;
      window.__szMap.addSource(sourceId,{type:'geojson',data});
      window.__szMap.addLayer(layer);
      if(obj.popup){
        const handler=e=>new maplibregl.Popup().setLngLat(e.lngLat).setHTML(obj.popup).addTo(window.__szMap);
        window.__szMap.on('click',layerId,handler);obj._handler=handler;
      }
      obj._sourceId=sourceId;obj._layerId=layerId;
    }
    clearLayers(){
      for(const obj of this.items){
        try{if(obj._marker)obj._marker.remove()}catch(_){}
        try{if(obj._handler&&obj._layerId)window.__szMap.off('click',obj._layerId,obj._handler)}catch(_){}
        try{if(obj._layerId&&window.__szMap.getLayer(obj._layerId))window.__szMap.removeLayer(obj._layerId)}catch(_){}
        try{if(obj._sourceId&&window.__szMap.getSource(obj._sourceId))window.__szMap.removeSource(obj._sourceId)}catch(_){}
      }
      this.items=[];
    }
  }

  function shape(kind,props){
    return Object.assign({kind,popup:null,_rendered:false,
      bindPopup(html){this.popup=html;return this},
      addTo(group){group._add(this);return this}
    },props);
  }

  window.L={
    map(id){
      const map=new maplibregl.Map({
        container:id,style:'https://tiles.openfreemap.org/styles/liberty',
        center:[-82.46,27.95],zoom:10,pitch:0,bearing:0,
        attributionControl:true,maxPitch:75,antialias:true
      });
      window.__szMap=map;
      map.addControl(new maplibregl.NavigationControl({showCompass:true,showZoom:true,visualizePitch:true}),'top-right');
      map.on('load',()=>{loaded=true;add3DBuildings(map);while(pending.length){try{pending.shift()()}catch(e){console.warn(e)}}});
      map.setView=function(latlng,zoom){map.easeTo({center:[latlng[1],latlng[0]],zoom:zoom??map.getZoom(),duration:350});return map};
      const nativeFit=map.fitBounds.bind(map);
      map.fitBounds=function(points,opts={}){
        if(window.__navFollowing)return map;
        const b=new maplibregl.LngLatBounds();
        for(const p of points)b.extend([p[1],p[0]]);
        nativeFit(b,{padding:Array.isArray(opts.padding)?opts.padding[0]:(opts.padding||40),duration:550,maxZoom:15});return map;
      };
      return map;
    },
    tileLayer(){return{addTo(){return this}}},
    layerGroup(){return new CompatGroup()},
    polyline(coords,options={}){return shape('polyline',{coords,options})},
    circle(latlng,options={}){return shape('circle',{lat:latlng[0],lon:latlng[1],options})},
    circleMarker(latlng,options={}){return shape('circleMarker',{lat:latlng[0],lon:latlng[1],options})},
    marker(latlng,options={}){return shape('marker',{lat:latlng[0],lon:latlng[1],options})},
    geoJSON(data,options={}){return shape('geojson',{data,options:options.style||options})}
  };

  function normalizeHeading(x){x%=360;if(x<0)x+=360;return x}
  function smoothHeading(target){
    target=normalizeHeading(target);
    if(smoothedHeading==null){smoothedHeading=target;return target}
    let d=((target-smoothedHeading+540)%360)-180;
    smoothedHeading=normalizeHeading(smoothedHeading+d*.24);
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
          const angle=(screen.orientation&&Number.isFinite(screen.orientation.angle))?screen.orientation.angle:0;
          h=normalizeHeading(360-e.alpha+angle);
        }
        if(h!=null){deviceHeading=smoothHeading(h);if(window.__navFollowing&&window.__lastNavPos)window.__updateNavCamera(window.__lastNavPos.lat,window.__lastNavPos.lon,deviceHeading,window.__lastNavPos.speed,true)}
      };
      window.addEventListener('deviceorientationabsolute',handler,true);
      window.addEventListener('deviceorientation',handler,true);
      return true;
    }catch(e){console.warn('Heading permission',e);return false}
  };

  function routeHeadingFallback(lat,lon){
    try{
      if(!window.AR||!window.AR.geometry)return null;
      const c=window.AR.geometry.coordinates;let best=0,bestD=Infinity;
      const mx=111320*Math.cos(lat*Math.PI/180),my=110540;
      for(let i=0;i<c.length-1;i++){
        const dx=(c[i][0]-lon)*mx,dy=(c[i][1]-lat)*my,d=dx*dx+dy*dy;
        if(d<bestD){bestD=d;best=i}
      }
      const a=c[best],b=c[Math.min(c.length-1,best+3)];
      const p1=a[1]*Math.PI/180,p2=b[1]*Math.PI/180,dl=(b[0]-a[0])*Math.PI/180;
      const y=Math.sin(dl)*Math.cos(p2),x=Math.cos(p1)*Math.sin(p2)-Math.sin(p1)*Math.cos(p2)*Math.cos(dl);
      return normalizeHeading(Math.atan2(y,x)*180/Math.PI);
    }catch(_){return null}
  }

  window.__updateNavCamera=function(lat,lon,gpsHeading,speed,orientationOnly=false){
    const map=window.__szMap;if(!map||!window.__navFollowing)return;
    let heading=Number.isFinite(deviceHeading)?deviceHeading:null;
    if(heading==null&&Number.isFinite(gpsHeading))heading=smoothHeading(gpsHeading);
    if(heading==null)heading=routeHeadingFallback(lat,lon);
    if(heading==null)heading=map.getBearing();
    const s=Number.isFinite(speed)?speed:0;
    const zoom=s>28?15.9:s>18?16.4:s>9?16.9:17.4;
    if(!orientationOnly)window.__lastNavPos={lat,lon,speed:s};
    map.easeTo({center:[lon,lat],zoom,bearing:heading,pitch:60,duration:orientationOnly?120:520,offset:[0,95],essential:true});
    window.__setNavMarker(lon,lat,heading);
  };

  window.__setNavMarker=function(lon,lat,heading=0){
    const map=window.__szMap;if(!map||!loaded)return;
    if(!navMarker){
      const el=document.createElement('div');el.className='nav-location-arrow';
      navMarker=new maplibregl.Marker({element:el,anchor:'center',rotationAlignment:'map',pitchAlignment:'map'}).setLngLat([lon,lat]).addTo(map);
    }
    navMarker.setLngLat([lon,lat]);
    if(Number.isFinite(heading))navMarker.setRotation(heading);
  };

  window.__enterNavVisual=function(){window.__navFollowing=true;document.body.classList.add('nav-mode');setTimeout(()=>{window.__szMap.resize();window.__szMap.easeTo({pitch:60,zoom:17,duration:500})},60)};
  window.__exitNavVisual=function(){window.__navFollowing=false;document.body.classList.remove('nav-mode');if(window.__szMap){window.__szMap.easeTo({pitch:0,bearing:0,duration:450});setTimeout(()=>window.__szMap.resize(),60)}};
})();