#!/usr/bin/env python3
"""Audit Arbore plant compatibility data without inventing missing values.

Examples:
  python3 scripts/audit_botanical_catalog.py --input plants.json
  ARBORE_API_KEY=... ARBORE_FIREBASE_TOKEN=... \
    python3 scripts/audit_botanical_catalog.py \
      --url https://api.example.com/plants --csv botanical-audit.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import urllib.request
from pathlib import Path
from typing import Any


FIELDS = (
    "environments",
    "minimumTemperatureC",
    "directSunHours",
    "indoorHumidityPercent",
    "wateringIntervalDays",
    "drainage",
    "matureHeightCm",
    "matureWidthCm",
    "minimumPotVolumeLiters",
    "minimumPotDepthCm",
    "windTolerance",
    "droughtTolerance",
    "saltTolerance",
    "petToxicity",
    "childToxicity",
)

CRITICAL_FIELDS = (
    "environments",
    "minimumTemperatureC",
    "directSunHours",
    "matureWidthCm",
    "minimumPotVolumeLiters",
    "petToxicity",
    "childToxicity",
)


def load_plants(path: str | None, url: str | None) -> list[dict[str, Any]]:
    if path:
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
    elif url:
        headers = {"Accept": "application/json"}
        api_key = os.getenv("ARBORE_API_KEY", "").strip()
        if api_key:
            headers["X-API-Key"] = api_key
        firebase_token = os.getenv("ARBORE_FIREBASE_TOKEN", "").strip()
        if firebase_token:
            headers["Authorization"] = f"Bearer {firebase_token}"
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    else:
        raise ValueError("Provide --input or --url")

    if not isinstance(payload, list):
        raise ValueError("Expected a JSON array of plants")
    return [plant for plant in payload if isinstance(plant, dict)]


def evidence_is_complete(fact: Any) -> bool:
    if not isinstance(fact, dict):
        return False
    evidence = fact.get("evidence")
    if not isinstance(evidence, dict):
        return False
    has_source = bool(str(evidence.get("sourceName", "")).strip()) or bool(
        str(evidence.get("sourceURL", "")).strip()
    )
    return (
        has_source
        and bool(str(evidence.get("reviewedAt", "")).strip())
        and str(evidence.get("reliability", "")).strip().lower() == "high"
    )


def value_is_present(fact: Any) -> bool:
    if not isinstance(fact, dict):
        return False
    if "value" in fact:
        value = fact["value"]
        return value is not None and value != "" and value != []
    return fact.get("minimum") is not None or fact.get("maximum") is not None


def audit_plant(plant: dict[str, Any]) -> dict[str, Any]:
    profile = plant.get("botanicalProfile")
    profile = profile if isinstance(profile, dict) else {}
    missing = [field for field in FIELDS if not value_is_present(profile.get(field))]
    unverified = [
        field
        for field in FIELDS
        if value_is_present(profile.get(field)) and not evidence_is_complete(profile.get(field))
    ]
    missing_critical = [field for field in CRITICAL_FIELDS if field in missing]
    unverified_critical = [field for field in CRITICAL_FIELDS if field in unverified]
    certifiable = not missing_critical and not unverified_critical

    return {
        "id": plant.get("id") or plant.get("_id") or "",
        "name": plant.get("name") or "Unnamed plant",
        "profile": bool(profile),
        "complete_fields": len(FIELDS) - len(missing),
        "verified_fields": len(FIELDS) - len(missing) - len(unverified),
        "missing": ",".join(missing),
        "unverified": ",".join(unverified),
        "missing_critical": ",".join(missing_critical),
        "unverified_critical": ",".join(unverified_critical),
        "certifiable": certifiable,
    }


def write_csv(path: str, rows: list[dict[str, Any]]) -> None:
    fields = list(rows[0].keys()) if rows else [
        "id",
        "name",
        "profile",
        "complete_fields",
        "verified_fields",
        "missing",
        "unverified",
        "missing_critical",
        "unverified_critical",
        "certifiable",
    ]
    with Path(path).open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--input", help="Exported /plants JSON file")
    source.add_argument("--url", help="Backend /plants endpoint")
    parser.add_argument("--csv", help="Optional detailed CSV output path")
    args = parser.parse_args()

    try:
        plants = load_plants(args.input, args.url)
    except Exception as error:  # noqa: BLE001 - CLI reports actionable cause
        print(f"Audit failed: {error}", file=sys.stderr)
        return 1

    rows = [audit_plant(plant) for plant in plants]
    certifiable = sum(bool(row["certifiable"]) for row in rows)
    with_profile = sum(bool(row["profile"]) for row in rows)
    verified_values = sum(int(row["verified_fields"]) for row in rows)
    possible_values = len(rows) * len(FIELDS)

    print(f"Plants: {len(rows)}")
    print(f"With botanical profile: {with_profile}/{len(rows)}")
    print(f"Certifiable on critical fields: {certifiable}/{len(rows)}")
    print(f"Verified field coverage: {verified_values}/{possible_values}")

    field_missing_counts = {
        field: sum(field in str(row["missing"]).split(",") for row in rows)
        for field in FIELDS
    }
    print("Most common missing fields:")
    for field, count in sorted(field_missing_counts.items(), key=lambda item: (-item[1], item[0])):
        print(f"  {field}: {count}")

    if args.csv:
        write_csv(args.csv, rows)
        print(f"Detailed CSV: {args.csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
