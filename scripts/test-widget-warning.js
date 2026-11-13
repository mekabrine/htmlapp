const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync('HTMLAppV3/NativeAPIBridge.swift','utf8');
const block = source.split("        const error = new Error(value?.message")[1].split('        item.reject(error);')[0];
function render(userAgent, wide) {
  let panel;
  const element = () => ({style:{}, setAttribute(){}, replaceChildren(){}, append(){}, remove(){}});
  const document = {getElementById:()=>null, createElement:element, body:{appendChild(e){panel=e;}}};
  const run = new Function('document','navigator','window','item','value',
    "const error = new Error(value?.message" + block);
  run(document,{userAgent},{matchMedia:()=>({matches:wide})},{method:'widgets.configure'}, {message:'Storage failed',code:'app_group_unavailable'});
  return panel.style.cssText;
}
assert.match(render('iPhone',false),/top:calc\(env\(safe-area-inset-top/);
assert.match(render('iPhone',true),/top:calc\(env\(safe-area-inset-top/);
assert.doesNotMatch(render('iPhone',true),/bottom:/);
assert.match(render('Macintosh',true),/bottom:12px/);
console.log('Widget error placement passed for portrait/landscape phones and tablet');
