#!/usr/bin/env node
// Exercise the exact bundled JavaScript with a small DOM and the same JSON
// serialization contract as HTMLAppNative.appStorage. No provider/network calls.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {randomUUID} = require('node:crypto');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../HTMLAppV3/ForgeStarterApps.swift'), 'utf8');
const shell = source.match(/private static let shell = #"""([\s\S]*?)"""#/)[1];
const starters = [...source.matchAll(/\.init\(id: "([^"]+)", title: "([^"]+)"[\s\S]*?body: #"""([\s\S]*?)"""#,\s*script: #"""([\s\S]*?)"""#\)/g)]
    .map(([, id, title, body, script]) => ({id, title, body, script}));
assert.equal(starters.length, 3, 'Every starter must be included in the behavior checks');

function element() {
    return {value: '', textContent: '', hidden: false, disabled: false, children: [], dataset: {},
        append(...nodes) { this.children.push(...nodes); },
        replaceChildren(...nodes) { this.children = nodes; },
        setAttribute(k, v) { this[k] = v; },
        removeAttribute(k) { if(k === 'data-error') delete this.dataset.error; else delete this[k]; },
        reset() {}};
}
async function open(id, {preview = false, storage = new Map(), failWrite = false, now = 1000000} = {}) {
    const starter = starters.find(s => s.id === id);
    const html = shell.replace('__TITLE__', starter.title).replace('__BODY__', starter.body).replace('__SCRIPT__', starter.script);
    const nodes = Object.fromEntries([...html.matchAll(/id="([^"]+)"/g)].map(([,name]) => [name, element()]));
    if(nodes.minutes) nodes.minutes.value = '25';
    let writes = 0, time = now, tick;
    class Clock extends Date { static now() { return time; } }
    const context = {
        document: {getElementById: id => nodes[id], createElement: () => element()},
        crypto: {randomUUID}, Date: Clock, Intl, console,
        setInterval: fn => {tick = fn; return 1;},
        window: {__HTMLAPP_STARTER_PREVIEW__: preview, HTMLAppNative: {appStorage: {
            get: async key => storage.has(key) ? JSON.parse(storage.get(key)) : null,
            set: async (key, value) => {if(failWrite) throw new Error('Disk full'); writes++; storage.set(key, JSON.stringify(value));}
        }}}
    };
    const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
    await vm.runInNewContext(script, context, {timeout: 1000});
    return {nodes, storage, writes: () => writes, advance: ms => {time += ms; tick?.();},
        submit: async () => nodes.entry.onsubmit({preventDefault(){}, target: nodes.entry})};
}
(async () => {
    const expense = await open('expenses');
    expense.nodes.label.value = '<img onerror=alert(1)>';
    expense.nodes.amount.value = '12.34';
    await expense.submit();
    assert.equal(expense.nodes.total.textContent, '$12.34');
    assert.equal(expense.nodes.items.children[0].children[0].textContent, '<img onerror=alert(1)> · $12.34', 'User text is rendered as text, never HTML');
    await expense.nodes.items.children[0].children[1].onclick();
    assert.equal(expense.nodes.total.textContent, '$0.00');
    await expense.nodes.undo.onclick();
    assert.equal(expense.nodes.total.textContent, '$12.34');
    const reloaded = await open('expenses', {storage: expense.storage});
    assert.equal(reloaded.nodes.total.textContent, '$12.34', 'Purchases survive reopening');
    const before = expense.writes(); expense.nodes.amount.value = '-2'; await expense.submit();
    assert.equal(expense.writes(), before, 'Invalid input never reaches storage');
    const failed = await open('expenses', {storage: expense.storage, failWrite: true});
    failed.nodes.label.value='Unsaved'; failed.nodes.amount.value='5'; await failed.submit();
    assert.equal(failed.nodes.total.textContent, '$12.34', 'Failed writes retain the last committed view');
    assert.match(failed.nodes['storage-status'].textContent, /Could not save/);

    const workout = await open('workouts');
    workout.nodes.exercise.value='Squat'; workout.nodes.sets.value='3'; workout.nodes.reps.value='8'; await workout.submit();
    assert.match(workout.nodes.items.children[0].children[0].textContent, /Squat · 3 × 8/);
    await workout.nodes.items.children[0].children[1].onclick();
    assert.equal(workout.nodes.undo.hidden, false);
    await workout.nodes.undo.onclick();
    const again = await open('workouts', {storage: workout.storage});
    assert.match(again.nodes.items.children[0].children[0].textContent, /Squat/);

    const timer = await open('timer');
    await timer.nodes.start.onclick(); timer.advance(60000);
    assert.equal(timer.nodes.clock.textContent, '24:00');
    await timer.nodes.start.onclick(); timer.advance(60000);
    assert.equal(timer.nodes.clock.textContent, '24:00', 'Paused sessions do not count down');
    const resumed = await open('timer', {storage: timer.storage, now: 1120000});
    assert.equal(resumed.nodes.clock.textContent, '24:00');
    await resumed.nodes.start.onclick(); resumed.advance(1440000);
    assert.match(resumed.nodes.finished.textContent, /complete/);
    await resumed.nodes.reset.onclick(); assert.equal(resumed.nodes.clock.textContent, '25:00');
    resumed.nodes.minutes.value='0'; await resumed.nodes.minutes.onchange();
    assert.equal(resumed.nodes.minutes.value, 25, 'Invalid intervals are rejected');

    for (const {id} of starters) {
        const trial = await open(id, {preview: true});
        if (id === 'timer') await trial.nodes.start.onclick();
        else {trial.nodes.label && (trial.nodes.label.value='Trial');trial.nodes.amount && (trial.nodes.amount.value='1');trial.nodes.exercise && (trial.nodes.exercise.value='Trial');trial.nodes.sets && (trial.nodes.sets.value='1');trial.nodes.reps && (trial.nodes.reps.value='1');await trial.submit();}
        assert.equal(trial.writes(), 0, 'Trials never write personal data');
        assert.match(trial.nodes['storage-status'].textContent, /Trial mode/);
        const corrupt = new Map([['starter.state', JSON.stringify('{broken')]]);
        const broken = await open(id, {storage: corrupt});
        assert.match(broken.nodes['storage-status'].textContent, /Nothing was overwritten/);
        assert.equal(broken.writes(), 0);
    }
    console.log('Starter apps: persistence, input validation, remove/undo, timer recovery, write failures, corrupt data, and isolated trials passed.');
})().catch(error => {console.error(error); process.exitCode=1;});
