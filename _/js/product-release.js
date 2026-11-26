// Mark the product release in the URL as the current release.
// A component version that several releases pin is built once, under the
// oldest of them. The other releases reach the same pages through their own
// path, /<url_prefix>/<release>/..., so the page shows the release of its URL.
// See helpers/productreleases.js. Without this script, the page shows the
// release that it was built under. The aliases, /<url_prefix>/latest/ and
// /<url_prefix>/dev/, stand for the releases that they link to.
(() => {
  const context = document.querySelector('[data-release-prefix]');
  if (!context) return;
  const segments = window.location.pathname.split('/');
  const index = segments.indexOf(context.dataset.releasePrefix);
  const segment = index < 0 ? undefined : segments[index + 1];
  const aliases = { latest: context.dataset.releaseLatest, dev: context.dataset.releaseDev };
  const release = Object.prototype.hasOwnProperty.call(aliases, segment) ? aliases[segment] : segment;
  if (!release) return;
  const options = [...document.querySelectorAll('[data-release-option]')];
  const selected = options.filter((option) => option.dataset.releaseOption === release);
  if (!selected.length) return;
  options.forEach((option) => option.classList.toggle('is-current', selected.includes(option)));
  document.querySelectorAll('[data-release-components]').forEach((list) => {
    list.hidden = list.dataset.releaseComponents !== release;
  });
  const label = selected[0].dataset.releaseLabel;
  document.querySelectorAll('[data-release-current]').forEach((element) => { element.textContent = label; });
})();
