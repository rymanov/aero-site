/*
 * Google Analytics 4 (gtag.js) loader for the Aero *marketing site*.
 *
 * SETUP: replace the placeholder below with your real GA4 Measurement ID
 * (GA4 admin -> Data Streams -> Web -> "G-XXXXXXXXXX"). That is the only
 * edit needed to go live — the ID lives here in exactly one place.
 *
 * WHY AN EXTERNAL FILE: loading this from 'self' (rather than an inline
 * <script>) keeps the site's strict Content-Security-Policy in _headers free
 * of 'unsafe-inline'. The gtag.js library this injects is allowlisted via
 * `script-src https://www.googletagmanager.com`.
 *
 * SCOPE: this is a SITE concern only. The Aero app collects nothing (see
 * privacy.html) — that policy is app-scoped and stays true. This file never
 * ships inside the app; it only runs on the public marketing pages.
 */
(function () {
  var GA_MEASUREMENT_ID = 'G-410NJK02EZ'; // Aero Site (aeroplay.tv) GA4 web stream

  // Safe no-op until a real ID is set, so the placeholder ships harmlessly.
  if (!GA_MEASUREMENT_ID || GA_MEASUREMENT_ID === 'G-XXXXXXXXXX') return;

  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=' + GA_MEASUREMENT_ID;
  document.head.appendChild(s);

  window.dataLayer = window.dataLayer || [];
  function gtag() { dataLayer.push(arguments); }
  gtag('js', new Date());

  // Privacy-forward config (Aero brand): no Google Signals / ads-personalisation
  // data at the tag level. Belt-and-suspenders with Google Signals disabled in
  // GA Admin, so ad-targeting data is never collected even if an account toggle
  // flips. Aero runs no ads — this is measurement only.
  gtag('config', GA_MEASUREMENT_ID, {
    allow_google_signals: false,
    allow_ad_personalization_signals: false
  });
})();
