const themeButton = document.querySelector('[data-theme-toggle]');
const storedTheme = localStorage.getItem('casechain-portal-theme');

function setTheme(theme) {
  document.documentElement.dataset.theme = theme;
  if (themeButton) themeButton.textContent = theme === 'dark' ? 'Use light appearance' : 'Use dark appearance';
}

setTheme(storedTheme || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));

themeButton?.addEventListener('click', () => {
  const nextTheme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  localStorage.setItem('casechain-portal-theme', nextTheme);
  setTheme(nextTheme);
});

const filters = document.querySelectorAll('[data-plan-filter]');
const cards = document.querySelectorAll('[data-plan-status]');
const emptyState = document.querySelector('[data-empty-filter]');

filters.forEach((filter) => {
  filter.addEventListener('click', () => {
    const selected = filter.dataset.planFilter;
    let visible = 0;
    filters.forEach((button) => button.setAttribute('aria-pressed', String(button === filter)));
    cards.forEach((card) => {
      const show = selected === 'all' || card.dataset.planStatus === selected;
      card.hidden = !show;
      if (show) visible += 1;
    });
    emptyState?.classList.toggle('is-visible', visible === 0);
  });
});
