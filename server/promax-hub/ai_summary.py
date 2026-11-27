import argparse
import json
import os
import re
import sqlite3
import sys
import tempfile
import time
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, Request, build_opener

from feature_usage import usage_summary

API = "https://moduleapi.pro/v1"
MAX_RESPONSE = 131072
MODEL_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$")
SAFE_LABEL = re.compile(r"^[A-Za-z0-9_]{1,40}$")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def read_metrics(database, hours, now=None):
    now = time.time() if now is None else now
    cutoff = int(now) - hours * 3600
    uri = Path(database).resolve().as_uri() + "?mode=ro"
    with closing(sqlite3.connect(uri, uri=True, timeout=5)) as db, db:
        usage = usage_summary(db, cutoff)
        operations = [
            {"stage": stage, "outcome": outcome, "count": count}
            for stage, outcome, count in db.execute("""
                SELECT json_extract(event, '$.stage'), json_extract(event, '$.outcome'), COUNT(*)
                FROM telemetry
                WHERE created >= ? AND installation = ''
                  AND json_extract(event, '$.kind') = 'operation'
                  AND json_extract(event, '$.stage') NOT LIKE 'feature%'
                GROUP BY 1, 2 ORDER BY 3 DESC, 1, 2 LIMIT 60
            """, (cutoff,))
            if isinstance(stage, str) and SAFE_LABEL.fullmatch(stage)
            and isinstance(outcome, str) and SAFE_LABEL.fullmatch(outcome)
        ]
        crashes = dict(db.execute("""
            SELECT json_extract(event, '$.kind'), COUNT(*)
            FROM telemetry
            WHERE created >= ? AND json_extract(event, '$.kind')
                IN ('flutter_error', 'uncaught_error', 'log_error')
            GROUP BY 1
        """, (cutoff,)))
        performance = [
            {"platform": platform, "reports": reports, "frames": frames, "slow_frames": slow}
            for platform, reports, frames, slow in db.execute("""
                SELECT json_extract(event, '$.platform'), COUNT(*),
                       SUM(json_extract(event, '$.summary.frames')),
                       SUM(json_extract(event, '$.summary.slow'))
                FROM telemetry
                WHERE created >= ? AND json_extract(event, '$.kind') = 'performance'
                GROUP BY 1
            """, (cutoff,))
            if isinstance(platform, str) and SAFE_LABEL.fullmatch(platform)
        ]
    return {"hours": hours, "usage": usage, "operations": operations,
            "diagnostic_counts": crashes, "performance": performance}


def request_json(path, key, body=None):
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    request = Request(API + path, data=data, headers={
        "Authorization": "Bearer " + key,
        "Content-Type": "application/json",
        "Accept": "application/json",
    })
    with build_opener(NoRedirect()).open(request, timeout=30) as response:
        raw = response.read(MAX_RESPONSE + 1)
    if len(raw) > MAX_RESPONSE:
        raise ValueError("oversized_response")
    return json.loads(raw)


def review(metrics, model, key):
    if not MODEL_ID.fullmatch(model):
        raise ValueError("invalid_model")
    started = time.monotonic()
    response = request_json("/chat/completions", key, {
        "model": model,
        "max_completion_tokens": 900,
        "messages": [
            {"role": "system", "content": (
                "Вы анализируете агрегаты поддержки ProMax. Используйте только данные из запроса. "
                "Это добровольные события сеансов, а не число уникальных людей. Ноль означает "
                "отсутствие наблюдений; он не доказывает, что функция не используется. "
                "Назовите наиболее наблюдаемую функцию и этап с наибольшим числом сбоев. "
                "Если данных нет, используйте null. Верните только JSON без разметки с четырьмя ключами: "
                "summary (по-русски, до 600 символов), top_feature (точное имя или null), "
                "priority_stage (точное имя или null), next_checks (до трёх строк по-русски)."
            )},
            {"role": "user", "content": json.dumps(metrics, ensure_ascii=False, separators=(",", ":"))},
        ],
    })
    analysis = json.loads(response["choices"][0]["message"]["content"])
    expected = {"summary", "top_feature", "priority_stage", "next_checks"}
    if not isinstance(analysis, dict) or set(analysis) != expected:
        raise ValueError("invalid_review")
    valid_features = {None, *(entry["feature"] for entry in metrics["usage"]["features"]
                             if entry["sessions_with_usage_event"] > 0)}
    valid_stages = {None, *(entry["stage"] for entry in metrics["operations"]
                           if entry["outcome"] in {"failed", "timeout", "denied", "invalid"})}
    if (not isinstance(analysis["summary"], str) or not 1 <= len(analysis["summary"]) <= 900
            or analysis["top_feature"] not in valid_features
            or analysis["priority_stage"] not in valid_stages
            or not isinstance(analysis["next_checks"], list) or len(analysis["next_checks"]) > 3
            or not all(isinstance(x, str) and len(x) <= 350 for x in analysis["next_checks"])):
        raise ValueError("invalid_review")
    return {**analysis, "elapsed_ms": round((time.monotonic() - started) * 1000)}


def benchmark(models, key):
    fixture = {
        "hours": 24,
        "usage": {"sessions_reported": 10, "features": [
            {"feature": "featureBatchFiles", "sessions_with_usage_event": 6},
            {"feature": "featureChatSearch", "sessions_with_usage_event": 2},
            {"feature": "featureDigitalId", "sessions_with_usage_event": 0},
        ]},
        "operations": [
            {"stage": "webPushLink", "outcome": "failed", "count": 4},
            {"stage": "digitalIdCallback", "outcome": "failed", "count": 1},
        ],
        "diagnostic_counts": {},
    }
    for model in models:
        try:
            result = review(fixture, model, key)
            passed = result["top_feature"] == "featureBatchFiles" and result["priority_stage"] == "webPushLink"
            print(json.dumps({"model": model, "correct": passed, "elapsed_ms": result["elapsed_ms"]}))
        except HTTPError as error:
            print(json.dumps({"model": model, "correct": False, "http_status": error.code}))
        except (OSError, ValueError, KeyError, IndexError, TypeError):
            print(json.dumps({"model": model, "correct": False}))


def write_report(path, value):
    path = Path(path)
    pending = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
            pending = Path(stream.name)
            json.dump(value, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(pending, path)
    finally:
        if pending is not None:
            pending.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", default="/var/lib/promax-hub/hub.sqlite3")
    parser.add_argument("--output", default="/var/lib/promax-reports/summary.json")
    parser.add_argument("--hours", type=int, default=24, choices=range(1, 337))
    parser.add_argument("--benchmark", nargs="+")
    parser.add_argument("--models", action="store_true")
    parser.add_argument("--credential-stdin", action="store_true")
    args = parser.parse_args()
    credential_directory = os.environ.get("CREDENTIALS_DIRECTORY")
    key = (Path(credential_directory) / "api-key").read_text().strip() if credential_directory else ""
    if args.credential_stdin:
        key = sys.stdin.readline().strip()
    if args.models:
        for item in request_json("/models", key)["data"]:
            if isinstance(item.get("id"), str) and MODEL_ID.fullmatch(item["id"]):
                print(item["id"])
        return
    if args.benchmark:
        benchmark(args.benchmark, key)
        return
    model = os.environ.get("PROMAX_SUMMARY_MODEL", "")
    metrics = read_metrics(args.database, args.hours)
    status = "no_data"
    analysis = None
    if any((metrics["usage"]["sessions_reported"], metrics["operations"],
            metrics["diagnostic_counts"], metrics["performance"])):
        status = "unavailable"
        if key and model:
            try:
                analysis = review(metrics, model, key)
                status = "ok"
            except (OSError, ValueError, KeyError, IndexError, TypeError):
                pass
    write_report(args.output, {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "metrics": metrics,
        "analysis": {"status": status, "model": model or None, "result": analysis},
    })
    print("ProMax summary: " + status)


if __name__ == "__main__":
    main()
