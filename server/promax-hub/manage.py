import argparse
import json
import os
from typing import get_args
from app import Hub, OperationStage

parser = argparse.ArgumentParser()
parser.add_argument("command", choices=["issue-code", "logs", "operations", "features", "cleanup", "revoke-admins"])
parser.add_argument("--hours", type=int, default=24, help="operations lookback (1–336 hours)")
parser.add_argument("--stage", choices=get_args(OperationStage), help="filter operations to one stage")
parser.add_argument("--limit", type=int, default=200, help="maximum operation groups (1–2000)")
args = parser.parse_args()
if args.command in ("operations", "features") and not (1 <= args.hours <= 336 and 1 <= args.limit <= 2000):
    parser.error("--hours must be 1–336 and --limit must be 1–2000")
hub = Hub(os.environ.get("PROMAX_HUB_DB", "/var/lib/promax-hub/hub.sqlite3"))
if args.command == "issue-code":
    print(hub.issue_code())
elif args.command == "cleanup":
    hub.cleanup()
elif args.command == "revoke-admins":
    with hub.db() as db:
        db.execute("DELETE FROM admins")
elif args.command == "operations":
    print(json.dumps(hub.operation_summary(args.hours, args.limit, args.stage), indent=2))
elif args.command == "features":
    print(json.dumps(hub.feature_summary(args.hours), indent=2))
else:
    with hub.db() as db:
        for row in db.execute("SELECT created,event FROM telemetry ORDER BY id DESC LIMIT 100"):
            print(json.dumps(dict(row), ensure_ascii=False))
