'use strict';

const fragment = location.hash;
const status = document.getElementById('status');
if (location.href.length <= 16384 && /^#v1\.[A-Za-z0-9_-]+$/.test(fragment)) {
  const open = document.getElementById('open');
  open.href = 'promax://settings' + fragment;
  open.hidden = false;
  const copy = document.getElementById('copy');
  copy.hidden = false;
  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText('https://proma-x.xyz/settings' + fragment);
      status.textContent = 'Ссылка скопирована';
    } catch (_) {
      status.textContent = 'Скопируйте ссылку из адресной строки браузера';
    }
  });
} else {
  status.textContent = 'Ссылка повреждена или не поддерживается. Попросите отправителя экспортировать настройки заново.';
}
