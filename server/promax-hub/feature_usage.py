FEATURE_STAGES = (
    "featureSession", "featureAppearance", "featureSettingsShare",
    "featureDigitalId", "featureWebPush", "featureGroupEncryption",
    "featureBatchFiles", "featureAntiReadException", "featureChatSearch",
)


def usage_summary(db, since):
    placeholders = ",".join("?" for _ in FEATURE_STAGES)
    rows = db.execute(f"""
        SELECT json_extract(event, '$.stage') AS stage, COUNT(*)
        FROM telemetry
        WHERE created >= ? AND installation = ''
          AND json_extract(event, '$.kind') = 'operation'
          AND json_extract(event, '$.outcome') = 'success'
          AND json_extract(event, '$.stage') IN ({placeholders})
        GROUP BY stage
    """, (since, *FEATURE_STAGES))
    counts = dict(rows)
    return {
        "sessions_reported": counts.get("featureSession", 0),
        "features": sorted(
            ({"feature": stage, "sessions_with_usage_event": counts.get(stage, 0)}
             for stage in FEATURE_STAGES if stage != "featureSession"),
            key=lambda item: (-item["sessions_with_usage_event"], item["feature"]),
        ),
    }
