// Motion for the EverydayOpen sites (docs/MOTION.md). Every page is complete and static without it.
(() => {
  const root = document.documentElement;
  const calm = matchMedia('(prefers-reduced-motion: reduce)');
  const fine = matchMedia('(hover: hover) and (pointer: fine)');

  // Tilt: --px/--py (-1..1 from the center) on the hovered [data-tilt]; CSS turns them into rotation and glare.
  // The box is read once per element entered, so the tilt never feeds back into it.
  let el = null, box, x = 0, y = 0, frame = 0;
  const enter = (t) => {
    if (el) {
      el.classList.remove('tilting');
      el.style.removeProperty('--px');
      el.style.removeProperty('--py');
    }
    el = t;
    if (el) {
      el.classList.add('tilting');
      box = el.getBoundingClientRect();
    }
  };
  const unit = (v, start, size) => Math.max(-1, Math.min(1, (v - start) / size * 2 - 1)).toFixed(3);
  const draw = () => {
    frame = 0;
    if (!el) return;
    el.style.setProperty('--px', unit(x, box.left, box.width));
    el.style.setProperty('--py', unit(y, box.top, box.height));
  };
  addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse' || calm.matches || !fine.matches) return;
    const t = e.target.closest ? e.target.closest('[data-tilt]') : null;
    if (t !== el) enter(t);
    x = e.clientX;
    y = e.clientY;
    if (el && !frame) frame = requestAnimationFrame(draw);
  }, { passive: true });
  addEventListener('scroll', () => el && enter(null), { passive: true });
  root.addEventListener('pointerleave', () => enter(null));

  // Reveal, where CSS scroll-driven animations don't exist yet (Firefox): .in when it enters, staggered per batch.
  const items = document.querySelectorAll('.reveal');
  if (items.length && !calm.matches && !CSS.supports('animation-timeline: view()') && 'IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.filter((e) => e.isIntersecting).forEach((e, n) => {
        e.target.style.setProperty('--i', Math.min(n, 6));
        e.target.classList.add('in');
        io.unobserve(e.target);
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    items.forEach((e) => (e.getBoundingClientRect().top < innerHeight ? e.classList.add('in') : io.observe(e)));
    root.classList.add('reveal-io');
  }

  // Sweep (Overstay only): the hero's Stop button sends the chips out through the door; the same button resets it.
  document.querySelectorAll('[data-sweep]').forEach((b) => {
    const scene = document.getElementById(b.getAttribute('aria-controls'));
    if (!scene) return;
    const stop = b.textContent, reset = b.getAttribute('data-sweep');
    const say = b.parentNode.querySelector('[data-sweep-status]');
    b.hidden = false;
    b.addEventListener('click', () => {
      const on = scene.classList.toggle('swept');
      b.textContent = on ? reset : stop;
      if (say) say.textContent = on ? 'Sample: stopped 183, 9.4 GB was held' : 'Demo reset';
    });
  });
})();
