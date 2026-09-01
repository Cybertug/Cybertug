/* v11.2 smart fuzzy geocoding: Photon first, Nominatim fallback, Florida/location bias */
(function(){
  const cache=new Map();
  const CACHE_MS=120000;

  function norm(s){
    return (s||'').toLowerCase()
      .normalize('NFD').replace(/[\u0300-\u036f]/g,'')
      .replace(/\bairforce\b/g,'air force')
      .replace(/\baf base\b/g,'air force base')
      .replace(/\bafb\b/g,'air force base')
      .replace(/\bst\.\b/g,'st')
      .replace(/\brd\.\b/g,'rd')
      .replace(/\bdr\.\b/g,'dr')
      .replace(/[^a-z0-9]+/g,' ')
      .trim();
  }

  const STOP=new Set(['the','of','at','in','on','and','usa','us','united','states',
    'street','st','road','rd','drive','dr','avenue','ave','boulevard','blvd',
    'lane','ln','court','ct','way','highway','hwy','florida','fl']);

  function words(s){
    return norm(s).split(/\s+/).filter(x=>x&&!STOP.has(x));
  }

  function hasExplicitState(q){
    const n=' '+norm(q)+' ';
    return /\b(alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|hampshire|jersey|mexico|york|carolina|dakota|ohio|oklahoma|oregon|pennsylvania|rhode|tennessee|texas|utah|vermont|virginia|washington|wisconsin|wyoming)\b/.test(n)
      || /\b(fl|ca|tx|ny|ga|nc|sc|va|pa|oh|mi|il|az|wa|or|co|tn|nj|ma|md)\b/.test(n);
  }

  function biasPoint(){
    try{
      if(typeof SO!=='undefined'&&SO&&Number.isFinite(SO.lat))return SO;
      if(typeof SD!=='undefined'&&SD&&Number.isFinite(SD.lat))return SD;
      if(typeof activeOrigin!=='undefined'&&activeOrigin&&Number.isFinite(activeOrigin.lat))return activeOrigin;
    }catch(_){}
    return {lat:27.9506,lon:-82.4572};
  }

  function distanceKm(a,b){
    if(!a||!b)return 0;
    const R=6371,p1=a.lat*Math.PI/180,p2=b.lat*Math.PI/180;
    const dp=(b.lat-a.lat)*Math.PI/180,dl=(b.lon-a.lon)*Math.PI/180;
    const h=Math.sin(dp/2)**2+Math.cos(p1)*Math.cos(p2)*Math.sin(dl/2)**2;
    return 2*R*Math.asin(Math.min(1,Math.sqrt(h)));
  }

  function photonToCandidate(f){
    const p=f.properties||{},c=f.geometry?.coordinates||[];
    const line1=[p.housenumber,p.street].filter(Boolean).join(' ')||p.name||p.street||'Location';
    const city=p.city||p.town||p.village||p.county||'';
    const state=p.state||'';
    const zip=p.postcode||'';
    const label=[line1,city,state,zip].filter(Boolean).join(', ');
    return {
      lat:+c[1],lon:+c[0],display_name:label,
      address:{
        house_number:p.housenumber||'',
        road:p.street||p.name||'',
        city,county:p.county||'',
        state,postcode:zip
      },
      type:p.type||p.osm_value||'place',
      _source:'photon'
    };
  }

  async function photon(q,bias){
    const u=new URL('https://photon.komoot.io/api/');
    u.searchParams.set('q',q);
    u.searchParams.set('limit','8');
    u.searchParams.set('lang','en');
    if(bias){
      u.searchParams.set('lat',bias.lat);
      u.searchParams.set('lon',bias.lon);
    }
    const d=await j(u.toString(),{},8500);
    return (d.features||[]).map(photonToCandidate)
      .filter(x=>Number.isFinite(x.lat)&&Number.isFinite(x.lon));
  }

  async function nominatim(q,bias,preferFlorida){
    let url='https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&limit=8&countrycodes=us&q='+encodeURIComponent(q);
    if(bias&&!hasExplicitState(q)){
      const span=preferFlorida?3.3:1.6;
      url+='&viewbox='+[
        bias.lon-span,bias.lat+span,bias.lon+span,bias.lat-span
      ].join(',');
    }
    const d=await j(url,{},9000);
    return (d||[]).map(x=>({...x,lat:+x.lat,lon:+x.lon,_source:'nominatim'}));
  }

  function score(c,q,bias){
    const qn=norm(q),ln=norm(c.display_name);
    const qw=words(q),lw=new Set(words(c.display_name));
    let s=0;

    if(ln.includes(qn)&&qn.length>4)s+=6;

    let matches=0;
    for(const w of qw){
      if(lw.has(w)){matches++;s+=2.1}
      else if([...lw].some(x=>x.startsWith(w)||w.startsWith(x)))s+=0.7;
      else s-=1.5;
    }

    if(qw.length)s+=3*(matches/qw.length);

    const qNum=(qn.match(/\b\d{1,6}\b/)||[])[0];
    const cNum=norm(c.address?.house_number||'').match(/\b\d{1,6}\b/)?.[0];
    if(qNum){
      if(cNum===qNum)s+=4;
      else if(cNum)s-=5;
    }

    const state=norm(c.address?.state||'');
    const explicit=hasExplicitState(q);
    if(!explicit){
      if(state.includes('florida')||state==='fl')s+=3.5;
      else if(state)s-=3.5;
    }else if(/\bflorida\b|\bfl\b/.test(qn)){
      if(state.includes('florida')||state==='fl')s+=4;
      else s-=7;
    }

    if(/\b(base|airport|hospital|park|university|college|mall|stadium|station)\b/.test(qn)){
      if(/\b(base|airport|hospital|park|university|college|mall|stadium|station)\b/.test(ln))s+=2;
    }

    if(bias){
      const km=distanceKm(bias,c);
      s-=Math.min(5,Math.log1p(km)/1.5);
      if(km<40)s+=1.5;
    }

    if(c._source==='photon')s+=0.2;
    return s;
  }

  function dedupe(list){
    const out=[],seen=new Set();
    for(const c of list){
      const k=(Math.round(c.lat*10000))+':'+(Math.round(c.lon*10000));
      if(seen.has(k))continue;
      seen.add(k);out.push(c);
    }
    return out;
  }

  function variants(q){
    const raw=q.trim();
    const corrected=raw
      .replace(/\bairforce\b/ig,'Air Force')
      .replace(/\bmacdill\b/ig,'MacDill');
    const out=[raw];
    if(corrected!==raw)out.push(corrected);
    if(!hasExplicitState(raw))out.push(corrected+', Florida');
    return [...new Set(out)];
  }

  async function smartSearch(q){
    q=(q||'').trim();
    if(q.length<2)return[];

    const key=norm(q);
    const old=cache.get(key);
    if(old&&Date.now()-old.ts<CACHE_MS)return old.data;

    const bias=biasPoint();
    const vs=variants(q);
    let all=[];

    try{all.push(...await photon(vs[0],bias))}catch(_){}
    try{all.push(...await nominatim(vs[0],bias,true))}catch(_){}

    let ranked=dedupe(all)
      .map(c=>({...c,_score:score(c,q,bias)}))
      .sort((a,b)=>b._score-a._score);

    if(!ranked.length||ranked[0]._score<5){
      for(const v of vs.slice(1)){
        try{all.push(...await photon(v,bias))}catch(_){}
        if(all.length<5){
          try{all.push(...await nominatim(v,bias,true))}catch(_){}
        }
      }
      ranked=dedupe(all)
        .map(c=>({...c,_score:score(c,q,bias)}))
        .sort((a,b)=>b._score-a._score);
    }

    const filtered=ranked.filter((c,i)=>{
      if(i===0&&c._score>=3.8)return true;
      return c._score>=4.5;
    }).slice(0,7);

    cache.set(key,{ts:Date.now(),data:filtered});
    return filtered;
  }

  searchAddr=smartSearch;

  resolve=async function(q,s){
    if(s)return s;
    const list=await smartSearch(q);
    if(!list.length)throw Error('No close match found. Try a street, place, city, or ZIP code.');
    const best=list[0];
    if(best._score<3.8)throw Error('No reliable nearby match found. Please choose one of the suggestions.');
    return {lat:+best.lat,lon:+best.lon,label:best.display_name,approximate:best._score<7};
  };

  function rebind(k){
    const inp=$(k),box=$(k+'s');
    inp.oninput=()=>{
      k==='o'?SO=null:SD=null;
      clearTimeout(timers[k]);
      const q=inp.value.trim();
      if(q.length<3){box.style.display='none';return}
      timers[k]=setTimeout(async()=>{
        try{
          const list=await smartSearch(q);
          box.innerHTML='';
          for(const x of list){
            const [a,b]=labelAddr(x),e=document.createElement('div');
            e.className='item';
            e.innerHTML='<b>'+a+'</b><small>'+b+(x._score<7?' · nearby match':'')+'</small>';
            e.onclick=()=>{
              const v={lat:+x.lat,lon:+x.lon,label:x.display_name};
              k==='o'?SO=v:SD=v;
              inp.value=a+(b?', '+b:'');
              box.style.display='none';
            };
            box.appendChild(e);
          }
          box.style.display=list.length?'block':'none';
        }catch(_){box.style.display='none'}
      },320);
    };
  }

  rebind('o');rebind('d');
})();