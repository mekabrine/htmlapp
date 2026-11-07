// HTMLApp runtime kits, MIT. No remote dependencies.
export function gameLoop({update, render, maxDelta=0.05}) {
  let frame=0, last=0, running=false;
  const tick = time => {
    if(!running) return;
    const dt=last ? Math.min(maxDelta,(time-last)/1000) : 0; last=time;
    update?.(dt,time/1000);render?.(dt,time/1000);
    frame=requestAnimationFrame(tick);
  };
  const stop=()=>{running=false;cancelAnimationFrame(frame);last=0;};
  const start=()=>{if(!running){running=true;frame=requestAnimationFrame(tick);}};
  const visibility=()=>document.hidden?stop():start();
  document.addEventListener('visibilitychange',visibility);start();
  return {start,stop,destroy(){stop();document.removeEventListener('visibilitychange',visibility);}};
}
export function canvasSurface(canvas,{maxPixelRatio=2}={}) {
  const context=canvas.getContext('2d');if(!context)throw Error('2D canvas unavailable');
  const resize=()=>{const r=canvas.getBoundingClientRect(),d=Math.min(maxPixelRatio,devicePixelRatio||1);
    canvas.width=Math.max(1,Math.round(r.width*d));canvas.height=Math.max(1,Math.round(r.height*d));context.setTransform(d,0,0,d,0,0);};
  const observer=new ResizeObserver(resize);observer.observe(canvas);resize();
  return {context,resize,destroy:()=>observer.disconnect()};
}
export function pointerInput(element) {
  const state={x:0,y:0,pressed:false};
  const move=e=>{const r=element.getBoundingClientRect();state.x=e.clientX-r.left;state.y=e.clientY-r.top;};
  const down=e=>{move(e);state.pressed=true;element.setPointerCapture?.(e.pointerId);};
  const up=()=>{state.pressed=false;};
  element.addEventListener('pointerdown',down);element.addEventListener('pointermove',move);
  element.addEventListener('pointerup',up);element.addEventListener('pointercancel',up);
  return {state,destroy(){element.removeEventListener('pointerdown',down);element.removeEventListener('pointermove',move);element.removeEventListener('pointerup',up);element.removeEventListener('pointercancel',up);}};
}
export function soundPreset(context, name='tap', volume=0.15) {
  const presets={tap:[660,0.06,'sine'],success:[880,0.18,'sine'],error:[160,0.2,'triangle'],jump:[440,0.12,'square']};
  const [frequency,duration,type]=presets[name]||presets.tap;
  const oscillator=context.createOscillator(),gain=context.createGain();
  oscillator.type=type;oscillator.frequency.value=frequency;gain.gain.setValueAtTime(Math.max(0.001,Math.min(0.4,volume)),context.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001,context.currentTime+duration);
  oscillator.connect(gain);gain.connect(context.destination);oscillator.start();oscillator.stop(context.currentTime+duration);
  oscillator.onended=()=>{oscillator.disconnect();gain.disconnect();};
}
export function sprite({size=64,color='#3576d3',shape='circle'}={}) {
  const canvas=document.createElement('canvas');canvas.width=canvas.height=Math.max(1,Math.min(512,size));
  const c=canvas.getContext('2d');c.fillStyle=color;
  if(shape==='circle'){c.beginPath();c.arc(size/2,size/2,size*.4,0,Math.PI*2);c.fill();}
  else if(shape==='triangle'){c.beginPath();c.moveTo(size/2,size*.1);c.lineTo(size*.9,size*.9);c.lineTo(size*.1,size*.9);c.closePath();c.fill();}
  else c.fillRect(size*.1,size*.1,size*.8,size*.8);
  return canvas;
}
export async function fetchJSON(url,{timeout=8000,signal,cache='no-store'}={}) {
  const controller=new AbortController(),abort=()=>controller.abort();
  if(signal?.aborted)controller.abort();else signal?.addEventListener('abort',abort,{once:true});
  const timer=setTimeout(abort,Math.max(500,Math.min(30000,timeout)));
  try { const response=await fetch(url,{signal:controller.signal,cache});if(!response.ok)throw Error('HTTP '+response.status);return await response.json(); }
  finally{clearTimeout(timer);signal?.removeEventListener('abort',abort);}
}
