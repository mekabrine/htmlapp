import fs from 'node:fs';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../HTMLApp/Resources/RuntimeLibraries/htmlapp/kits.js',import.meta.url),'utf8');
const {gameLoop,fetchJSON,proceduralTexture,takeSnapshot,canvasDiagnostics} =
  await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));

let callback,cancelled=0,updates=[];
globalThis.requestAnimationFrame=f=>{callback=f;return 1;};
globalThis.cancelAnimationFrame=()=>cancelled++;
const events=new Map();
const textureCalls=[];
const context={
  fillRect:(...args)=>textureCalls.push(args),
  createLinearGradient:()=>({addColorStop:()=>{}}),
  getImageData:()=>({data:new Uint8ClampedArray([1,2,3,255])})
};
globalThis.document={
  hidden:false,addEventListener:(n,f)=>events.set(n,f),
  removeEventListener:n=>events.delete(n),
  createElement:tag=>{assert.equal(tag,'canvas');return {
    width:0,height:0,getContext:kind=>kind==='2d'?context:null,
    toDataURL:(kind)=>'data:'+kind+';base64,cafe'
  };}
};

const loop=gameLoop({update:dt=>updates.push(dt)});
callback(100);callback(2100);
assert.deepEqual(updates,[0,.05]);
assert.equal(loop.frames,2);
assert.equal(loop.fps,.5); // FPS uses real elapsed time, not clamped simulation delta
document.hidden=true;events.get('visibilitychange')();
assert.ok(cancelled);
loop.destroy();assert.equal(events.size,0);

globalThis.fetch=async(_url,options)=>{assert.equal(options.cache,'no-store');return {ok:true,json:async()=>({ok:1})};};
assert.deepEqual(await fetchJSON('https://example.com'),{ok:1});
globalThis.fetch=async()=>({ok:false,status:503});
await assert.rejects(fetchJSON('https://example.com'),/503/);

const texture=proceduralTexture({width:32,height:24,kind:'checker',cellSize:8});
assert.equal(texture.width,32);
assert.equal(texture.height,24);
assert.ok(textureCalls.length>=12);
const noisy=proceduralTexture({width:4,height:4,kind:'noise',seed:99});
assert.equal(noisy.width,4);
assert.throws(()=>proceduralTexture({kind:'missing'}),/kind/);
assert.equal(takeSnapshot(texture),'data:image/png;base64,cafe');
assert.throws(()=>takeSnapshot({width:10000,height:10000,toDataURL:()=>''}),/limit/);
assert.deepEqual(canvasDiagnostics(texture),{
  available:true,width:32,height:24,visibleSamples:64,uniqueColors:1,uniform:true
});
console.log('Runtime kit lifecycle, bounded assets, FPS, snapshot and network fixtures passed.');
