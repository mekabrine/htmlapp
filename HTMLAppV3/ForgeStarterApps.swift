import Foundation

/// Bundled, offline starting points. Trying and saving them never calls a provider.
struct ForgeStarterApp: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let detail: String
    let prompt: String
    let body: String
    let script: String

    var html: String {
        Self.shell.replacingOccurrences(of: "__TITLE__", with: title)
            .replacingOccurrences(of: "__BODY__", with: body)
            .replacingOccurrences(of: "__SCRIPT__", with: script)
    }

    static let all: [ForgeStarterApp] = [
        .init(id: "expenses", title: "Pocket Expenses", symbol: "creditcard",
              detail: "Log purchases, see a total, and undo a removal. No account needed.",
              prompt: "Customize this offline expense tracker. Keep purchase logging, totals, persistent data and undo; ask me which currency and categories I prefer.",
              body: #"""
              <p>Keep track of the little purchases.</p><h2 id="total">$0.00</h2>
              <form id="entry" hidden><label>Purchase<input id="label" required maxlength="100" autocomplete="off"></label>
              <label>Amount (USD)<input id="amount" type="number" min="0.01" max="999999" step="0.01" inputmode="decimal" required></label><button>Add purchase</button></form>
              <ul id="items"></ul><button id="undo" hidden>Undo removal</button>
              """#,
              script: #"""
              const money = n => new Intl.NumberFormat(undefined,{style:'currency',currency:'USD'}).format(n/100);
              let rows = await read([]), removed;
              if (!Array.isArray(rows) || !rows.every(r=>r && typeof r.id==='string' && typeof r.label==='string' && Number.isInteger(r.cents) && r.cents>0)) throw new Error('Saved purchases could not be read.');
              function render() {
                document.getElementById('total').textContent = money(rows.reduce((sum,r)=>sum+r.cents,0));
                const list=document.getElementById('items'); list.replaceChildren();
                if (!rows.length) { const li=document.createElement('li'); li.textContent='No purchases yet. Add your first above.'; list.append(li); }
                rows.forEach(row=>{
                  const li=document.createElement('li'), text=document.createElement('span'), button=document.createElement('button');
                  text.textContent=row.label+' · '+money(row.cents); button.textContent='Remove'; button.setAttribute('aria-label','Remove '+row.label);
                  button.onclick=async()=>{ const next=rows.filter(r=>r.id!==row.id); if(await write(next)){removed={row,index:rows.indexOf(row)}; rows=next; render();} };
                  li.append(text,button); list.append(li);
                });
                document.getElementById('undo').hidden=!removed;
              }
              document.getElementById('entry').onsubmit=async event=>{
                event.preventDefault(); const label=document.getElementById('label').value.trim(), amount=Number(document.getElementById('amount').value);
                if(!label||!Number.isFinite(amount)||amount<=0||amount>999999)return;
                const next=[{id:newID(),label,cents:Math.round(amount*100)},...rows];
                if(await write(next)){rows=next;event.target.reset();render();}
              };
              document.getElementById('undo').onclick=async()=>{if(!removed)return;const next=[...rows];next.splice(removed.index,0,removed.row);if(await write(next)){rows=next;removed=null;render();}};
              document.getElementById('entry').hidden=false;render();
              """#),
        .init(id: "timer", title: "Focus Timer", symbol: "timer",
              detail: "Choose a study interval, pause it, and resume after reopening. Alerts stay inside the app.",
              prompt: "Customize this offline study timer. Preserve start, pause, reset and saved progress. Add a simple break workflow and keep the interface accessible.",
              body: #"""
              <p>One focused session at a time. Keep the app open to see when time is up.</p>
              <label>Session minutes<input id="minutes" type="number" min="1" max="180" value="25" inputmode="numeric"></label>
              <h2 id="clock" role="timer">25:00</h2><p id="finished" role="status"></p>
              <button id="start" disabled>Start</button><button id="reset" disabled>Reset</button>
              """#,
              script: #"""
              let state=await read({remaining:1500000,end:null,minutes:25});
              if(!state||!Number.isFinite(state.remaining)||state.remaining<0||!Number.isInteger(state.minutes)||state.minutes<1||state.minutes>180||(state.end!==null&&!Number.isFinite(state.end)))throw new Error('Saved timer could not be read.');
              const minutes=document.getElementById('minutes');minutes.value=state.minutes;
              const remaining=()=>state.end?Math.max(0,state.end-Date.now()):state.remaining;
              function render(){const ms=remaining(),seconds=Math.ceil(ms/1000);document.getElementById('clock').textContent=String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0');document.getElementById('start').textContent=state.end&&ms>0?'Pause':ms===0?'Start again':'Start';minutes.disabled=!!state.end&&ms>0;document.getElementById('finished').textContent=ms===0?'Session complete. Take a break.':'';}
              document.getElementById('start').onclick=async()=>{let next;if(state.end&&remaining()>0){next={...state,remaining:remaining(),end:null};}else{const count=remaining()||state.minutes*60000;next={...state,remaining:count,end:Date.now()+count};}if(await write(next)){state=next;render();}};
              document.getElementById('reset').onclick=async()=>{const next={...state,remaining:state.minutes*60000,end:null};if(await write(next)){state=next;render();}};
              minutes.onchange=async()=>{const count=Number(minutes.value);if(!Number.isInteger(count)||count<1||count>180){minutes.value=state.minutes;return;}const next={minutes:count,remaining:count*60000,end:null};if(await write(next)){state=next;render();}else{minutes.value=state.minutes;}};
              document.getElementById('start').disabled=false;document.getElementById('reset').disabled=false;render();setInterval(render,500);
              """#),
        .init(id: "workouts", title: "Workout Notes", symbol: "figure.strengthtraining.traditional",
              detail: "Record exercises, sets, and reps without requesting Health access.",
              prompt: "Customize this offline workout log. Keep exercise, sets and reps, persistent history, input validation and undo. Add a useful weekly summary without requiring Health access.",
              body: #"""
              <p>A simple record of the work you put in.</p><form id="entry" hidden>
              <label>Exercise<input id="exercise" required maxlength="100"></label>
              <label>Sets<input id="sets" type="number" min="1" max="100" value="3" required></label>
              <label>Reps per set<input id="reps" type="number" min="1" max="1000" value="10" required></label><button>Log exercise</button></form>
              <ul id="items"></ul><button id="undo" hidden>Undo removal</button>
              """#,
              script: #"""
              let rows=await read([]),removed;if(!Array.isArray(rows)||!rows.every(r=>r&&typeof r.id==='string'&&typeof r.exercise==='string'&&Number.isInteger(r.sets)&&r.sets>=1&&Number.isInteger(r.reps)&&r.reps>=1&&Number.isFinite(Date.parse(r.date))))throw new Error('Saved workouts could not be read.');
              function render(){const list=document.getElementById('items');list.replaceChildren();if(!rows.length){const li=document.createElement('li');li.textContent='No exercises logged. Start with one set.';list.append(li);}rows.forEach(row=>{const li=document.createElement('li'),text=document.createElement('span'),button=document.createElement('button');text.textContent=row.exercise+' · '+row.sets+' × '+row.reps+' · '+new Date(row.date).toLocaleDateString();button.textContent='Remove';button.setAttribute('aria-label','Remove '+row.exercise);button.onclick=async()=>{const next=rows.filter(r=>r.id!==row.id);if(await write(next)){removed={row,index:rows.indexOf(row)};rows=next;render();}};li.append(text,button);list.append(li);});document.getElementById('undo').hidden=!removed;}
              document.getElementById('entry').onsubmit=async event=>{event.preventDefault();const exercise=document.getElementById('exercise').value.trim(),sets=Number(document.getElementById('sets').value),reps=Number(document.getElementById('reps').value);if(!exercise||!Number.isInteger(sets)||sets<1||sets>100||!Number.isInteger(reps)||reps<1||reps>1000)return;const next=[{id:newID(),date:new Date().toISOString(),exercise,sets,reps},...rows];if(await write(next)){rows=next;document.getElementById('exercise').value='';render();}};
              document.getElementById('undo').onclick=async()=>{if(!removed)return;const next=[...rows];next.splice(removed.index,0,removed.row);if(await write(next)){rows=next;removed=null;render();}};
              document.getElementById('entry').hidden=false;render();
              """#)
    ]

    private static let shell = #"""
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="htmlapp-starter" content="1"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>__TITLE__</title>
    <style>:root{color-scheme:light dark;font:17px system-ui;--accent:#7352c6}*{box-sizing:border-box}body{margin:0;background:Canvas;color:CanvasText}main{max-width:40rem;margin:auto;padding:calc(1rem + env(safe-area-inset-top)) max(1rem,env(safe-area-inset-right)) calc(2rem + env(safe-area-inset-bottom)) max(1rem,env(safe-area-inset-left))}h1{font-size:2rem}h2{font-size:2.5rem;font-variant-numeric:tabular-nums}label{display:block;margin:1rem 0}input,button{font:inherit;min-height:44px;border-radius:.6rem;padding:.65rem;max-width:100%}input{display:block;width:100%;margin-top:.35rem;border:1px solid GrayText;background:Canvas;color:CanvasText}button{background:var(--accent);color:white;border:0;cursor:pointer;margin:.25rem .25rem .25rem 0}button:disabled{opacity:.5;cursor:default}button:focus-visible,input:focus-visible{outline:3px solid Highlight;outline-offset:3px}ul{list-style:none;padding:0}li{display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.7rem 0;border-bottom:1px solid GrayText;overflow-wrap:anywhere}li span{min-width:0}li button{flex-shrink:0}#storage-status{font-size:.85rem}#storage-status[data-error]{color:LinkText}[hidden]{display:none!important}@media(max-width:340px){li{align-items:flex-start;flex-direction:column}}</style></head>
    <body><main><h1>__TITLE__</h1><p id="storage-status" role="status">Loading saved data…</p>__BODY__</main><script>
    (async()=>{'use strict';
      const status=document.getElementById('storage-status');
      // PREVIEW has no native data access. Its trial values live only in memory.
      const native=window.HTMLAppNative, preview=window.__HTMLAPP_STARTER_PREVIEW__===true;
      const newID=()=>globalThis.crypto?.randomUUID?.() || Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
      let busy=false;
      async function read(fallback){if(preview){status.textContent='Trial mode. Save the app before entering data you want to keep.';return fallback;}if(!native?.appStorage)throw new Error('Saved storage is unavailable. Reopen this app in HTMLApp.');const raw=await native.appStorage.get('starter.state');status.textContent='Saved on this device.';return raw==null?fallback:typeof raw==='string'?JSON.parse(raw):raw;}
      async function write(value){if(busy)return false;busy=true;try{if(!preview){if(!native?.appStorage)throw new Error('Saved storage is unavailable.');await native.appStorage.set('starter.state',JSON.stringify(value));}status.removeAttribute('data-error');status.textContent=preview?'Trial mode. Save the app to keep future entries.':'Saved on this device.';return true;}catch(error){status.dataset.error='true';status.textContent='Could not save. Your previous data is unchanged. '+error.message;return false;}finally{busy=false;}}
      try{__SCRIPT__}catch(error){status.dataset.error='true';status.textContent='Could not load saved data. Nothing was overwritten. '+error.message;}
    })();</script></body></html>
    """#
}
