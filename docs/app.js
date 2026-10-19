/* AppFactory landing page — vanilla JS, no build step. */
(function () {
  "use strict";
  var CONFIG = window.APP_CONFIG || {};
  document.documentElement.classList.add("js");
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  var navWrap = $(".nav-wrap"), navToggle = $("#nav-toggle"), navLinks = $("#nav-links");
  window.addEventListener("scroll", function () { if (navWrap) navWrap.classList.toggle("is-scrolled", window.scrollY > 8); }, { passive: true });
  if (navToggle && navLinks) {
    navToggle.addEventListener("click", function () {
      var open = navLinks.classList.toggle("is-open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    $$("a", navLinks).forEach(function (a) { a.addEventListener("click", function () { navLinks.classList.remove("is-open"); }); });
  }

  var reveals = $$(".reveal");
  if ("IntersectionObserver" in window && reveals.length) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("is-visible"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    reveals.forEach(function (el) { io.observe(el); });
  } else { reveals.forEach(function (el) { el.classList.add("is-visible"); }); }

  // Latest release: version label, asset size, direct download link.
  if (CONFIG.RELEASE_API_URL && window.fetch) {
    fetch(CONFIG.RELEASE_API_URL, { headers: { Accept: "application/vnd.github+json" } })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (rel) {
        if (!rel) return;
        var asset = (rel.assets || []).filter(function (a) { return a.name === CONFIG.ASSET_NAME; })[0];
        $$("[data-version]").forEach(function (el) { el.textContent = rel.tag_name || "Latest release"; });
        if (asset) {
          var mb = (asset.size / 1048576).toFixed(1);
          $$("[data-release-meta]").forEach(function (el) { el.textContent = asset.name + " · " + mb + " MB · " + (rel.tag_name || ""); });
          $$("a[data-download]").forEach(function (a) { a.href = asset.browser_download_url; });
        }
      }).catch(function () {});
  }
})();
