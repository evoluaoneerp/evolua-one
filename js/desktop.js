const registry = new Map();
let zCounter = 20;

function clamp(value, min, max) { return Math.min(max, Math.max(min, value)); }

export class DesktopManager {
  constructor({ desktop, taskbarApps, startMenu }) {
    this.desktop = desktop;
    this.taskbarApps = taskbarApps;
    this.startMenu = startMenu;
    this.windows = registry;
  }

  register(id, options) {
    const win = document.querySelector(`[data-window="${id}"]`);
    if (!win) return;
    const record = {
      id,
      win,
      title: options.title || id,
      icon: options.icon || '▣',
      minimized: false,
      maximized: false,
      prevRect: null
    };
    registry.set(id, record);
    this.bindWindow(record);
  }

  bindWindow(record) {
    const { win } = record;
    const titlebar = win.querySelector('.window-titlebar');
    win.querySelector('[data-window-close]')?.addEventListener('click', () => this.close(record.id));
    win.querySelector('[data-window-minimize]')?.addEventListener('click', () => this.minimize(record.id));
    win.querySelector('[data-window-maximize]')?.addEventListener('click', () => this.toggleMaximize(record.id));
    win.addEventListener('pointerdown', () => this.focus(record.id));
    titlebar?.addEventListener('dblclick', event => {
      if (!event.target.closest('button')) this.toggleMaximize(record.id);
    });

    let drag = null;
    titlebar?.addEventListener('pointerdown', event => {
      if (event.target.closest('button') || record.maximized || window.innerWidth < 720) return;
      drag = {
        x: event.clientX,
        y: event.clientY,
        left: win.offsetLeft,
        top: win.offsetTop
      };
      titlebar.setPointerCapture(event.pointerId);
      this.focus(record.id);
    });
    titlebar?.addEventListener('pointermove', event => {
      if (!drag) return;
      const maxLeft = Math.max(0, this.desktop.clientWidth - 180);
      const maxTop = Math.max(0, this.desktop.clientHeight - 100);
      win.style.left = `${clamp(drag.left + event.clientX - drag.x, 0, maxLeft)}px`;
      win.style.top = `${clamp(drag.top + event.clientY - drag.y, 0, maxTop)}px`;
    });
    titlebar?.addEventListener('pointerup', () => { drag = null; });
  }

  open(id) {
    const record = registry.get(id);
    if (!record) return;
    record.win.classList.remove('hidden-window', 'minimized-window');
    record.minimized = false;
    this.focus(id);
    this.syncTaskbar();
    this.startMenu?.classList.add('hidden');
    record.win.dispatchEvent(new CustomEvent('window:open'));
  }

  close(id) {
    const record = registry.get(id);
    if (!record) return;
    record.win.classList.add('hidden-window');
    record.minimized = false;
    this.syncTaskbar();
  }

  minimize(id) {
    const record = registry.get(id);
    if (!record) return;
    record.minimized = true;
    record.win.classList.add('minimized-window');
    this.syncTaskbar();
  }

  focus(id) {
    const record = registry.get(id);
    if (!record) return;
    registry.forEach(item => item.win.classList.remove('active-window'));
    record.win.classList.add('active-window');
    record.win.style.zIndex = String(++zCounter);
    this.syncTaskbar();
  }

  toggleMaximize(id) {
    const record = registry.get(id);
    if (!record || window.innerWidth < 720) return;
    const { win } = record;
    if (!record.maximized) {
      record.prevRect = {
        left: win.style.left,
        top: win.style.top,
        width: win.style.width,
        height: win.style.height
      };
      win.classList.add('maximized-window');
      record.maximized = true;
    } else {
      win.classList.remove('maximized-window');
      Object.assign(win.style, record.prevRect || {});
      record.maximized = false;
    }
    this.focus(id);
  }

  restore(id) {
    const record = registry.get(id);
    if (!record) return;
    if (record.minimized) {
      record.win.classList.remove('minimized-window');
      record.minimized = false;
    }
    this.focus(id);
    this.syncTaskbar();
  }

  syncTaskbar() {
    if (!this.taskbarApps) return;
    this.taskbarApps.innerHTML = '';
    registry.forEach(record => {
      if (record.win.classList.contains('hidden-window')) return;
      const button = document.createElement('button');
      button.className = `taskbar-app ${record.win.classList.contains('active-window') && !record.minimized ? 'active' : ''}`;
      button.innerHTML = `<span>${record.icon}</span><span>${record.title}</span>`;
      button.addEventListener('click', () => {
        if (record.minimized) this.restore(record.id);
        else if (record.win.classList.contains('active-window')) this.minimize(record.id);
        else this.focus(record.id);
      });
      this.taskbarApps.appendChild(button);
    });
  }
}
