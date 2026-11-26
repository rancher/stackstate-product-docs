// Expand or collapse all sections of the left navigation.
// The bundle site.js does not handle .nav-menu-toggle, so this script does.
(() => {
  const menu = document.querySelector('.nav-panel-menu');
  const toggle = menu && menu.querySelector('.nav-menu-toggle');
  if (!toggle) return;
  const items = () => menu.querySelectorAll('.nav-item > .nav-item-toggle');
  if (!items().length) return;

  const update = () => {
    const label = `${toggle.classList.contains('is-active') ? 'Collapse' : 'Expand'} all navigation sections`;
    toggle.setAttribute('aria-label', label);
    toggle.title = label;
  };

  const setExpanded = (expand) => {
    items().forEach(item => item.parentElement.classList.toggle('is-active', expand));
    toggle.classList.toggle('is-active', expand);
    update();
  };

  toggle.addEventListener('click', () => setExpanded(!toggle.classList.contains('is-active')));

  toggle.style.display = '';
  // A product landing page starts with all sections open.
  if (menu.hasAttribute('data-start-expanded')) setExpanded(true);
  else update();
})();
