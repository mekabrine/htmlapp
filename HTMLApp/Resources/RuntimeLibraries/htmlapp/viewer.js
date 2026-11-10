import {scene, disposeObjects} from './scene.js';

class HTMLAppViewer extends HTMLElement {
  static get observedAttributes() { return ['src']; }

  attributeChangedCallback(name, oldValue, value) {
    if (oldValue === value || !this.isConnected || !this.cleanup) return;
    this.cleanup();
    this.connectedCallback();
  }

  connectedCallback() {
    if (this.cleanup) return;
    const root = this.shadowRoot || this.attachShadow({mode: 'open'});
    root.innerHTML = `
      <style>
        :host{display:block;min-width:0;color:inherit}
        :host([hidden]){display:none}
        canvas{display:block;width:100%;height:var(--ha-viewer-height,clamp(200px,48vw,420px));border-radius:12px}
        nav{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
        button{font:inherit;min-height:44px;padding:0 12px;border-radius:8px;border:1px solid GrayText;background:Canvas;color:CanvasText}
        [hidden]{display:none}
      </style>
      <canvas role="img"></canvas>
      <p role="status" hidden></p>
      <nav aria-label="3D view controls">
        <button type="button" aria-label="Rotate left">←</button>
        <button type="button" aria-label="Rotate right">→</button>
        <button type="button" aria-label="Rotate up">↑</button>
        <button type="button" aria-label="Rotate down">↓</button>
        <button type="button" aria-label="Zoom in">+</button>
        <button type="button" aria-label="Zoom out">−</button>
        <button type="button">Reset view</button>
      </nav>`;
    const canvas = root.querySelector('canvas');
    const status = root.querySelector('p');
    const nav = root.querySelector('nav');
    const label = this.getAttribute('label') || 'Interactive 3D object';
    canvas.setAttribute('aria-label', label);
    let active = true, view, animationFrame = null;
    const abort = new AbortController();
    const showStatus = message => {
      status.textContent = message;
      status.hidden = !message;
    };
    const fail = error => {
      if (!active) return;
      this.dataset.htmlappViewer = 'error';
      showStatus(label + ' — ' + (error?.message || '3D rendering is unavailable.'));
      nav.hidden = true;
      canvas.hidden = true;
      view?.destroy();
      if (animationFrame !== null) cancelAnimationFrame(animationFrame);
      animationFrame = null;
    };
    const pause = () => {
      if (animationFrame !== null) cancelAnimationFrame(animationFrame);
      animationFrame = null;
    };
    const leave = event => { if (!event.persisted) this.cleanup?.(); else pause(); };
    let visibility;
    this.cleanup = () => {
      active = false;
      abort.abort();
      pause();
      visibility?.disconnect();
      view?.destroy();
      window.removeEventListener('pagehide', leave);
      window.removeEventListener('pageshow', resume);
      document.removeEventListener('visibilitychange', resume);
      delete this.htmlappInspect;
      this.cleanup = null;
    };
    const animate = this.getAttribute('animate') === 'spin';
    const resume = () => {
      if (!active || !animate || document.hidden || !canvas.getClientRects().length ||
          this.dataset.htmlappViewer !== 'ready') { pause(); return; }
      if (animationFrame !== null) return;
      let lastTime;
      const spin = time => {
        animationFrame = null;
        if (document.hidden || !canvas.getClientRects().length || !active) return;
        if (lastTime !== undefined) view.rotate(Math.min(time - lastTime, 40) * .0005, 0);
        lastTime = time;
        animationFrame = requestAnimationFrame(spin);
      };
      animationFrame = requestAnimationFrame(spin);
    };
    window.addEventListener('pagehide', leave);
    window.addEventListener('pageshow', resume);
    document.addEventListener('visibilitychange', resume);
    this.dataset.htmlappViewer = 'loading';
    try {
      view = scene(canvas, {
        background: this.getAttribute('background') || 0x101822,
        rotation: this.getAttribute('rotation') === 'camera' ? 'camera' : 'object',
        continuous: false, pixelRatio: 1.5, onError: fail
      });
      const actions = [
        () => view.rotate(-.3, 0), () => view.rotate(.3, 0),
        () => view.rotate(0, -.3), () => view.rotate(0, .3),
        () => view.zoom(.8), () => view.zoom(1.25), () => view.reset()
      ];
      nav.querySelectorAll('button').forEach((button, index) => button.addEventListener('click', actions[index]));
      canvas.addEventListener('webglcontextlost', () => showStatus('Restoring 3D view…'));
      canvas.addEventListener('webglcontextrestored', () => showStatus(''));
      const src = this.getAttribute('src');
      const finish = () => {
        if (!active) return;
        this.dataset.htmlappViewer = 'ready';
        showStatus('');
        view.invalidate();
        resume();
      };
      if (src) {
        showStatus('Loading model…');
        loadModel(src, view.THREE, abort.signal).then(model => {
          if (!active) { disposeObjects(model); return; }
          view.content.add(model);
          finish();
        }).catch(fail);
      } else {
        const mesh = view.primitive(this.getAttribute('shape') || 'box', this.getAttribute('color') || 0x3576d3);
        mesh.material.roughness = numberAttribute(this, 'roughness', .65, 0, 1);
        mesh.material.metalness = numberAttribute(this, 'metalness', 0, 0, 1);
        mesh.scale.setScalar(numberAttribute(this, 'scale', 1.65, .1, 3));
        mesh.position.set(...['x', 'y', 'z'].map(axis => numberAttribute(this, axis, 0, -2, 2)));
        const [ambient, directional] = view.world.children.filter(child => child.isLight);
        ambient.intensity = numberAttribute(this, 'ambient', 2, 0, 8);
        directional.intensity = numberAttribute(this, 'lighting', 3, 0, 8);
        finish();
      }
      visibility = new IntersectionObserver(resume);
      visibility.observe(canvas);
      this.htmlappInspect = () => ({
        pose: view.pose, width: canvas.width, height: canvas.height,
        aspect: view.camera.aspect, contextLost: canvas.dataset.htmlappContextLost === 'true',
        rendered: view.render(), triangles: view.renderer.info.render.triangles
      });
    } catch (error) { fail(error); }
  }

  disconnectedCallback() { this.cleanup?.(); }
}

function numberAttribute(element, name, fallback, min, max) {
  const value = Number(element.getAttribute(name) ?? fallback);
  return Number.isFinite(value) ? Math.max(min, Math.min(max, value)) : fallback;
}

async function loadModel(path, THREE, signal) {
  const url = new URL(path, document.baseURI);
  const base = new URL(location.href);
  if (url.protocol !== base.protocol || url.host !== base.host || url.username || url.password ||
      url.search || url.hash || !url.pathname.toLowerCase().endsWith('.glb')) {
    throw new Error('Choose a local .glb file.');
  }
  const response = await fetch(url, {signal});
  const limit = 16 * 1024 * 1024;
  if (!response.ok || Number(response.headers.get('Content-Length')) > limit) {
    throw new Error('Could not open the model. Use a local .glb under 16 MB.');
  }
  const bytes = await response.arrayBuffer();
  if (bytes.byteLength < 20 || bytes.byteLength > limit) throw new Error('Invalid or oversized .glb file.');
  const header = new DataView(bytes);
  const jsonLength = header.getUint32(12, true);
  if (header.getUint32(0, true) !== 0x46546c67 || header.getUint32(4, true) !== 2 ||
      header.getUint32(8, true) !== bytes.byteLength || header.getUint32(16, true) !== 0x4e4f534a ||
      jsonLength > bytes.byteLength - 20) throw new Error('Invalid glTF 2.0 binary model.');
  const json = JSON.parse(new TextDecoder().decode(new Uint8Array(bytes, 20, jsonLength)));
  if ([...(json.buffers || []), ...(json.images || [])].some(asset => asset.uri !== undefined)) {
    throw new Error('Use a self-contained .glb with embedded textures and geometry.');
  }
  if ((json.accessors || []).some(accessor => accessor.count > 1_000_000)) {
    throw new Error('The model is too complex. Use a simplified .glb.');
  }
  const {GLTFLoader} = await import('../three/examples/jsm/loaders/GLTFLoader.js');
  const manager = new THREE.LoadingManager();
  manager.setURLModifier(value => {
    if (!value.startsWith('blob:')) throw new Error('External model assets are unsupported.');
    return value;
  });
  const {scene: model} = await new GLTFLoader(manager).parseAsync(bytes, '');
  const bounds = new THREE.Box3().setFromObject(model);
  const size = bounds.getSize(new THREE.Vector3());
  const extent = Math.max(size.x, size.y, size.z);
  if (!Number.isFinite(extent) || extent <= 0) {
    disposeObjects(model);
    throw new Error('The model has no visible geometry.');
  }
  const centered = new THREE.Group();
  centered.add(model);
  model.position.sub(bounds.getCenter(new THREE.Vector3()));
  centered.scale.setScalar(2 / extent);
  return centered;
}

if (!customElements.get('htmlapp-viewer')) customElements.define('htmlapp-viewer', HTMLAppViewer);
