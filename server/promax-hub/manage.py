import argparse
import json
import os
from app import Hub

parser = argparse.ArgumentParser()
parser.add_argument("command", choices=["issue-code", "logs", "cleanup", "revoke-admins"])
args = parser.parse_args()
hub = Hub(os.environ.get("PROMAX_HUB_DB", "/var/lib/promax-hub/hub.sqlite3"))
if args.command == "issue-code":
    print(hub.issue_code())
elif args.command == "cleanup":
    hub.cleanup()
elif args.command == "revoke-admins":
    with hub.db() as db:
        db.execute("DELETE FROM admins")
else:
    with hub.db() as db:
        for row in db.execute("SELECT created,event FROM telemetry ORDER BY id DESC LIMIT 100"):
            print(json.dumps(dict(row), ensure_ascii=False))
