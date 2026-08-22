(() => {
  'use strict';

  const phone = document.getElementById('phone');
  const conceptSeg = document.getElementById('conceptSeg');
  const scenarioSeg = document.getElementById('scenarioSeg');
  const backdrop = document.getElementById('backdrop');
  const drawer = document.getElementById('drawer');
  const sheet = document.getElementById('sheet');
  const toastEl = document.getElementById('toast');
  const carousel = document.getElementById('carousel');
  const carouselDots = document.getElementById('carouselDots');

  let state = { concept: 'a', scenario: 1 };

  try {
    const saved = JSON.parse(localStorage.getItem('autocarnet-concept-demo') || '{}');
    if (saved.concept === 'a' || saved.concept === 'b') state.concept = saved.concept;
    if ([1, 2, 3, 4].includes(saved.scenario)) state.scenario = saved.scenario;
  } catch (_) { /* private mode / storage unavailable: fall back to defaults */ }

  function persist() {
    try { localStorage.setItem('autocarnet-concept-demo', JSON.stringify(state)); } catch (_) { /* ignore */ }
  }

  function applyConcept() {
    phone.dataset.concept = state.concept;
    conceptSeg.querySelectorAll('button').forEach((b) => {
      b.setAttribute('aria-pressed', String(b.dataset.concept === state.concept));
    });
  }

  function applyScenario() {
    const n = state.scenario;

    scenarioSeg.querySelectorAll('button').forEach((b) => {
      b.setAttribute('aria-pressed', String(Number(b.dataset.scenario) === n));
    });

    // Show/hide blocks tagged for this scenario.
    phone.querySelectorAll('[data-scenario-el]').forEach((el) => {
      const list = el.dataset.scenarioEl.split(',').map((s) => s.trim());
      el.hidden = !list.includes(String(n));
    });

    // Single-value visibility switches (status pills, greeting lines).
    phone.querySelectorAll('[data-when]').forEach((el) => {
      el.hidden = el.dataset.when !== String(n);
    });

    // Text content that varies 1/2/3.
    phone.querySelectorAll('[data-when1], [data-when2], [data-when3]').forEach((el) => {
      const key = 'when' + n;
      if (el.dataset[key] !== undefined) el.textContent = el.dataset[key];
    });

    // Ring gauges that vary 1/2/3.
    const circumference = 113;
    phone.querySelectorAll('[data-pct1], [data-pct2], [data-pct3]').forEach((el) => {
      const key = 'pct' + n;
      if (el.dataset[key] !== undefined) {
        const pct = Number(el.dataset[key]);
        el.style.strokeDashoffset = String(circumference * (1 - pct / 100));
      }
    });

    persist();
  }

  conceptSeg.addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-concept]');
    if (!btn) return;
    state.concept = btn.dataset.concept;
    applyConcept();
    persist();
  });

  scenarioSeg.addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-scenario]');
    if (!btn) return;
    state.scenario = Number(btn.dataset.scenario);
    applyScenario();
    closeOverlays();
  });

  // ---- Carousel dots (scénario 3) ----
  if (carousel && carouselDots) {
    const dots = Array.from(carouselDots.children);
    const cards = Array.from(carousel.children);
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const idx = cards.indexOf(entry.target);
            dots.forEach((d, i) => d.classList.toggle('active', i === idx));
          }
        });
      },
      { root: carousel, threshold: 0.6 }
    );
    cards.forEach((c) => io.observe(c));
    dots.forEach((dot, i) => {
      dot.addEventListener('click', () => cards[i].scrollIntoView({ behavior: 'smooth', inline: 'start' }));
    });
  }

  // ---- Overlays: drawer / bottom sheet / toast ----
  function openDrawer() {
    drawer.classList.add('open');
    backdrop.classList.add('open');
  }
  function openSheet() {
    sheet.classList.add('open');
    backdrop.classList.add('open');
  }
  function closeOverlays() {
    drawer.classList.remove('open');
    sheet.classList.remove('open');
    backdrop.classList.remove('open');
  }

  let toastTimer = null;
  function showToast(message) {
    toastEl.textContent = message;
    toastEl.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove('show'), 1800);
  }

  document.getElementById('menuBtn').addEventListener('click', openDrawer);
  document.getElementById('fabBtn').addEventListener('click', openSheet);
  document.getElementById('avatarBtn').addEventListener('click', () => {
    closeOverlays();
    showToast('Ouvrir : Compte & sécurité');
  });
  backdrop.addEventListener('click', closeOverlays);

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeOverlays();
  });

  drawer.addEventListener('click', (e) => {
    const item = e.target.closest('.drawer-item');
    if (!item) return;
    closeOverlays();
    if (item.closest('.drawer-lock')) {
      showToast('AutoCarnet verrouillé (démo) — retour à l’écran de code');
    } else {
      showToast('Ouvrir : ' + item.textContent.trim());
    }
  });

  sheet.addEventListener('click', (e) => {
    const item = e.target.closest('.sheet-item');
    if (!item) return;
    closeOverlays();
    showToast(item.dataset.toast || item.textContent.trim());
  });

  phone.addEventListener('click', (e) => {
    const tile = e.target.closest('.tile');
    if (tile) showToast(tile.dataset.toast || tile.querySelector('span:last-child').textContent);
    const card = e.target.closest('.veh-card');
    if (card && !e.target.closest('.tile')) {
      const name = card.querySelector('.veh-name')?.textContent || 'le véhicule';
      showToast('Ouvrir la fiche : ' + name);
    }
  });

  applyConcept();
  applyScenario();
})();
