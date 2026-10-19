const GTM_ID = 'GTM-P7SN2D3S';
const GA4_ID = 'G-1856DFR43Z';
const CONSENT_KEY = 'hannyeong.analytics-consent';
const panel = document.querySelector('[data-analytics-consent]');
const status = document.querySelector('[data-analytics-status]');
const settings = document.querySelector('[data-analytics-settings]');
let consent = localStorage.getItem(CONSENT_KEY);
let loaded = false;

window.dataLayer = window.dataLayer || [];
function gtag() { window.dataLayer.push(arguments); }
gtag('consent', 'default', {
  analytics_storage: 'denied', ad_storage: 'denied',
  ad_user_data: 'denied', ad_personalization: 'denied'
});

function enableAnalytics() {
  if (loaded) return;
  loaded = true;
  window[`ga-disable-${GA4_ID}`] = false;
  gtag('consent', 'update', { analytics_storage: 'granted' });
  window.dataLayer.push({ 'gtm.start': Date.now(), event: 'gtm.js' });
  const script = document.createElement('script');
  script.async = true;
  script.src = `https://www.googletagmanager.com/gtm.js?id=${GTM_ID}`;
  document.head.append(script);
}

function clearAnalyticsCookies() {
  for (const cookie of document.cookie.split(';')) {
    const name = cookie.split('=')[0].trim();
    if (!/^(_ga(?:_|$)|_gid$|_gat(?:_|$)|_clck$|_clsk$)/.test(name)) continue;
    const expired = `${name}=; Max-Age=0; Path=/; SameSite=Lax; Secure`;
    document.cookie = expired;
    document.cookie = `${expired}; Domain=${location.hostname}`;
  }
}

function showSettings() {
  status.textContent = consent === 'granted' ? '현재 이용 분석에 동의한 상태입니다.'
    : consent === 'denied' ? '현재 이용 분석을 사용하지 않습니다.' : '';
  panel.hidden = false;
}

settings.addEventListener('click', showSettings);
document.querySelector('[data-analytics-details]').addEventListener('click', () => {
  document.querySelector('#website-analytics details').open = true;
  panel.hidden = true;
});
document.querySelector('[data-analytics-accept]').addEventListener('click', () => {
  consent = 'granted';
  localStorage.setItem(CONSENT_KEY, consent);
  panel.hidden = true;
  enableAnalytics();
});
document.querySelector('[data-analytics-decline]').addEventListener('click', () => {
  consent = 'denied';
  localStorage.setItem(CONSENT_KEY, consent);
  panel.hidden = true;
  window[`ga-disable-${GA4_ID}`] = true;
  if (loaded && window.clarity) window.clarity('stop');
  clearAnalyticsCookies();
  // Reload unloads vendor listeners so withdrawal also stops cookieless tracking.
  if (loaded) location.reload();
});

for (const link of document.querySelectorAll('[data-download-location]')) {
  link.addEventListener('click', () => {
    if (consent !== 'granted') return;
    window.dataLayer.push({
      event: 'download_click', download_url: link.href,
      button_location: link.dataset.downloadLocation,
      link_text: link.textContent.trim()
    });
  });
}

if (consent === 'granted') enableAnalytics();
else if (consent !== 'denied') showSettings();
