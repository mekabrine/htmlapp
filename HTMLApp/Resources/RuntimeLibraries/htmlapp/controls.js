class HTMLAppSwitch extends HTMLElement {
  static get observedAttributes() { return ['checked', 'disabled', 'label']; }

  constructor() {
    super();
    const root = this.attachShadow({mode: 'open'});
    root.innerHTML = `
      <style>
        :host{display:inline-flex;flex:none;align-self:center;vertical-align:middle}
        :host([hidden]){display:none}
        label{position:relative;display:grid;place-items:center;min-width:44px;min-height:44px;cursor:pointer}
        input{position:absolute;inset:0;margin:0;width:100%;height:100%;opacity:0;cursor:inherit}
        .track{--w:46px;--h:26px;--inset:3px;--thumb:calc(var(--h) - 2 * var(--inset));
          position:relative;box-sizing:border-box;width:var(--w);height:var(--h);border-radius:999px;
          background:var(--ha-switch-off,#62656b);box-shadow:inset 0 0 0 1px rgb(0 0 0 / 18%);pointer-events:none;direction:ltr}
        :host([size="small"]) .track{--w:38px;--h:22px}
        :host([size="large"]) .track{--w:54px;--h:30px}
        .thumb{position:absolute;left:var(--inset);top:var(--inset);width:var(--thumb);height:var(--thumb);
          border-radius:50%;background:var(--ha-switch-thumb,#fff);box-shadow:0 1px 3px rgb(0 0 0 / 28%)}
        input:checked + .track{background:var(--ha-accent,#1968cd)}
        input:checked + .track .thumb{left:calc(100% - var(--thumb) - var(--inset))}
        input:focus-visible + .track{outline:2px solid var(--ha-accent,#1968cd);outline-offset:3px}
        input:disabled + .track{opacity:.5}
        input:disabled{cursor:default}
      </style>
      <label><input type="checkbox" role="switch"><span class="track" aria-hidden="true"><span class="thumb"></span></span></label>`;
    this.input = root.querySelector('input');
    this.input.setAttribute('aria-label', 'Toggle setting');
    this.input.addEventListener('change', () => {
      this.checked = this.input.checked;
      this.dispatchEvent(new Event('change', {bubbles: true, composed: true}));
    });
  }

  attributeChangedCallback(name, oldValue, value) {
    if (name === 'checked') this.input.checked = value !== null;
    if (name === 'disabled') this.input.disabled = value !== null;
    if (name === 'label') this.input.setAttribute('aria-label', value || 'Toggle setting');
  }

  get checked() { return this.hasAttribute('checked'); }
  set checked(value) { this.toggleAttribute('checked', Boolean(value)); }
  get disabled() { return this.hasAttribute('disabled'); }
  set disabled(value) { this.toggleAttribute('disabled', Boolean(value)); }
  focus(options) { this.input.focus(options); }
}

if (!customElements.get('htmlapp-switch')) customElements.define('htmlapp-switch', HTMLAppSwitch);

// Text-only confirmation avoids HTML injection. Native dialog provides focus
// trapping, keyboard dismissal and modal accessibility on supported WebKit.
export function confirm({title = 'Confirm', message = '', accept = 'Continue', cancel = 'Cancel'} = {}) {
  return new Promise(resolve => {
    const previous = document.activeElement;
    const dialog = document.createElement('dialog'); dialog.className = 'ha-dialog';
    const heading = document.createElement('h2'); heading.textContent = title;
    const text = document.createElement('p'); text.textContent = message;
    const actions = document.createElement('div'); actions.className = 'ha-dialog-actions';
    const no = document.createElement('button'), yes = document.createElement('button');
    for (const button of [no, yes]) { button.type = 'button'; button.className = 'ha-button'; }
    no.textContent = cancel; yes.textContent = accept;
    actions.append(no, yes); dialog.append(heading, text, actions);
    dialog.setAttribute('aria-label', String(title));
    let done = false;
    const finish = value => { if (done) return; done = true; dialog.remove(); previous?.focus(); resolve(value); };
    no.onclick = () => finish(false); yes.onclick = () => finish(true);
    dialog.addEventListener('cancel', e => { e.preventDefault(); finish(false); });
    document.body.append(dialog);
    if (typeof dialog.showModal !== 'function') { finish(globalThis.confirm(String(message))); return; }
    dialog.showModal(); no.focus();
  });
}

// Buttons supply aria-controls pointing at existing panels; no HTML is built.
// Returns cleanup for apps which replace a screen dynamically.
export function tabs(root) {
  const buttons = [...root.querySelectorAll('[aria-controls]')];
  root.setAttribute('role', 'tablist');
  const select = button => {
    for (const item of buttons) {
      const active = item === button;
      item.setAttribute('role', 'tab'); item.setAttribute('aria-selected', String(active));
      item.tabIndex = active ? 0 : -1;
      const panel = document.getElementById(item.getAttribute('aria-controls'));
      if (panel) { panel.hidden = !active; panel.setAttribute('role', 'tabpanel'); }
    }
  };
  const click = e => { const button = buttons.find(b => b === e.target || b.contains(e.target)); if (button) select(button); };
  const key = e => {
    const i = buttons.indexOf(document.activeElement); if (i < 0 || !buttons.length) return;
    let n;
    if (e.key === 'ArrowRight') n = (i + 1) % buttons.length;
    if (e.key === 'ArrowLeft') n = (i - 1 + buttons.length) % buttons.length;
    if (e.key === 'Home') n = 0;
    if (e.key === 'End') n = buttons.length - 1;
    if (n !== undefined) { e.preventDefault(); select(buttons[n]); buttons[n].focus(); }
  };
  if (buttons.length) select(buttons.find(b => b.getAttribute('aria-selected') === 'true') || buttons[0]);
  root.addEventListener('click', click); root.addEventListener('keydown', key);
  return () => { root.removeEventListener('click', click); root.removeEventListener('keydown', key); };
}

