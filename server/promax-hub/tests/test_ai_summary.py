import json
import sqlite3
import tempfile
import unittest
from contextlib import closing
from pathlib import Path
from unittest.mock import patch

from ai_summary import read_metrics, review, write_report


class ReportTests(unittest.TestCase):
    def test_only_aggregates_and_zero_features_survive_collection(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "synthetic.db"
            with closing(sqlite3.connect(database)) as db, db:
                db.execute("CREATE TABLE telemetry(created, installation, event)")
                for stage in ("featureSession", "featureBatchFiles", "webPushLink"):
                    db.execute("INSERT INTO telemetry VALUES(?, '', ?)", (100000, json.dumps({
                        "kind": "operation", "stage": stage, "outcome": "success",
                        "url": "https://example.test/synthetic-private-data",
                    })))
                db.execute("INSERT INTO telemetry VALUES(?, 'id', ?)", (100000, json.dumps({
                    "kind": "uncaught_error", "frames": ["synthetic-private-data"],
                })))
            metrics = read_metrics(database, 24, now=100001)
            self.assertEqual(metrics["usage"]["sessions_reported"], 1)
            self.assertEqual(metrics["usage"]["features"][0], {
                "feature": "featureBatchFiles", "sessions_with_usage_event": 1,
            })
            self.assertIn({"feature": "featureDigitalId", "sessions_with_usage_event": 0},
                          metrics["usage"]["features"])
            self.assertEqual(metrics["diagnostic_counts"], {"uncaught_error": 1})
            self.assertNotIn("synthetic-private-data", json.dumps(metrics))
            report = Path(directory) / "summary.json"
            write_report(report, metrics)
            self.assertEqual(json.loads(report.read_text(encoding="utf-8")), metrics)

    def test_model_cannot_report_an_unknown_feature(self):
        metrics = {"usage": {"features": []}, "operations": []}
        content = json.dumps({
            "summary": "Synthetic", "top_feature": "unknown", "priority_stage": None,
            "next_checks": [],
        })
        with patch("ai_summary.request_json", return_value={"choices": [{"message": {"content": content}}]}):
            with self.assertRaises(ValueError):
                review(metrics, "synthetic-model", "synthetic-key")
