// Exercises the exact JS embedded in the Swift runtime, not a copied fixture.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const foundation = fs.readFileSync('HTMLAppV3/HTMLAppRuntimeFoundation.swift', 'utf8');
const fpsSource = foundation.match(/      const measureFPS = ([\s\S]*?)\n      const runtime = Object\.freeze/);
assert.ok(fpsSource, 'Device FPS diagnostic source must exist');
const code = 'const measureFPS = ' + fpsSource[1] + '\nreturn measureFPS;';
let callbacks = [], nextID = 0, hidden = false;
const document = { get hidden() { return hidden; } };
const window = { addEventListener() {}, removeEventListener() {} };
const raf = cb => { callbacks.push(cb); return ++nextID; };
const cancel = () => {};
const measureFPS = new Function('document','window','requestAnimationFrame',
  'cancelAnimationFrame','setTimeout','clearTimeout',code)(
    document, window, raf, cancel, setTimeout, clearTimeout);
const outcome = measureFPS({frames:45, timeoutMs:1500});
for (let i = 0; i < 46; i++) {
  assert.ok(callbacks.length, 'Expected a pending animation frame');
  callbacks.shift()(i * (1000 / 60));
}
const result = await outcome;
assert.equal(result.frames, 45);
assert.ok(result.fps > 59 && result.fps < 61, 'Expected measured 60 FPS, got ' + result.fps);
hidden = true;
await assert.rejects(measureFPS(), /visible app/);
hidden = false;

const verifier = fs.readFileSync('HTMLAppV3/HTMLRuntimeVerifier.swift','utf8');
const probe = verifier.match(/    private static let canvasProbe = #"""([\s\S]*?)"""#/);
assert.ok(probe, 'Opt-in canvas pixel verification source must exist');
function checkCanvas(kind) {
  const image = new Uint8ClampedArray(48 * 48 * 4);
  for (let i = 0; i < image.length; i += 4) {
    if (kind === 'transparent') continue;
    image[i] = kind === 'varied' && (i / 4) % 2 ? 255 : 0;
    image[i + 2] = kind === 'varied' && (i / 4) % 2 === 0 ? 255 : 0;
    image[i + 3] = 255;
  }
  const canvas = {
    width: 300, height: 300, closest: () => null,
    getBoundingClientRect: () => ({width:300,height:300})
  };
  const doc = {
    querySelectorAll: () => [canvas],
    createElement: () => ({
      getContext: () => ({
        drawImage() {},
        getImageData: () => ({data:image})
      })
    })
  };
  return vm.runInNewContext(probe[1], {
    document: doc,
    getComputedStyle: () => ({ display:'block', visibility:'visible' })
  });
}
assert.equal(checkCanvas('transparent').length,1);
assert.equal(checkCanvas('uniform').length,1);
assert.equal(checkCanvas('varied').length,0);
console.log('Canvas and frame-rate diagnostic fixtures passed.');
