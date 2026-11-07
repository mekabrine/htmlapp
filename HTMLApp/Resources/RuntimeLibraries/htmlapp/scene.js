import * as THREE from '../three/build/three.module.js';
import {gameLoop} from './kits.js';

// Zero-CDN WebGL scene. orbit controls and shapes are reusable infrastructure,
// not promises of AR, photorealism, or iOS WebGPU availability.
export function scene(canvas,{background=0x101822,orbit=true}={}) {
  const renderer=new THREE.WebGLRenderer({canvas,antialias:true});
  renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio||1,2));
  const world=new THREE.Scene();world.background=new THREE.Color(background);
  const camera=new THREE.PerspectiveCamera(50,1,.1,1000);
  world.add(new THREE.HemisphereLight(0xffffff,0x444444,2));
  const light=new THREE.DirectionalLight(0xffffff,3);light.position.set(3,5,2);world.add(light);

  const cameraState={radius:5,azimuth:0,elevation:.38};
  let orbitEnabled=!!orbit,dragging=false,lastX=0,lastY=0;
  const positionCamera=()=>{
    const {radius,azimuth,elevation}=cameraState;
    camera.position.set(radius*Math.sin(azimuth)*Math.cos(elevation),
      radius*Math.sin(elevation),radius*Math.cos(azimuth)*Math.cos(elevation));
    camera.lookAt(0,0,0);
  };
  positionCamera();
  const down=e=>{
    if(!orbitEnabled)return;
    dragging=true;lastX=e.clientX;lastY=e.clientY;canvas.setPointerCapture?.(e.pointerId);
  };
  const move=e=>{
    if(!dragging||!orbitEnabled)return;
    cameraState.azimuth-=(e.clientX-lastX)*.006;
    cameraState.elevation=Math.max(-1.45,Math.min(1.45,
      cameraState.elevation+(e.clientY-lastY)*.006));
    lastX=e.clientX;lastY=e.clientY;positionCamera();
  };
  const up=()=>{dragging=false;};
  const wheel=e=>{
    if(!orbitEnabled)return;
    e.preventDefault();cameraState.radius=Math.max(.8,Math.min(100,cameraState.radius*Math.exp(e.deltaY*.001)));
    positionCamera();
  };
  canvas.addEventListener('pointerdown',down);canvas.addEventListener('pointermove',move);
  canvas.addEventListener('pointerup',up);canvas.addEventListener('pointercancel',up);
  canvas.addEventListener('wheel',wheel,{passive:false});

  const resize=()=>{
    const {width,height}=canvas.getBoundingClientRect();
    renderer.setSize(Math.max(1,width),Math.max(1,height),false);
    camera.aspect=Math.max(1,width)/Math.max(1,height);camera.updateProjectionMatrix();
  };
  const observer=new ResizeObserver(resize);observer.observe(canvas);resize();
  const loop=gameLoop({render:()=>renderer.render(world,camera)});
  return {
    THREE,world,camera,renderer,
    get fps(){return loop.fps;},
    setOrbitEnabled(enabled){orbitEnabled=!!enabled;dragging=false;},
    primitive(kind='box',color=0x3576d3){
      const geometries={
        box:()=>new THREE.BoxGeometry(1,1,1),
        sphere:()=>new THREE.SphereGeometry(.5,24,16),
        cylinder:()=>new THREE.CylinderGeometry(.5,.5,1,24),
        cone:()=>new THREE.ConeGeometry(.5,1,24),
        plane:()=>new THREE.PlaneGeometry(1,1),
        torus:()=>new THREE.TorusGeometry(.45,.14,12,32)
      };
      if(!geometries[kind])throw new RangeError('Unknown primitive shape: '+kind);
      const mesh=new THREE.Mesh(geometries[kind](),new THREE.MeshStandardMaterial({color}));
      world.add(mesh);return mesh;
    },
    destroy(){
      loop.destroy();observer.disconnect();
      canvas.removeEventListener('pointerdown',down);canvas.removeEventListener('pointermove',move);
      canvas.removeEventListener('pointerup',up);canvas.removeEventListener('pointercancel',up);
      canvas.removeEventListener('wheel',wheel);
      world.traverse(object=>{
        object.geometry?.dispose();
        const materials=Array.isArray(object.material)?object.material:[object.material];
        materials.forEach(material=>material?.dispose());
      });
      renderer.dispose();
    }
  };
}
