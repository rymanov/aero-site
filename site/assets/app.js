// Tasteful scroll reveal + hero entrance. No dependencies, no requests.
// Defensive: content is never left hidden if rAF/IntersectionObserver misbehave.
(function () {
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.documentElement.classList.add('js');

  // Hero settles in once painted (with a timeout fallback if rAF is throttled).
  function settle() { document.body.classList.add('hero-loaded'); }
  requestAnimationFrame(function () { requestAnimationFrame(settle); });
  setTimeout(settle, 1000);

  var items = [].slice.call(document.querySelectorAll('.reveal'));
  function show(el) { el.classList.add('in'); }

  if (reduce || !('IntersectionObserver' in window)) {
    items.forEach(show);
    return;
  }

  // Anything already on screen at first paint reveals immediately.
  function near(el) {
    var r = el.getBoundingClientRect();
    return r.top < window.innerHeight * 0.92 && r.bottom > 0;
  }
  items.forEach(function (el) { if (near(el)) show(el); });

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) { show(e.target); io.unobserve(e.target); }
    });
  }, { threshold: 0.18, rootMargin: '0px 0px -8% 0px' });
  items.forEach(function (el) { if (!el.classList.contains('in')) io.observe(el); });

  // Safety net: once loaded, reveal anything on screen that's still hidden.
  window.addEventListener('load', function () {
    setTimeout(function () {
      items.forEach(function (el) { if (!el.classList.contains('in') && near(el)) show(el); });
    }, 200);
  });
})();
