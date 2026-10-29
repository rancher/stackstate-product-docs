// Mark the product release in the URL as the current release.
// A component version that several releases pin is built once, under the
// oldest of them. The other releases reach the same pages through their own
// path, /<url_prefix>/<release>/..., so the page shows the release of its URL.
// See helpers/productreleases.js. Without this script, the page shows the
// release that it was built under.
(() => {
  const context = document.querySelector('[data-release-prefix]');
  if (!context) return;
  const segments = window.location.pathname.split('/');
  const index = segments.indexOf(context.dataset.releasePrefix);
  const release = index < 0 ? undefined : segments[index + 1];
  if (!release) return;
  const options = [...document.querySelectorAll('[data-release-option]')];
  const selected = options.filter((option) => option.dataset.releaseOption === release);
  if (!selected.length) return;
  options.forEach((option) => option.classList.toggle('is-current', selected.includes(option)));
  const label = selected[0].dataset.releaseLabel;
  document.querySelectorAll('[data-release-current]').forEach((element) => { element.textContent = label; });
})();
