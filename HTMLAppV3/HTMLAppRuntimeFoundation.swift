import Foundation

/// Small, optional, forward-compatible JavaScript helpers for saved HTMLApps.
/// This does not grant new native permissions or keep JavaScript alive while
/// iOS suspends the WebView.
enum HTMLAppRuntimeFoundation {
    static let source = #"""
    (() => {
      if (window.HTMLAppRuntime || window.HTMLAppData) return;

      const nativeAPI = group => {
        const api = window.HTMLAppNative?.[group];
        if (!api) throw Object.assign(new Error('This HTMLApp feature is unavailable.'), { code: 'bridge_unavailable' });
        return api;
      };
      const validName = name => {
        if (typeof name !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(name))
          throw new TypeError('Collection or migration key must use 1–80 letters, digits, - or _.');
        return name;
      };
      const collection = name => {
        validName(name);
        return Object.freeze({
          put: (id, document) => nativeAPI('db').put(name, id, document),
          get: id => nativeAPI('db').get(name, id),
          remove: id => nativeAPI('db').delete(name, id),
          query: (options = {}) => nativeAPI('db').query(name, options),
          search: (text, limit = 50) => nativeAPI('db').search(name, text, limit),
          count: () => nativeAPI('db').count(name)
        });
      };
      const kv = Object.freeze({
        get: key => nativeAPI('appStorage').get(key),
        set: (key, value) => nativeAPI('appStorage').set(key, value),
        remove: key => nativeAPI('appStorage').remove(key)
      });
      const data = Object.freeze({
        collection,
        kv,
        migrate: async (name, targetVersion, migrations) => {
          validName(name);
          if (!Number.isInteger(targetVersion) || targetVersion < 0 || targetVersion > 1000)
            throw new RangeError('Invalid schema version.');
          const key = '__htmlappSchema:' + name;
          let current = Number(await kv.get(key) || 0);
          if (!Number.isInteger(current) || current < 0) throw new Error('Invalid saved schema version.');
          if (current > targetVersion) throw new Error('The app data belongs to a newer schema.');
          while (current < targetVersion) {
            const next = current + 1;
            const migrate = migrations?.[next];
            if (typeof migrate !== 'function')
              throw new Error('Missing migration for schema version ' + next);
            // Migrations must be idempotent; a kill between data writes and
            // the marker update can legitimately retry a step on next launch.
            await migrate({ from: current, to: next, collection, kv });
            await kv.set(key, next);
            current = next;
          }
          return current;
        }
      });

      const operations = new Map();
      const report = (onChange, state) => {
        if (typeof onChange === 'function') {
          try { onChange(state); } catch (error) { console.warn('HTMLApp operation status callback failed', error); }
        }
      };
      const runOperation = (name, work, onChange) => {
        validName(name);
        if (typeof work !== 'function') throw new TypeError('Provide a task function.');
        if (operations.has(name)) return operations.get(name).promise;
        const controller = new AbortController();
        report(onChange, { status: 'loading', name });
        // Race the cancellation signal so even work which ignores abort
        // settles its UI immediately. The underlying task receives the signal.
        const cancellation = () => Object.assign(new Error('Operation cancelled.'), {
          name: 'AbortError', code: 'cancelled'
        });
        let abortListener;
        const cancelled = new Promise((_, reject) => {
          abortListener = () => reject(cancellation());
          controller.signal.addEventListener('abort', abortListener, { once: true });
        });
        const workPromise = Promise.resolve().then(() => {
          if (controller.signal.aborted) throw cancellation();
          return work({ signal: controller.signal });
        });
        const promise = Promise.race([workPromise, cancelled])
          .then(value => {
            if (controller.signal.aborted) throw cancellation();
            report(onChange, { status: 'success', name });
            return value;
          })
          .catch(error => {
            report(onChange, {
              status: controller.signal.aborted ? 'cancelled' : 'error',
              name, error
            });
            throw error;
          })
          .finally(() => {
            controller.signal.removeEventListener('abort', abortListener);
            operations.delete(name);
          });
        operations.set(name, { controller, promise });
        return promise;
      };
      const cancelOperation = name => {
        const entry = operations.get(name);
        if (!entry) return false;
        entry.controller.abort();
        return true;
      };

      const onLifecycle = (state, callback) => {
        if (typeof callback !== 'function') throw new TypeError('Provide an event handler.');
        const handler = event => {
          if (event.detail?.state === state) callback(event.detail);
        };
        window.addEventListener('htmlapp:lifecycle', handler);
        return () => window.removeEventListener('htmlapp:lifecycle', handler);
      };
      const publishLifecycle = state => {
        window.dispatchEvent(new CustomEvent('htmlapp:lifecycle', { detail: { state } }));
      };
      document.addEventListener('visibilitychange', () => {
        publishLifecycle(document.hidden ? 'inactive' : 'active');
      });
      window.addEventListener('pagehide', () => {
        for (const item of operations.values()) item.controller.abort();
        publishLifecycle('background');
      });
      window.addEventListener('pageshow', () => publishLifecycle('resume'));

      // Host-owned declarative navigation: generated content supplies destinations,
      // while UIKit supplies the primary tab bar. Preview fallback is explicit.
      const configureNavigation = async () => {
        // Enforce native-tab fallback visibility even when app CSS uses !important.
        // This rule also protects apps using screens.configure directly.
        if (!document.getElementById('htmlapp-navigation-hidden-style')) {
          const style = document.createElement('style');
          style.id = 'htmlapp-navigation-hidden-style';
          style.textContent = '[data-htmlapp-screen][hidden],[data-htmlapp-tab-fallback][hidden]{display:none!important}';
          (document.head || document.documentElement).appendChild(style);
        }
        const manifest = document.getElementById?.('htmlapp-navigation');
        if (!manifest) return;
        try {
          const options = JSON.parse(manifest.textContent);
          if (!window.HTMLAppNative?.screens?.configure) throw new Error('Native screen router unavailable');
          await window.HTMLAppNative.screens.configure(options);
          window.__htmlappNavigationConfigured = true;
        } catch (error) {
          window.__htmlappNavigationError = String(error.message || error);
          console.error('Native navigation configuration failed', error);
        }
      };
      document.addEventListener('DOMContentLoaded', configureNavigation, { once: true });

      // Measure compositor frame cadence only while the app is actually visible.
      // This is a smoke metric, not a GPU benchmark or a guarantee of steady FPS.
      const measureFPS = ({ frames = 45, timeoutMs = 6000 } = {}) => {
        const samples = Math.max(10, Math.min(120, Math.floor(Number(frames) || 45)));
        const limit = Math.max(1000, Math.min(15000, Number(timeoutMs) || 6000));
        if (document.hidden || typeof requestAnimationFrame !== 'function')
          return Promise.reject(new Error('FPS measurement requires a visible app.'));
        return new Promise((resolve, reject) => {
          let start, count = 0, frameID, settled = false;
          const cleanup = () => {
            if (frameID !== undefined) cancelAnimationFrame(frameID);
            clearTimeout(timer);
            window.removeEventListener('pagehide', onPageHide);
          };
          const finish = (error, result) => {
            if (settled) return;
            settled = true;
            cleanup();
            if (error) reject(error);
            else resolve(result);
          };
          const onPageHide = () => finish(new Error('App was hidden during FPS measurement.'));
          const timer = setTimeout(() => finish(new Error('FPS measurement timed out: test while the app is visible.')), limit);
          window.addEventListener('pagehide', onPageHide, { once: true });
          const step = now => {
            if (document.hidden) return finish(new Error('App was hidden during FPS measurement.'));
            if (start === undefined) start = now;
            if (++count > samples) {
              const durationMs = Math.max(1, now - start);
              return finish(null, { fps: Math.round(samples * 100000 / durationMs) / 100, frames: samples, durationMs });
            }
            frameID = requestAnimationFrame(step);
          };
          frameID = requestAnimationFrame(step);
        });
      };

      const runtime = Object.freeze({
        runOperation, cancelOperation, measureFPS,
        get activeOperations() { return Array.from(operations.keys()); },
        get isVisible() { return !document.hidden; },
        onActive: cb => onLifecycle('active', cb),
        onInactive: cb => onLifecycle('inactive', cb),
        onBackground: cb => onLifecycle('background', cb),
        onResume: cb => onLifecycle('resume', cb)
      });
      Object.defineProperty(window, 'HTMLAppData', {
        configurable: false, enumerable: true, value: data
      });
      Object.defineProperty(window, 'HTMLAppRuntime', {
        configurable: false, enumerable: true, value: runtime
      });
    })();
    """#
}
