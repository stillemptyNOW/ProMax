#!/usr/bin/env bash
set -euo pipefail
cd /opt/promax-hub/current
if ! id promax-hub >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/promax-hub --shell /usr/sbin/nologin promax-hub
fi
python3 -m venv /opt/promax-hub/venv
/opt/promax-hub/venv/bin/pip install -r requirements.txt
/opt/promax-hub/venv/bin/python -m unittest discover -s tests -v
install -d -o promax-hub -g promax-hub -m 0700 /var/lib/promax-hub
install -d -m 0755 /var/www/promax-push/.well-known/acme-challenge
install -m 0644 promax-hub.service /etc/systemd/system/promax-hub.service
install -m 0644 nginx.conf /etc/nginx/sites-available/promax-hub
ln -sfn /etc/nginx/sites-available/promax-hub /etc/nginx/sites-enabled/promax-hub
nginx -t
systemctl daemon-reload
systemctl enable --now promax-hub.service
systemctl restart promax-hub.service
systemctl reload nginx
umask 077
runuser -u promax-hub -- /opt/promax-hub/venv/bin/python manage.py issue-code > /root/promax-admin-activation.txt
systemctl is-active promax-hub.service
