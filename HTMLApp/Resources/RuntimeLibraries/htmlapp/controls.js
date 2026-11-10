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
