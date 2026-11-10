import * as THREE from '../three/build/three.module.js';

export function scene(canvas, {
  background = 0x101822, orbit = true, continuous = true, pixelRatio = 2,
  rotation = 'camera', onError = console.error
} = {}) {
  const renderer = new THREE.WebGLRenderer({canvas, antialias: true});
  renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio || 1, pixelRatio));
  const world = new THREE.Scene();
  world.background = new THREE.Color(background);
  const camera = new THREE.PerspectiveCamera(50, 1, .1, 1000);
  const objects = new THREE.Group();
  // Keep existing scene() callers' world hierarchy intact.
  if (rotation === 'object') world.add(objects);
  const content = rotation === 'object' ? objects : world;
  world.add(new THREE.HemisphereLight(0xffffff, 0x444444, 2));
  const light = new THREE.DirectionalLight(0xffffff, 3);
  light.position.set(3, 5, 2);
  world.add(light);

  const origin = {radius: 5, azimuth: 0, elevation: .38};
  const state = {...origin};
  const pointers = new Map();
  const oldTouchAction = canvas.style.touchAction;
  let enabled = !!orbit, dead = false, lost = false, frame = null, fps = 0, lastFrame = 0;
  let width = 0, height = 0;
  function positionCamera() {
    const {radius, azimuth, elevation} = state;
    camera.position.set(radius * Math.sin(azimuth) * Math.cos(elevation),
      radius * Math.sin(elevation), radius * Math.cos(azimuth) * Math.cos(elevation));
    camera.lookAt(0, 0, 0);
  }
  function render() {
    if (dead || lost || !width || !height) return false;
    renderer.render(world, camera);
    return true;
  }
  function visible() {
    return !document.hidden && canvas.isConnected && canvas.getClientRects().length > 0 &&
      getComputedStyle(canvas).visibility === 'visible';
  }
  function invalidate() {
    if (frame !== null || dead || lost || !visible()) return;
    frame = requestAnimationFrame(time => {
      frame = null;
      if (!visible()) { lastFrame = 0; return; }
      try {
        render();
        if (continuous && lastFrame && time > lastFrame) fps = 1000 / (time - lastFrame);
        lastFrame = time;
        if (continuous) invalidate();
      } catch (error) { onError(error); }
    });
  }
  function rotate(x, y) {
    if (rotation === 'object') {
      objects.rotation.y += x;
      objects.rotation.x = Math.max(-1.45, Math.min(1.45, objects.rotation.x + y));
    } else {
      state.azimuth -= x;
      state.elevation = Math.max(-1.45, Math.min(1.45, state.elevation + y));
      positionCamera();
    }
    invalidate();
  }
  function zoom(factor) {
    state.radius = Math.max(.8, Math.min(100, state.radius * factor));
    positionCamera();
    invalidate();
  }
  function reset() {
    Object.assign(state, origin);
    objects.rotation.set(0, 0, 0);
    positionCamera();
    invalidate();
  }
  function down(event) {
    if (!enabled || event.button !== 0 || pointers.size >= 2) return;
    pointers.set(event.pointerId, [event.clientX, event.clientY]);
    // Synthetic QA events don't have a browser-managed pointer to capture.
    try { canvas.setPointerCapture(event.pointerId); } catch {}
  }
  function move(event) {
    const old = pointers.get(event.pointerId);
    if (!enabled || !old) return;
    const next = [event.clientX, event.clientY];
    pointers.set(event.pointerId, next);
    if (pointers.size === 1) {
      rotate((next[0] - old[0]) * .008, (next[1] - old[1]) * .008);
    } else {
      const [, other] = [...pointers].find(([id]) => id !== event.pointerId);
      const distance = point => Math.hypot(point[0] - other[0], point[1] - other[1]);
      if (distance(old) > 1 && distance(next) > 1) zoom(distance(old) / distance(next));
    }
  }
  function up(event) { pointers.delete(event.pointerId); }
  function wheel(event) {
    if (!enabled) return;
    event.preventDefault();
    zoom(Math.exp(event.deltaY * .001));
  }
  function setOrbitEnabled(value) {
    enabled = !!value;
    for (const id of pointers.keys()) {
      if (canvas.hasPointerCapture(id)) canvas.releasePointerCapture(id);
    }
    pointers.clear();
    canvas.style.touchAction = enabled ? 'none' : oldTouchAction;
  }
  function resize() {
    ({width, height} = canvas.getBoundingClientRect());
    if (width && height) {
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    }
    invalidate();
  }
  function visibility() {
    if (document.hidden) {
      if (frame !== null) cancelAnimationFrame(frame);
      frame = null;
      lastFrame = 0;
      pointers.clear();
    } else invalidate();
  }
  function contextLost(event) {
    event.preventDefault();
    lost = true;
    canvas.dataset.htmlappContextLost = 'true';
  }
  function contextRestored() {
    lost = false;
    delete canvas.dataset.htmlappContextLost;
    resize();
  }
  const listeners = {
    pointerdown: down, pointermove: move, pointerup: up, pointercancel: up,
    lostpointercapture: up, wheel, webglcontextlost: contextLost, webglcontextrestored: contextRestored
  };
  for (const [event, handler] of Object.entries(listeners)) {
    canvas.addEventListener(event, handler, event === 'wheel' ? {passive: false} : undefined);
  }
  document.addEventListener('visibilitychange', visibility);
  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(canvas);
  const visibilityObserver = new IntersectionObserver(invalidate);
  visibilityObserver.observe(canvas);
  setOrbitEnabled(enabled);
  reset();
  resize();

  function destroy() {
    if (dead) return;
    dead = true;
    if (frame !== null) cancelAnimationFrame(frame);
    resizeObserver.disconnect();
    visibilityObserver.disconnect();
    setOrbitEnabled(false);
    for (const [event, handler] of Object.entries(listeners)) canvas.removeEventListener(event, handler);
    document.removeEventListener('visibilitychange', visibility);
    disposeObjects(world);
    renderer.dispose();
    renderer.forceContextLoss();
  }
  return {
    THREE, world, camera, renderer, content, rotate, zoom, reset, render, resize, invalidate,
    get fps() { return fps; },
    get pose() { return [state.azimuth, state.elevation, state.radius, objects.rotation.x, objects.rotation.y]; },
    setOrbitEnabled, destroy,
    primitive(kind = 'box', color = 0x3576d3) {
      const geometries = {
        box: () => new THREE.BoxGeometry(1, 1, 1),
        sphere: () => new THREE.SphereGeometry(.5, 24, 16),
        cylinder: () => new THREE.CylinderGeometry(.5, .5, 1, 24),
        cone: () => new THREE.ConeGeometry(.5, 1, 24),
        plane: () => new THREE.PlaneGeometry(1, 1),
        torus: () => new THREE.TorusGeometry(.45, .14, 12, 32)
      };
      if (!Object.hasOwn(geometries, kind)) throw new RangeError('Unknown shape: ' + kind);
      const mesh = new THREE.Mesh(geometries[kind](), new THREE.MeshStandardMaterial({color}));
      content.add(mesh);
      invalidate();
      return mesh;
    }
  };
}

export function disposeObjects(root) {
  const geometries = new Set(), materials = new Set(), textures = new Set(), images = new Set();
  root.traverse(object => {
    if (object.geometry) geometries.add(object.geometry);
    for (const material of Array.isArray(object.material) ? object.material : [object.material]) {
      if (!material) continue;
      materials.add(material);
      for (const value of Object.values(material)) if (value?.isTexture) textures.add(value);
    }
  });
  for (const geometry of geometries) geometry.dispose();
  for (const material of materials) material.dispose();
  for (const texture of textures) {
    texture.dispose();
    if (typeof texture.image?.close === 'function') images.add(texture.image);
  }
  for (const image of images) image.close();
}
