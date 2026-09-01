/* v11.1 reliable MapLibre compatibility layer */
(function(){
  if(!window.maplibregl)throw new Error('MapLibre was not loaded');

  let uid=0,loaded=false;
  const pending=[];
  let deviceHeading=null,smoothedHeading=null,navMarker=null;

  function nextId(p){return 'sz-'+p+'-'+(++uid)}

  const baseStyle={
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
      {id:'background',type:'background',paint:{'background-color':'#dce7ef'}},
      {id:'esri',type:'raster',source:'esri'}
    ]
  };

  function polygonCircle(lat,lon,radiusM,steps=48){
    const coords=[],dLat=radiusM/110540;
    const dLon=radiusM/Math.max(20000,111320*Math.cos(lat*Math.PI/180));
    for(let i=0;i<=steps;i++){
      const a=Math.PI*2*i/steps;
      coords.push([lon+dLon*Math.cos(a),lat+dLat*Math.sin(a)]);
    }
    return {type:'Feature',properties:{},geometry:{type:'Polygon',coordinates:[coords]}};
  }

  class Group{
    constructor(){this.items=[]}
    addTo(){return this}
    _add(o){this.items.push(o);if(loaded)this._render(o);else pending.push(()=>this.items.includes(o)&&this._render(o))}
    _render(o){
      if(o._rendered)return;o._rendered=true;const m=window.__szMap;
      if(o.kind==='marker'||o.kind==='circleMarker'){
        let marker;
        if(o.kind==='circleMarker'){
          const el=document.createElement('div'),r=o.options.radius||7;
          Object.assign(el.style,{width:(r*2)+'px',height:(r*2)+'px',borderRadius:'50%',background:o.options.fillColor||'#006cff',border:(o.options.weight||2)+'px solid '+(o.options.color||'#fff'),boxSizing:'border-box'});
          marker=new maplibregl.Marker({element:el,anchor:'center'}).setLngLat([o.lon,o.lat]);
        }else marker=new maplibregl.Marker({color:'#d93025'}).setLngLat([o.lon,o.lat]);
        if(o.popup)marker.setPopup(new maplibregl.Popup({offset:18}).setHTML(o.popup));
        marker.addTo(m);o._marker=marker;return;
      }
      const sid=nextId('src'),lid=nextId('lyr');let data,layer;
      if(o.kind==='polyline'){
        data={type:'Feature',properties:{},geometry:{type:'LineString',coordinates:o.coords.map(p=>[p[1],p[0]])}};
        layer={id:lid,type:'line',source:sid,layout:{'line-cap':'round','line-join':'round'},paint:{'line-color':o.options.color||'#006cff','line-width':o.options.weight||6,'line-opacity':o.options.opacity??1}};
      }else if(o.kind==='circle'){
        data=polygonCircle(o.lat,o.lon,o.options.radius||304.8,56);
        layer={id:lid,type:'fill',source:sid,paint:{'fill-color':o.options.fillColor||'#ea4335','fill-opacity':o.options.fillOpacity??.13,'fill-outline-color':o.options.color||'#d93025'}};
      }else if(o.kind==='geojson'){
        data=o.data;
        layer={id:lid,type:'fill',source:sid,paint:{'fill-color':o.options.fillColor||'#ea4335','fill-opacity':o.options.fillOpacity??.13,'fill-outline-color':o.options.color||'#d93025'}};
      }
      if(!data)return;
      m.addSource(sid,{type:'geojson',data});m.addLayer(layer);o._sourceId=sid;o._layerId=lid;
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

  function shape(kind,p){return Object.assign({kind,popup:null,_rendered:false,bindPopup(html){this.popup=html;return this},addTo(group){group._add(this);return this}},p)}

  window.L={
    map(id){
      const m=new maplibregl.Map({container:id,style:baseStyle,center:[-82.46,27.95],zoom:10,pitch:0,bearing:0,maxPitch:70,attributionControl:true,antialias:true});
      window.__szMap=m;
      m.addControl(new maplibregl.NavigationControl({showCompass:true,showZoom:true,visualizePitch:true}),'top-right');
      m.on('load',()=>{loaded=true;while(pending.length){try{pending.shift()()}catch(e){console.warn(e)}}});
      m.on('error',e=>console.warn('MapLibre map error',e?.error||e));
      m.setView=function(latlng,zoom){m.easeTo({center:[latlng[1],latlng[0]],zoom:zoom??m.getZoom(),duration:250});return m};
      const nativeFit=m.fitBounds.bind(m);
      m.fitBounds=function(points,opts={}){if(window.__navFollowing)return m;const b=new maplibregl.LngLatBounds();for(const p of points)b.extend([p[1],p[0]]);nativeFit(b,{padding:Array.isArray(opts.padding)?opts.padding[0]:(opts.padding||40),duration:450,maxZoom:15});return m};
      return m;
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
  function smooth(target){target=norm(target);if(smoothedHeading==null){smoothedHeading=target;return target}const d=((target-smoothedHeading+540)%360)-180;smoothedHeading=norm(smoothedHeading+d*.22);return smoothedHeading}

  window.__requestHeadingPermission=async function(){
    try{
      if(typeof DeviceOrientationEvent!=='undefined'&&typeof DeviceOrientationEvent.requestPermission==='function'){
        const r=await DeviceOrientationEvent.requestPermission();if(r!=='granted')return false;
      }
      const handler=e=>{
        let h=null;
        if(Number.isFinite(e.webkitCompassHeading))h=e.webkitCompassHeading;
        else if(e.absolute&&Number.isFinite(e.alpha)){const angle=screen.orientation&&Number.isFinite(screen.orientation.angle)?screen.orientation.angle:0;h=norm(360-e.alpha+angle)}
        if(h!=null){deviceHeading=smooth(h);if(window.__navFollowing&&window.__lastNavPos)window.__updateNavCamera(window.__lastNavPos.lat,window.__lastNavPos.lon,deviceHeading,window.__lastNavPos.speed,true)}
      };
      window.addEventListener('deviceorientationabsolute',handler,true);window.addEventListener('deviceorientation',handler,true);return true;
    }catch(e){console.warn('Heading permission failed',e);return false}
  };

  window.__setNavMarker=function(lon,lat,heading=0){
    const m=window.__szMap;
    if(!navMarker){const el=document.createElement('div');el.className='navArrow';el.innerHTML='<div class="navArrowInner"></div>';navMarker=new maplibregl.Marker({element:el,anchor:'center',rotationAlignment:'map'}).setLngLat([lon,lat]).addTo(m)}
    navMarker.setLngLat([lon,lat]);try{navMarker.setRotation(heading||0)}catch(_){}
  };

  window.__updateNavCamera=function(lat,lon,heading,speed=0,fromCompass=false){
    const m=window.__szMap;window.__lastNavPos={lat,lon,speed};
    const chosen=Number.isFinite(deviceHeading)?deviceHeading:(Number.isFinite(heading)?smooth(heading):m.getBearing());
    const zoom=speed>24?15.8:speed>12?16.5:speed>4?17.2:18.0,pitch=speed>2?58:52;
    window.__setNavMarker(lon,lat,chosen);
    m.easeTo({center:[lon,lat],zoom,pitch,bearing:chosen,padding:{top:170,bottom:330,left:30,right:30},duration:fromCompass?180:420,essential:true});
  };

  window.__enterNavVisual=function(){window.__navFollowing=true;document.body.classList.add('navMode');try{window.__szMap.easeTo({pitch:58,zoom:17.3,duration:450})}catch(_){}};
  window.__exitNavVisual=function(){window.__navFollowing=false;document.body.classList.remove('navMode');try{window.__szMap.easeTo({pitch:0,bearing:0,duration:400})}catch(_){}};
})();