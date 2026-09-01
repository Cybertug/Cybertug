/* v11.5 search patch: Any MacDill base-like query puts the real AFB main gate first. */
(function(){
  const oldSearch=searchAddr;
  const oldResolve=resolve;

  function n(s){return(s||'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim()}
  function looksMacDill(q){
    const x=n(q);
    return x.includes('macdill') || x.includes('mac dill');
  }

  async function macdillCanonical(){
    const queries=[
      '6911 S Dale Mabry Hwy, Tampa, FL 33621',
      '6901 S Dale Mabry Hwy, Tampa, FL 33621'
    ];

    for(const q of queries){
      try{
        const rows=await oldSearch(q);
        const good=(rows||[]).find(x=>{
          const lat=+x.lat,lon=+x.lon;
          return Number.isFinite(lat)&&Number.isFinite(lon)&&
                 lat>27.80&&lat<27.90&&lon>-82.55&&lon<-82.45;
        });
        if(good){
          return{
            ...good,
            display_name:'MacDill Air Force Base – Dale Mabry Gate, 6911 S Dale Mabry Hwy, Tampa, FL 33621',
            address:{
              ...(good.address||{}),
              road:'S Dale Mabry Hwy',
              city:'Tampa',
              state:'Florida',
              postcode:'33621'
            },
            _score:100,
            _canonical:'macdill'
          };
        }
      }catch(_){}
    }
    return null;
  }

  searchAddr=async function(q){
    if(!looksMacDill(q))return oldSearch(q);
    const c=await macdillCanonical();
    let rest=[];
    try{rest=await oldSearch(q)}catch(_){}
    rest=(rest||[]).filter(x=>!/macdill park/i.test(x.display_name||''));
    return c?[c,...rest.filter(x=>Math.abs(+x.lat-c.lat)>.0001||Math.abs(+x.lon-c.lon)>.0001).slice(0,6)]:rest;
  };

  resolve=async function(q,s){
    if(looksMacDill(q)){
      const c=await macdillCanonical();
      if(c)return{lat:+c.lat,lon:+c.lon,label:c.display_name,approximate:false,canonical:'macdill'};
    }
    return oldResolve(q,s);
  };

  function bind(k){
    const inp=$(k),box=$(k+'s');
    inp.oninput=()=>{
      k==='o'?SO=null:SD=null;
      clearTimeout(timers[k]);
      const q=inp.value.trim();
      if(q.length<3){box.style.display='none';return}
      timers[k]=setTimeout(async()=>{
        try{
          const list=await searchAddr(q);
          box.innerHTML='';
          for(const x of list){
            const [a,b]=labelAddr(x);
            const e=document.createElement('div');
            e.className='item';
            e.innerHTML='<b>'+a+'</b><small>'+b+(x._canonical==='macdill'?' · MAIN GATE':'')+'</small>';
            e.onclick=()=>{
              const v={lat:+x.lat,lon:+x.lon,label:x.display_name,canonical:x._canonical||null};
              k==='o'?SO=v:SD=v;
              inp.value=x._canonical==='macdill'
                ?'MacDill Air Force Base – Dale Mabry Gate'
                :a+(b?', '+b:'');
              box.style.display='none';
            };
            box.appendChild(e);
          }
          box.style.display=list.length?'block':'none';
        }catch(_){box.style.display='none'}
      },220);
    };
  }

  bind('o');bind('d');
})();
