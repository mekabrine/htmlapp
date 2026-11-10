#!/usr/bin/env node
'use strict';
const fs = require('fs');
const vm = require('vm');
const assert = require('node:assert/strict');
const path = require('path');

const root = path.resolve(__dirname, '..');
const native = fs.readFileSync(path.join(root, 'HTMLAppV3/NativeAPIBridge.swift'), 'utf8');
const editor = fs.readFileSync(path.join(root, 'HTMLAppV3/EditorWeb.swift'), 'utf8');

const nativeScript = native.split('enum HTMLNativeAPIScript {')[1]
  .split('static let source = #"""')[1].split('"""#')[0];
const viewportScript = editor.split('enum HTMLAppResponsiveViewport {')[1]
  .split('static let source = #"""')[1].split('"""#')[0];

async function testNativeRPC() {
  const sent = [];
  const listeners = new Map();
  const navigator = { userActivation: { isActive: true } };
  const window = {
    addEventListener(name, cb) { listeners.set(name, cb); },
    webkit: { messageHandlers: { htmlappNative: {
      postMessage(message) {
        sent.push(message);
        if (message.method === 'ui.controls' && message.args.title === 'Pending') return;
        if (message.method === 'ui.controls') {
          queueMicrotask(() => window.__htmlappNativeResolve(message.id, true, {cancelled: false, values: {sound: true}}));
          return;
        }
        if (message.method === 'network.request') return; // deliberately pending
        queueMicrotask(() => {
          window.__htmlappNativeResolve(message.id, true,
            message.method === 'capabilities.list'
              ? { methods: ['network.request', 'permissions.status'] }
              : { method: message.args?.method || '', hostPolicy: 'ask' });
        });
      }
    } } }
  };
  const element = attrs => ({
    hidden: false,
    getAttribute: key => attrs[key],
    setAttribute: (key, value) => { attrs[key] = value; },
    removeAttribute: key => { delete attrs[key]; }
  });
  const home = element({ 'data-htmlapp-screen': 'home' });
  const settings = element({ 'data-htmlapp-screen': 'settings' });
  const button = element({ 'data-htmlapp-go': 'settings' });
  const fallback = element({});
  const document = {
    querySelectorAll: selector => ({
      '[data-htmlapp-screen]': [home, settings],
      '[data-htmlapp-go]': [button],
      '[data-htmlapp-tab-fallback]': [fallback]
    })[selector] || [],
    addEventListener: (name, handler) => listeners.set(name, handler)
  };
  vm.runInNewContext(nativeScript, {
    window, document, navigator, setTimeout, clearTimeout, queueMicrotask, console,
    AbortController, DOMException, Response, Blob, atob
  }, { filename: 'HTMLNativeAPIScript.js' });
  const api = window.HTMLAppNative;
  assert.equal(api.protocolVersion, 2);
  assert.equal(await api.capabilities.has('network.request'), true);
  assert.equal(await api.capabilities.has('nonexistent.method'), false);
  assert.equal((await api.capabilities.describe('permissions.status')).method, 'permissions.status');
  assert.equal((await api.permissions.status('camera')).hostPolicy, 'ask');
  assert.equal(typeof api.audio.record, 'function');
  assert.equal(typeof api.video.capture, 'function');
  assert.equal(typeof api.ui.colorPicker, 'function');
  assert.equal(typeof api.network.status, 'function');
  assert.equal(typeof api.location.geocode, 'function');
  assert.equal(typeof api.location.distance, 'function');
  await api.network.status();
  await api.location.geocode('Central Park');
  await api.location.distance(0, 0, 1, 1);
  assert.ok(sent.some(msg => msg.method === 'network.status'));
  assert.ok(sent.some(msg => msg.method === 'location.geocode' && msg.args.query === 'Central Park'));
  assert.ok(sent.some(msg => msg.method === 'location.distance' && msg.args.latitude2 === 1));
  await api.audio.record({ maxDuration: 30 });
  await api.audio.levels();
  await api.audio.stopRecording();
  await api.video.capture({ maxDuration: 15 });
  await api.ui.colorPicker({ hex: '#445566' });
  await api.ui.list({ title: 'Choose', items: [{ id: 'a', title: 'One' }], allowsRefresh: true });
  await api.ui.listUpdate([{ id: 'a', title: 'Updated' }]);
  await api.ui.listDismiss();
  assert.ok(sent.some(msg => msg.method === 'audio.record' && msg.args.maxDuration === 30));
  assert.ok(sent.some(msg => msg.method === 'audio.stopRecording'));
  assert.ok(sent.some(msg => msg.method === 'video.capture' && msg.args.maxDuration === 15));
  assert.ok(sent.some(msg => msg.method === 'ui.colorPicker'));
  assert.ok(sent.some(msg => msg.method === 'ui.list' && msg.args.items[0].id === 'a'));
  assert.ok(sent.some(msg => msg.method === 'ui.listUpdate'));
  assert.ok(sent.some(msg => msg.method === 'ui.listDismiss'));

  const fields = [{type: 'toggle', id: 'sound', title: 'Sound effects', value: false}];
  assert.equal((await api.ui.controls({fields})).values.sound, true);
  assert.ok(sent.some(msg => msg.method === 'ui.controls' && msg.args.fields[0].value === false));
  navigator.userActivation.isActive = false;
  const sentBefore = sent.length;
  await assert.rejects(api.ui.controls({fields}), err => err.code === 'gesture_required');
  assert.equal(sent.length, sentBefore);
  navigator.userActivation.isActive = true;
  const formAbort = new AbortController();
  const form = api.ui.controls({title: 'Pending', fields}, {signal: formAbort.signal});
  const formRequest = sent.at(-1);
  formAbort.abort();
  await assert.rejects(form, err => err.code === 'cancelled');
  assert.equal(sent.at(-1).method, 'bridge.cancel');
  assert.equal(sent.at(-1).args.targetID, formRequest.id);

  const controller = new AbortController();
  const request = api.network.request({ url: 'https://example.org/data', signal: controller.signal });
  controller.abort();
  await assert.rejects(request, err => err.code === 'cancelled');
  assert.ok(sent.some(msg => msg.method === 'bridge.cancel' && msg.args.targetID));
  listeners.get('pagehide')();
  await api.ai.localComplete({ messages: [{ role: 'user', content: 'Hello' }] });
  assert.equal(sent.find(msg => msg.method === 'ai.localComplete').args.messages[0].content, 'Hello');
  await api.backend.status();
  await api.backend.read();
  await api.backend.notify({ title: 'Test', body: 'Hello' });
  assert.ok(sent.some(msg => msg.method === 'backend.status'));
  assert.ok(sent.some(msg => msg.method === 'backend.read'));
  const notification = sent.find(msg => msg.method === 'backend.notify');
  assert.equal(notification.args.body, 'Hello');
  assert.deepEqual(Object.keys(notification.args).sort(), ['body', 'title']);
  await api.ui.glassShow({ x: 20, y: 16, width: 140, height: 46 });
  assert.ok(sent.some(msg => msg.method === 'ui.glassShow' && msg.args.width === 140 && msg.args.y === 16));
  await api.ui.glassHide();
  assert.ok(sent.some(msg => msg.method === 'ui.glassHide'));
  await api.screens.configure({ items: [{ id: 'home' }, { id: 'settings' }] });
  assert.equal(home.hidden, false);
  assert.equal(settings.hidden, true);
  assert.equal(fallback.hidden, false);
  listeners.get('htmlapp:native-tab-select')({ detail: { id: 'home' } });
  assert.equal(fallback.hidden, true);
  listeners.get('click')({ target: { closest: () => button }, preventDefault() {} });
  assert.ok(sent.some(msg => msg.method === 'tabs.select' && msg.args.id === 'settings'));
  listeners.get('htmlapp:native-tab-select')({ detail: { id: 'settings' } });
  assert.equal(home.hidden, true);
  assert.equal(settings.hidden, false);
  assert.equal(button.getAttribute('aria-current'), 'page');
  assert.equal(await api.screens.go('unknown'), false);

}

async function testAISessionTools() {
  const sent = [];
  const transcript = [
    '{"type":"tool","name":"health.today","arguments":{}}',
    '{"type":"answer","text":"Health data was read after your approval."}'
  ];
  const window = {
    addEventListener() {},
    webkit: { messageHandlers: { htmlappNative: { postMessage(message) {
      sent.push(message);
      queueMicrotask(() => {
        const value = message.method === 'ai.complete'
          ? { text: transcript.shift() }
          : message.method === 'ui.alert'
            ? { id: 'allow', cancelled: false }
            : message.method === 'health.today'
              ? { steps: 1234 } : {};
        window.__htmlappNativeResolve(message.id, true, value);
      });
    } } } }
  };
  vm.runInNewContext(nativeScript, {
    window, setTimeout, clearTimeout, queueMicrotask, console,
    AbortController, DOMException, Response, Blob, atob
  });
  const api = window.HTMLAppNative;
  assert.equal(typeof api.ai.createSession, 'function');
  const session = api.ai.createSession({ tools: ['health.today', 'network.request'] });
  assert.deepEqual(Array.from(session.tools), ['health.today']);
  const answer = await session.ask('How active was I?');
  assert.match(answer.text, /after your approval/);
  const methods = sent.map(item => item.method);
  assert.ok(methods.indexOf('ui.alert') > methods.indexOf('ai.complete'));
  assert.ok(methods.indexOf('health.today') > methods.indexOf('ui.alert'));
  assert.equal(methods.filter(name => name === 'ai.complete').length, 2);
  assert.equal(session.history.length, 2);
  assert.equal(session.history[0].content, 'How active was I?');
  assert.equal(JSON.stringify(session.history).includes('1234'), false);
  session.clear();
  assert.equal(session.history.length, 0);
}

async function testAIStreaming() {
  const listeners = new Map();
  const tokens = [];
  const sent = [];
  const window = {
    addEventListener(name, fn) { listeners.set(name, fn); },
    removeEventListener(name) { listeners.delete(name); },
    webkit: { messageHandlers: { htmlappNative: { postMessage(msg) {
      sent.push(msg);
      queueMicrotask(() => {
        if (msg.method === 'ai.stream') {
          const listener = listeners.get('htmlapp:ai-stream');
          assert.equal(typeof listener, 'function');
          listener({ detail: { requestID: 'other-request', delta: 'SECRET', done: false } });
          listener({ detail: { requestID: msg.id, delta: 'Hello', done: false } });
          listener({ detail: { requestID: msg.id, delta: ' world', done: false } });
          window.__htmlappNativeResolve(msg.id, true,
            { text: 'Hello world', requestID: msg.id });
        } else window.__htmlappNativeResolve(msg.id, true, {});
      });
    } } } }
  };
  vm.runInNewContext(nativeScript, {
    window, setTimeout, clearTimeout, queueMicrotask, console,
    AbortController, DOMException, Response, Blob, atob
  });
  assert.equal(typeof window.HTMLAppNative.ai.stream, 'function');
  const answer = await window.HTMLAppNative.ai.stream({
    prompt: 'Say hello',
    onToken: value => tokens.push(value)
  });
  assert.equal(answer.text, 'Hello world');
  assert.deepEqual(tokens, ['Hello', ' world']);
  assert.equal(listeners.has('htmlapp:ai-stream'), false);
  assert.ok(sent.some(x => x.method === 'ai.stream' && x.args.prompt === 'Say hello'));
}

function testViewport() {
  const elements = {};
  const head = { appendChild(node) {
    if (node.name === 'viewport') elements.viewport = node;
    if (node.id) elements[node.id] = node;
  } };
  const root = { style: { setProperty() {} } };
  const document = {
    documentElement: root, head,
    querySelector(selector) { return selector === 'meta[name="viewport"]' ? (elements.viewport || null) : null; },
    getElementById(id) { return elements[id] || null; },
    createElement(tag) { return { tag, name: '', id: '', content: '', textContent: '' }; }
  };
  let enforce;
  class MutationObserver {
    constructor(callback) { enforce = callback; }
    observe() {}
    disconnect() {}
  }
  vm.runInNewContext(viewportScript, {
    document, MutationObserver, window: { addEventListener() {} }
  }, { filename: 'HTMLAppResponsiveViewport.js' });
  assert.ok(elements.viewport.content.includes('user-scalable=no'));
  assert.ok(elements.viewport.content.includes('maximum-scale=1'));
  assert.ok(elements.__htmlappViewportGuard.textContent.includes('overflow-x:clip'));
  assert.ok(elements.__htmlappViewportGuard.textContent.includes('data-htmlapp-horizontal-scroll'));
  assert.ok(elements.__htmlappViewportGuard.textContent.includes('overflow-wrap:anywhere'));
  elements.viewport.content = 'width=640, user-scalable=yes';
  enforce();
  assert.ok(elements.viewport.content.includes('user-scalable=no'));
  elements.__htmlappViewportGuard.textContent = 'body{overflow-x:scroll}';
  enforce();
  assert.ok(elements.__htmlappViewportGuard.textContent.includes('overflow-x:clip'));
}

(async () => {
  await testNativeRPC();
  await testAISessionTools();
  await testAIStreaming();
  testViewport();
  console.log('Native bridge and app viewport JS tests passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });

