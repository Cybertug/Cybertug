/* Compatibility patches loaded before v10-core.js */
if(window.L){
  window.L.tileLayer=function(){return{addTo(){return this},on(){return this}}};
}
