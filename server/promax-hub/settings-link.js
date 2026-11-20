'use strict';

const fragment = location.hash;
const status = document.getElementById('status');
const short = location.pathname === '/s' && /^#[A-Za-z0-9_-]{22}$/.test(fragment);
const portable = location.pathname === '/settings' && /^#v1\.[A-Za-z0-9_-]+$/.test(fragment);
if (!location.search && location.href.length <= 16384 && (short || portable)) {
  const open = document.getElementById('open');
  open.href = 'promax://settings' + (short ? '#v2.' + fragment.slice(1) : fragment);
  open.hidden = false;
  const copy = document.getElementById('copy');
  copy.hidden = false;
  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText('https://proma-x.xyz' + location.pathname + fragment);
      status.textContent = 'Ссылка скопирована';
    } catch (_) {
      status.textContent = 'Скопируйте ссылку из адресной строки браузера';
    }
  });
} else {
  status.textContent = 'Ссылка повреждена или не поддерживается. Попросите отправителя экспортировать настройки заново.';
}
