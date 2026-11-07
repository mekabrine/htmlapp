// HTMLApp runtime kits, MIT. No remote dependencies.
export function gameLoop({update, render, maxDelta=0.05}) {
  let frame=0, last=0, running=false, fps=0, frames=0;
  const tick = time => {
    if(!running) return;
    const elapsed=last ? Math.max(0,(time-last)/1000) : 0;
    const dt=Math.min(maxDelta,elapsed); last=time;
    if(elapsed>0){const instant=1/elapsed;fps=fps?fps*.8+instant*.2:instant;}
    frames++;
    update?.(dt,time/1000);render?.(dt,time/1000);
    frame=requestAnimationFrame(tick);
  };
  const stop=()=>{running=false;cancelAnimationFrame(frame);last=0;};
  const start=()=>{if(!running){running=true;frame=requestAnimationFrame(tick);}};
  const visibility=()=>document.hidden?stop():start();
  document.addEventListener('visibilitychange',visibility);start();
  return {start,stop,get fps(){return Number(fps.toFixed(1));},get frames(){return frames;},
    destroy(){stop();document.removeEventListener('visibilitychange',visibility);}};
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


// Deterministic, local assets: no image CDN, key or model download required.
// The returned canvas can be used as a CSS image, sprite or THREE.CanvasTexture.
export function proceduralTexture({width=128,height=128,kind='checker',
  colors=['#24344b','#5175aa'],seed=1,cellSize=16}={}) {
  const w=Math.max(1,Math.min(1024,Math.floor(Number(width)||128)));
  const h=Math.max(1,Math.min(1024,Math.floor(Number(height)||128)));
  const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h;
  const context=canvas.getContext('2d');
  if(!context)throw new Error('2D texture rendering unavailable');
  const palette=colors.length?colors.slice(0,8):['#24344b','#5175aa'];
  const size=Math.max(2,Math.min(256,Math.floor(cellSize)||16));
  const fill=color=>{context.fillStyle=color;context.fillRect(0,0,w,h);};
  fill(palette[0]);
  if(kind==='gradient'){
    const gradient=context.createLinearGradient(0,0,w,h);
    gradient.addColorStop(0,palette[0]);gradient.addColorStop(1,palette[1]||palette[0]);
    fill(gradient);
  }else if(kind==='checker'||kind==='stripes'){
    for(let y=0;y<h;y+=size)for(let x=0;x<w;x+=size){
      const index=kind==='stripes'?Math.floor(x/size):Math.floor(x/size)+Math.floor(y/size);
      context.fillStyle=palette[index%palette.length];
      context.fillRect(x,y,Math.min(size,w-x),Math.min(size,h-y));
    }
  }else if(kind==='noise'){
    let state=(Number(seed)>>>0)||1;
    const random=()=>{state^=state<<13;state^=state>>>17;state^=state<<5;return (state>>>0)/4294967296;};
    for(let y=0;y<h;y+=size)for(let x=0;x<w;x+=size){
      context.globalAlpha=.3+.7*random();context.fillStyle=palette[Math.floor(random()*palette.length)];
      context.fillRect(x,y,Math.min(size,w-x),Math.min(size,h-y));
    }
    context.globalAlpha=1;
  }else throw new RangeError('Texture kind must be checker, stripes, gradient or noise');
  return canvas;
}

// Explicit snapshot for optional device QA. WebGL must capture during its
// render frame when preserveDrawingBuffer is false. Cross-origin taint throws.
export function takeSnapshot(canvas,{type='image/png',quality=.92,maxPixels=4_000_000}={}) {
  if(!canvas||!Number.isFinite(canvas.width)||!Number.isFinite(canvas.height)||
    canvas.width<1||canvas.height<1||canvas.width*canvas.height>maxPixels)
    throw new RangeError('Canvas snapshot dimensions exceed safety limit');
  if(type!=='image/png'&&type!=='image/jpeg'&&type!=='image/webp')
    throw new RangeError('Unsupported snapshot format');
  return canvas.toDataURL(type,Math.min(1,Math.max(0,quality)));
}

export function canvasDiagnostics(canvas) {
  const width=canvas?.width||0,height=canvas?.height||0;
  if(!width||!height)return {available:false,width,height,reason:'Canvas has no pixels'};
  try {
    const context=canvas.getContext('2d');
    if(!context)return {available:false,width,height,reason:'Use a render-frame snapshot for WebGL'};
    const stepX=Math.max(1,Math.floor(width/8)),stepY=Math.max(1,Math.floor(height/8));
    const colors=new Set();let visible=0;
    for(let y=0;y<height;y+=stepY)for(let x=0;x<width;x+=stepX){
      const pixel=context.getImageData(x,y,1,1).data;
      if(pixel[3]>0)visible++;
      colors.add(Array.from(pixel).join(','));
    }
    return {available:true,width,height,visibleSamples:visible,uniqueColors:colors.size,
      uniform:colors.size<=1};
  }catch(error){return {available:false,width,height,reason:String(error?.message||error)};}
}
