let target = 'promax://open';
try {
  const uri = new URL(new URLSearchParams(location.search).get('to'));
  if (uri.protocol === 'promax:' && uri.hostname === 'open' && !uri.username && !uri.password) target = uri.href;
} catch {}
document.getElementById('open').addEventListener('click', () => { location.href = target; });
location.replace(target);
