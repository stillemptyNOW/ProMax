export async function recordDownload(asset, event, fetcher = fetch) {
  const response = await fetcher('/v1/downloads', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({asset, event}),
    keepalive: true,
  });
  if (!response.ok) throw new Error('download count unavailable');
  const value = await response.json();
  if (!Number.isSafeInteger(value.started) || value.started < 1) throw new Error('invalid download count');
  return value.started;
}
