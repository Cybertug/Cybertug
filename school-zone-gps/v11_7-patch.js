/* v11.7 UI patch: expose why a route failed instead of generic red text. */
(function(){
  const originalAvoid=avoidRoute;
  avoidRoute=async function(a,b,alternatives){
    const out=await originalAvoid(a,b,alternatives);
    if(!out.r&&out.diagnostic){
      const originNote=out.originZones?` Starting point is inside ${out.originZones} mapped school zone${out.originZones===1?'':'s'}; exit-only handling was applied.`:'';
      setTimeout(()=>{try{$('detail').textContent=(out.diagnostic||'Routing failed.')+originNote;$('st').textContent='Could not validate a route: '+(out.diagnostic||'all available routes still cross a school zone.')+originNote}catch(_){}},0);
    }
    return out;
  };
  const observer=new MutationObserver(()=>{
    try{
      if(AR&&$('sum').style.display!=='none'){
        if(AR._safeApproach){
          if(AR._safeApproach.boundaryFallback){
            const feet=Math.round((AR._safeApproach.distanceToDestination||0)*3.28084);
            $('sumSub').innerHTML='<span class="valid">SAFE STOP · closest reachable road point outside the red school zone</span>';
            $('destWarning').innerHTML='<span class="red">A fully clear route to the requested destination was not available. Navigation stops outside the 1,000 ft circle for '+AR._safeApproach.school+', approximately '+feet+' ft from the requested destination.</span>';
          }else{
            $('sumSub').innerHTML='<span class="valid">Validated to a safe approach point outside the destination school zone</span>';
            $('destWarning').innerHTML='<span class="red">The requested destination is inside the 1,000 ft zone for '+AR._safeApproach.school+'. Navigation stops outside the red circle.</span>';
          }
        }else if(routingDiagnostics.originZones){
          $('sumSub').innerHTML='<span class="valid">Validated · route exits the starting school zone and does not re-enter it</span>';
        }
      }
    }catch(_){}
  });
  observer.observe(document.body,{subtree:true,attributes:true,attributeFilter:['style']});
})();
