import * as THREE from '../three/build/three.module.js';
import {gameLoop} from './kits.js';
export function scene(canvas,{background=0x101822}={}) {
  const renderer=new THREE.WebGLRenderer({canvas,antialias:true});renderer.setPixelRatio(Math.min(devicePixelRatio||1,2));
  const world=new THREE.Scene();world.background=new THREE.Color(background);
  const camera=new THREE.PerspectiveCamera(50,1,.1,1000);camera.position.set(0,2,5);camera.lookAt(0,0,0);
  world.add(new THREE.HemisphereLight(0xffffff,0x444444,2));
  const light=new THREE.DirectionalLight(0xffffff,3);light.position.set(3,5,2);world.add(light);
  const resize=()=>{const {width,height}=canvas.getBoundingClientRect();renderer.setSize(Math.max(1,width),Math.max(1,height),false);camera.aspect=width/Math.max(1,height);camera.updateProjectionMatrix();};
  const observer=new ResizeObserver(resize);observer.observe(canvas);resize();
  const loop=gameLoop({render:()=>renderer.render(world,camera)});
  return {THREE,world,camera,renderer,primitive(kind='box',color=0x3576d3){const geometry=kind==='sphere'?new THREE.SphereGeometry(.5,24,16):new THREE.BoxGeometry(1,1,1);const mesh=new THREE.Mesh(geometry,new THREE.MeshStandardMaterial({color}));world.add(mesh);return mesh;},destroy(){loop.destroy();observer.disconnect();world.traverse(object=>{object.geometry?.dispose();const materials=Array.isArray(object.material)?object.material:[object.material];materials.forEach(m=>m?.dispose());});renderer.dispose();}};
}
