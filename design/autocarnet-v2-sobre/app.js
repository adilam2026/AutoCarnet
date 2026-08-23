(() => {
  'use strict';

  /* ============================================================
     Per-vehicle content driving the home screen, fiche header and
     alerts context line when the active vehicle changes.
     ============================================================ */
  const VEHICLES = {
    q5: {
      index: 0,
      name: 'Audi Q5',
      km: '86 750 km',
      health: 100,
      healthLabel: '100 · À jour',
      healthOk: true,
      revision: '95 450 km',
      contextOk: true,
      context: 'Tout est à jour',
      todos: [],
      ops: [
        { icon: 'wrench', title: 'Vidange + filtres', date: '09 août', meta: '85 450 km' },
        { icon: 'fuel', title: 'Plein', date: '02 août', meta: '620 MAD · 54 L' },
        { icon: 'wrench', title: 'Révision', date: '16 oct.', meta: '78 900 km' },
      ],
    },
    astra: {
      index: 1,
      name: 'Opel Astra',
      km: '270 000 km',
      health: 90,
      healthLabel: '90 · 1 à faire',
      healthOk: false,
      revision: '271 200 km',
      contextOk: false,
      context: '1 action est à prévoir prochainement',
      todos: [
        { type: 'danger', icon: 'alert', title: 'Vidange', due: '1 200 km', urgency: 'danger' },
        { type: 'warning', icon: 'shield', title: 'Assurance', due: '41 jours', urgency: 'warning' },
      ],
      ops: [
        { icon: 'wrench', title: 'Plaquettes de frein', date: '20 juil.', meta: '268 400 km' },
        { icon: 'wrench', title: 'Vidange + filtres', date: '02 févr.', meta: '255 100 km' },
        { icon: 'document', title: 'Contrôle technique', date: '11 nov.', meta: '240 000 km' },
      ],
    },
  };
  const ORDER = ['q5', 'astra'];

  const root = document.documentElement;
  const phone = document.getElementById('phone');

  /* ---------------- Accent switch (demo only) ---------------- */
  document.querySelectorAll('[data-accent-btn]').forEach((btn) => {
    btn.addEventListener('click', () => {
      root.dataset.accent = btn.dataset.accentBtn;
      document.querySelectorAll('[data-accent-btn]').forEach((b) => {
        b.classList.toggle('is-active', b === btn);
        b.setAttribute('aria-selected', b === btn ? 'true' : 'false');
      });
    });
  });

  /* ---------------- Width switch (demo only) ---------------- */
  document.querySelectorAll('[data-width]').forEach((btn) => {
    btn.addEventListener('click', () => {
      phone.style.setProperty('--phone-w', btn.dataset.width + 'px');
      document.querySelectorAll('[data-width]').forEach((b) => b.classList.toggle('is-active', b === btn));
    });
  });

  /* ---------------- Screen navigation ---------------- */
  const screens = document.querySelectorAll('.screen');
  const screenTabs = document.querySelectorAll('[data-screen-btn]');
  const bottomNav = document.querySelector('[data-bottom-nav]');
  const drawer = document.querySelector('[data-drawer]');
  const drawerOverlay = document.querySelector('[data-drawer-overlay]');
  const sheet = document.querySelector('[data-sheet]');
  const sheetOverlay = document.querySelector('[data-sheet-overlay]');
  const fab = document.querySelector('[data-fab]');

  function showScreen(id) {
    screens.forEach((s) => s.classList.toggle('screen--active', s.dataset.screen === id));
    if (bottomNav) {
      bottomNav.querySelectorAll('[data-nav]').forEach((b) => b.classList.toggle('is-active', b.dataset.nav === id));
    }
    if (fab) fab.classList.toggle('is-visible', id === 'home');
    closeDrawer();
    closeSheet();
    document.querySelectorAll(`.screen[data-screen="${id}"]`).forEach((s) => { s.scrollTop = 0; });
  }

  document.querySelectorAll('[data-nav]').forEach((btn) => {
    btn.addEventListener('click', () => showScreen(btn.dataset.nav));
  });

  screenTabs.forEach((btn) => {
    btn.addEventListener('click', () => {
      screenTabs.forEach((t) => t.classList.toggle('is-active', t === btn));
      if (btn.dataset.vehicle) {
        showScreen('home');
        goToVehicle(btn.dataset.vehicle);
      } else if (btn.dataset.screenBtn === 'menu') {
        openDrawer();
      } else {
        showScreen(btn.dataset.screenBtn);
      }
    });
  });

  /* ---------------- Vehicle card content render ---------------- */
  function iconMarkup(name) {
    return `<i class="ic" style="--src:url('assets/icons/${name}.svg')" aria-hidden="true"></i>`;
  }

  function renderVehicleData(key) {
    const v = VEHICLES[key];

    document.querySelectorAll('[data-context-line]').forEach((el) => { el.textContent = v.context; });
    document.querySelectorAll('[data-status-dot]').forEach((el) => { el.classList.toggle('status-dot--warn', !v.contextOk); });

    const notifDot = document.querySelector('[data-notif-dot]');
    if (notifDot) notifDot.style.display = v.todos.length ? '' : 'none';

    const todoHost = document.querySelector('[data-todo-host]');
    if (todoHost) {
      if (!v.todos.length) {
        todoHost.innerHTML = `
          <div class="all-good-row">
            <div class="all-good-row__icon">${iconMarkup('check')}</div>
            <div>
              <div class="all-good-row__title">Tout est à jour</div>
              <div class="all-good-row__sub">Aucune action requise</div>
            </div>
          </div>`;
      } else {
        todoHost.innerHTML = `<div class="list-surface">${v.todos.map((t) => `
          <div class="list-row">
            <div class="list-row__icon list-row__icon--${t.urgency}">${iconMarkup(t.icon)}</div>
            <div class="list-row__body"><div class="list-row__title">${t.title}</div></div>
            <div class="list-row__trail"><div class="list-row__trail-value list-row__trail-value--${t.urgency}">${t.due}</div></div>
          </div>`).join('')}</div>`;
      }
    }

    const opsHost = document.querySelector('[data-ops-list]');
    if (opsHost) {
      opsHost.innerHTML = v.ops.slice(0, 3).map((o) => `
        <div class="list-row">
          <div class="list-row__icon">${iconMarkup(o.icon)}</div>
          <div class="list-row__body"><div class="list-row__title">${o.title}</div><div class="list-row__meta">${o.meta}</div></div>
          <div class="list-row__trail"><div class="list-row__trail-value--muted">${o.date}</div></div>
        </div>`).join('');
    }

    document.querySelectorAll('[data-fiche-name]').forEach((el) => { el.textContent = v.name; });
    document.querySelectorAll('[data-fiche-km]').forEach((el) => { el.textContent = v.km; });
    document.querySelectorAll('[data-fiche-health]').forEach((el) => { el.textContent = `Santé ${v.health}%`; });
    document.querySelectorAll('[data-fiche-health-dot]').forEach((el) => { el.classList.toggle('status-dot--warn', !v.healthOk); });
  }

  /* ---------------- Vehicle swipe / carousel ---------------- */
  const stack = document.querySelector('[data-card-stack]');
  const cards = stack ? Array.from(stack.querySelectorAll('.vehicle-card')) : [];
  const dots = document.querySelectorAll('[data-dot]');
  let currentKey = 'q5';

  cards.forEach((card) => {
    card.addEventListener('click', (e) => {
      // A drag that moved the card shouldn't also trigger the tap-through.
      if (card.dataset.suppressClick === '1') { card.dataset.suppressClick = '0'; return; }
      showScreen('fiche');
    });
  });

  function goToVehicle(key, animate = true) {
    currentKey = key;
    const idx = VEHICLES[key].index;
    cards.forEach((card) => {
      const cIdx = Number(card.dataset.index);
      card.classList.remove('is-current', 'is-next', 'is-prev');
      if (!animate) card.style.transition = 'none';
      if (cIdx === idx) card.classList.add('is-current');
      else if (cIdx > idx) card.classList.add('is-next');
      else card.classList.add('is-prev');
      if (!animate) requestAnimationFrame(() => { card.style.transition = ''; });
    });
    dots.forEach((d) => d.classList.toggle('is-active', Number(d.dataset.dot) === idx));
    renderVehicleData(key);
  }

  dots.forEach((dot) => dot.addEventListener('click', () => {
    const key = ORDER[Number(dot.dataset.dot)];
    if (key) goToVehicle(key);
  }));

  /* Drag / swipe between the two vehicle cards. dx is recomputed from the
     pointerup/touchend position itself (not just the last move sample):
     on a fast flick, intermediate pointermove events can be coalesced by
     the browser down to just one or two, so trusting only the running
     "dx" from onMove risks under-reading a real, fast swipe. */
  if (stack) {
    let startX = 0, dragging = false, moved = false;
    const threshold = 55;
    const eventX = (e) => (e.touches ? e.touches[0].clientX : (e.changedTouches ? e.changedTouches[0].clientX : e.clientX));

    const onDown = (e) => {
      dragging = true;
      moved = false;
      startX = eventX(e);
      const cur = stack.querySelector('.vehicle-card.is-current');
      if (cur) cur.classList.add('is-dragging');
    };
    const onMove = (e) => {
      if (!dragging) return;
      const dx = eventX(e) - startX;
      if (Math.abs(dx) > 4) moved = true;
      const cur = stack.querySelector('.vehicle-card.is-current');
      if (cur) cur.style.transform = `translateX(${dx}px)`;
    };
    const onUp = (e) => {
      if (!dragging) return;
      dragging = false;
      const dx = eventX(e) - startX;
      const cur = stack.querySelector('.vehicle-card.is-current');
      if (cur) {
        cur.classList.remove('is-dragging');
        cur.style.transform = '';
        if (moved) cur.dataset.suppressClick = '1';
      }

      const idx = VEHICLES[currentKey].index;
      if (dx <= -threshold && idx < ORDER.length - 1) goToVehicle(ORDER[idx + 1]);
      else if (dx >= threshold && idx > 0) goToVehicle(ORDER[idx - 1]);
    };

    stack.addEventListener('pointerdown', onDown);
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
    stack.addEventListener('touchstart', onDown, { passive: true });
    window.addEventListener('touchmove', onMove, { passive: true });
    window.addEventListener('touchend', onUp);
  }

  /* ---------------- Drawer ---------------- */
  function openDrawer() { if (drawer) { drawer.classList.add('is-open'); drawerOverlay.classList.add('is-open'); } }
  function closeDrawer() { if (drawer) { drawer.classList.remove('is-open'); drawerOverlay.classList.remove('is-open'); } }
  document.querySelectorAll('[data-open-drawer]').forEach((b) => b.addEventListener('click', openDrawer));
  document.querySelectorAll('[data-close-drawer]').forEach((b) => b.addEventListener('click', closeDrawer));

  /* ---------------- Sheet (Ajouter) ---------------- */
  function openSheet() { if (sheet) { sheet.classList.add('is-open'); sheetOverlay.classList.add('is-open'); } }
  function closeSheet() { if (sheet) { sheet.classList.remove('is-open'); sheetOverlay.classList.remove('is-open'); } }
  document.querySelectorAll('[data-open-sheet]').forEach((b) => b.addEventListener('click', openSheet));
  document.querySelectorAll('[data-close-sheet]').forEach((b) => b.addEventListener('click', closeSheet));

  /* ---------------- Fiche tabs (cosmetic) ---------------- */
  document.querySelectorAll('.fiche-tabs').forEach((group) => {
    group.querySelectorAll('.fiche-tab').forEach((tab) => {
      tab.addEventListener('click', () => {
        group.querySelectorAll('.fiche-tab').forEach((t) => t.classList.toggle('is-active', t === tab));
      });
    });
  });

  /* ---------------- Notification bell dot clears once alerts is opened ---------------- */
  document.querySelectorAll('[data-nav="alertes"]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const dot = document.querySelector('[data-notif-dot]');
      if (dot) dot.style.display = 'none';
    });
  });

  /* ---------------- Escape closes overlays ---------------- */
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { closeDrawer(); closeSheet(); }
  });

  /* ---------------- Initial paint ---------------- */
  goToVehicle('q5', false);
  showScreen('home');
})();
