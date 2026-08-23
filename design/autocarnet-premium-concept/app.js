(() => {
  'use strict';

  /* ============================================================
     Per-vehicle content — everything the brief asks to "follow"
     the active vehicle on swipe: status line, à faire prochainement,
     dernières opérations, and the carnet stats.
     ============================================================ */
  const VEHICLES = {
    q5: {
      index: 0,
      context: 'Votre Audi Q5 est à jour.',
      todos: [
        { type: 'upcoming', icon: 'shield', title: 'Assurance', due: 'Dans 28 jours' },
        { type: 'upcoming', icon: 'calendar', title: 'Contrôle technique', due: 'Dans 96 jours' },
      ],
      ops: [
        { icon: 'fuel', title: 'Vidange + filtres', meta: '09 août 2026 · 88 700 km' },
        { icon: 'wrench', title: 'Révision', meta: '16 oct. 2025 · 78 900 km' },
        { icon: 'tire', title: 'Pneus remplacés', meta: '02 mars 2025 · 65 400 km' },
      ],
      health: 100, expense: '18 450', lastMaintWhen: 'Il y a 2 mois', lastMaintWhat: 'Vidange', kmYear: '13 200',
      bars: [38, 55, 70, 86],
    },
    astra: {
      index: 1,
      context: '1 action est à prévoir prochainement.',
      todos: [
        { type: 'urgent', icon: 'wrench', title: 'Vidange', due: '1 200 km restants' },
        { type: 'upcoming', icon: 'shield', title: 'Assurance', due: 'Dans 41 jours' },
      ],
      ops: [
        { icon: 'wrench', title: 'Plaquettes de frein', meta: '20 juil. 2026 · 268 400 km' },
        { icon: 'fuel', title: 'Vidange + filtres', meta: '02 févr. 2026 · 255 100 km' },
        { icon: 'document', title: 'Contrôle technique', meta: '11 nov. 2025 · 240 000 km' },
      ],
      health: 90, expense: '9 200', lastMaintWhen: 'Il y a 3 semaines', lastMaintWhat: 'Plaquettes', kmYear: '15 800',
      bars: [60, 68, 78, 92],
    },
  };
  const ORDER = ['q5', 'astra'];

  const root = document.documentElement;
  const phone = document.getElementById('phone');

  /* ---------------- Theme switch ---------------- */
  document.querySelectorAll('[data-theme-btn]').forEach((btn) => {
    btn.addEventListener('click', () => {
      root.dataset.theme = btn.dataset.themeBtn;
      document.querySelectorAll('[data-theme-btn]').forEach((b) => {
        b.classList.toggle('is-active', b === btn);
        b.setAttribute('aria-selected', b === btn ? 'true' : 'false');
      });
    });
  });

  /* ---------------- Width switch ---------------- */
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
  const vehicleStage = document.querySelector('[data-vehicle-stage]');
  const drawer = document.querySelector('[data-drawer]');
  const sheet = document.querySelector('[data-sheet]');

  function realScreenId(id) {
    return (id === 'home-single' || id === 'home-multi') ? 'home-single' : id;
  }

  function showScreen(id) {
    const real = realScreenId(id);
    screens.forEach((s) => s.classList.toggle('screen--active', s.dataset.screen === real));

    const viewport = document.getElementById('viewport');
    if (viewport) viewport.dataset.activeScreen = real;

    // Keep the top demo tabs in sync even when navigation happened from
    // inside the phone (bottom nav, drawer, back chevrons…).
    screenTabs.forEach((t) => t.classList.toggle('is-active', t.dataset.screenBtn === id));

    if (bottomNav) {
      bottomNav.querySelectorAll('[data-nav]').forEach((b) => {
        b.classList.toggle('is-active', b.dataset.nav === real);
      });
    }

    if (id === 'home-single') setVehicleMode('single');
    if (id === 'home-multi') setVehicleMode('multi');

    closeDrawer();
    closeSheet();

    if (id === 'menu') openDrawer();

    const vp = document.getElementById('viewport');
    if (vp) vp.scrollTop = 0;
    document.querySelectorAll(`.screen[data-screen="${real}"]`).forEach((s) => { s.scrollTop = 0; });
  }

  screenTabs.forEach((btn) => btn.addEventListener('click', () => showScreen(btn.dataset.screenBtn)));
  document.querySelectorAll('[data-nav]').forEach((btn) => {
    btn.addEventListener('click', () => showScreen(btn.dataset.nav));
  });

  /* ---------------- Vehicle mode (single vs multi) ---------------- */
  function setVehicleMode(mode) {
    if (!vehicleStage) return;
    vehicleStage.classList.toggle('mode-single', mode === 'single');
    if (mode === 'single') goToVehicle('q5', false);
  }

  /* ---------------- Vehicle swipe / carousel ---------------- */
  const stack = document.querySelector('[data-card-stack]');
  const cards = stack ? Array.from(stack.querySelectorAll('.vehicle-card')) : [];
  const dots = document.querySelectorAll('[data-dot]');
  let currentKey = 'q5';

  function iconMarkup(name) {
    return `<i class="ic" style="--src:url('assets/icons/${name}.svg')" aria-hidden="true"></i>`;
  }

  function renderVehicleData(key) {
    const v = VEHICLES[key];
    const ctxEl = document.querySelector('[data-context-line]');
    if (ctxEl) ctxEl.textContent = v.context;

    const todoList = document.querySelector('[data-todo-list]');
    if (todoList) {
      todoList.innerHTML = v.todos.map((t) => `
        <div class="todo-item todo-item--${t.type}">
          <div class="todo-item__icon">${iconMarkup(t.icon)}</div>
          <div class="todo-item__body">
            <div class="todo-item__title">${t.title}</div>
            <div class="todo-item__due">${t.due}</div>
          </div>
        </div>`).join('');
    }

    const timelineHost = document.querySelector('.screen[data-screen="home-single"] .timeline');
    if (timelineHost) {
      timelineHost.innerHTML = v.ops.map((o, i) => `
        <div class="timeline-item">
          <div class="timeline-item__rail">
            <div class="timeline-item__icon">${iconMarkup(o.icon)}</div>
            ${i < v.ops.length - 1 ? '<div class="timeline-item__line"></div>' : ''}
          </div>
          <div class="timeline-item__content">
            <div class="timeline-item__title">${o.title}</div>
            <div class="timeline-item__meta">${o.meta}</div>
          </div>
        </div>`).join('');
    }

    const healthRing = document.querySelector('.screen[data-screen="home-single"] .carnet-hero .ring-value');
    const healthLabel = document.querySelector('.screen[data-screen="home-single"] .carnet-hero__label strong');
    if (healthRing) healthRing.style.setProperty('--pct', v.health);
    if (healthLabel) healthLabel.textContent = v.health;

    const expenseEl = document.querySelector('[data-stat="expense"]');
    if (expenseEl) expenseEl.innerHTML = `${v.expense} <em>DH</em>`;
    const lastMaintEl = document.querySelector('[data-stat="last-maint"]');
    if (lastMaintEl) lastMaintEl.textContent = v.lastMaintWhen;
    const lastMaintWhatEl = document.querySelector('[data-stat="last-maint-what"]');
    if (lastMaintWhatEl) lastMaintWhatEl.textContent = v.lastMaintWhat;
    const kmYearEl = document.querySelector('[data-stat="km-year"]');
    if (kmYearEl) kmYearEl.textContent = v.kmYear + ' km/an';
    const bars = document.querySelectorAll('.screen[data-screen="home-single"] .bar-chart .bar');
    bars.forEach((bar, i) => { if (v.bars[i] != null) bar.style.setProperty('--h', v.bars[i] + '%'); });
  }

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
    let startX = 0, lastX = 0, dragging = false;
    const threshold = 55;
    const eventX = (e) => (e.touches ? e.touches[0].clientX : (e.changedTouches ? e.changedTouches[0].clientX : e.clientX));

    const onDown = (e) => {
      if (vehicleStage.classList.contains('mode-single')) return;
      dragging = true;
      startX = lastX = eventX(e);
      const cur = stack.querySelector('.vehicle-card.is-current');
      if (cur) cur.classList.add('is-dragging');
    };
    const onMove = (e) => {
      if (!dragging) return;
      lastX = eventX(e);
      const dx = lastX - startX;
      const cur = stack.querySelector('.vehicle-card.is-current');
      if (cur) cur.style.transform = `translateX(${dx}px) rotate(${dx / 40}deg)`;
    };
    const onUp = (e) => {
      if (!dragging) return;
      dragging = false;
      const dx = eventX(e) - startX;
      const cur = stack.querySelector('.vehicle-card.is-current');
      if (cur) { cur.classList.remove('is-dragging'); cur.style.transform = ''; }

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
  function openDrawer() { if (drawer) drawer.classList.add('is-open'); }
  function closeDrawer() { if (drawer) drawer.classList.remove('is-open'); }
  document.querySelectorAll('[data-open-drawer]').forEach((b) => b.addEventListener('click', openDrawer));
  document.querySelectorAll('[data-close-drawer]').forEach((b) => b.addEventListener('click', closeDrawer));

  /* ---------------- Bottom sheet (Ajouter) ---------------- */
  function openSheet() { if (sheet) sheet.classList.add('is-open'); }
  function closeSheet() { if (sheet) sheet.classList.remove('is-open'); }
  const primaryCta = document.querySelector('.screen[data-screen="home-single"] .action-primary:not(.action-primary--static)');
  if (primaryCta) primaryCta.addEventListener('click', openSheet);
  document.querySelectorAll('[data-close-sheet]').forEach((b) => b.addEventListener('click', closeSheet));
  document.querySelectorAll('.sheet__option').forEach((b) => b.addEventListener('click', closeSheet));

  /* ---------------- Notification bell: tap to mark read ---------------- */
  document.querySelectorAll('[data-notif-btn]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const dot = btn.querySelector('.icon-btn__dot');
      if (dot) dot.style.display = 'none';
    });
  });

  /* ---------------- Fiche tabs (cosmetic) ---------------- */
  document.querySelectorAll('.fiche-tabs').forEach((group) => {
    group.querySelectorAll('.fiche-tab').forEach((tab) => {
      tab.addEventListener('click', () => {
        group.querySelectorAll('.fiche-tab').forEach((t) => t.classList.toggle('is-active', t === tab));
      });
    });
  });

  /* ---------------- Escape closes overlays ---------------- */
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { closeDrawer(); closeSheet(); }
  });

  /* ---------------- Initial paint ---------------- */
  showScreen('home-single');
})();
