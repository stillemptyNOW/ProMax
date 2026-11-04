#!/usr/bin/env bash
set -euo pipefail
umask 077
release="${1:?release path required}"
case "$release" in /opt/promax-hub/releases/*) ;; *) exit 2 ;; esac
test -f "$release/app.py"
test -f "$release/site/index.html"
previous="$(readlink -f /opt/promax-hub/current)"
config="$(readlink -f /etc/nginx/sites-enabled/proma-x)"
backup="$(mktemp -d /root/promax-site-backup.XXXXXX)"
cp -a "$config" "$backup/nginx.conf"
printf '%s\n' "$previous" > "$backup/previous-release"
/opt/promax-hub/venv/bin/python -c 'import sqlite3,sys; source=sqlite3.connect("/var/lib/promax-hub/hub.sqlite3"); target=sqlite3.connect(sys.argv[1]); source.backup(target); target.close(); source.close()' "$backup/hub.sqlite3"
switched=0
rollback() {
    result=$?
    cp -a "$backup/nginx.conf" "$config"
    if [ "$switched" = 1 ]; then
        ln -sfn "$previous" /opt/promax-hub/current.next
        mv -Tf /opt/promax-hub/current.next /opt/promax-hub/current
        systemctl restart promax-hub
    fi
    nginx -t && systemctl reload nginx
    exit "$result"
}
trap rollback EXIT
install -m 0644 "$release/nginx-proma-x.conf" "$config"
nginx -t
ln -sfn "$release" /opt/promax-hub/current.next
mv -Tf /opt/promax-hub/current.next /opt/promax-hub/current
switched=1
systemctl restart promax-hub
curl --fail --silent --show-error --retry 10 --retry-connrefused --retry-delay 1 --max-time 2 http://127.0.0.1:8091/health
curl --fail --silent --output /dev/null http://127.0.0.1:8091/
systemctl reload nginx
trap - EXIT
printf '\nActivated %s\nBackup %s\n' "$release" "$backup"
