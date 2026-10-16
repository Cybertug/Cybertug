#!/usr/bin/env python3
"""Fail closed: never send the seven-question UI pilot to TestFlight."""
from pathlib import Path
import json, os, re, sys

root = Path(__file__).resolve().parents[1]
main = root / "PsychologyLawNativeApp.swift"
source = main.read_text(encoding="utf-8")
if os.environ.get("RELEASE_CONFIRM") != "FULL_BUILD_APPROVED":
    sys.exit("RELEASE BLOCKED: type FULL_BUILD_APPROVED as the workflow confirmation.")

if re.search(r"\bseven-question interface pilot\b|Interface pilot only|native SwiftUI interface pilot", source, re.I):
    sys.exit("RELEASE BLOCKED: current app is explicitly labelled a seven-question interface pilot.")

# Check the bank actually included in the project (not an unrelated ZIP elsewhere).
swift_question_count = len(re.findall(r"\.init\s*\(\s*prompt\s*:", source))
bank_path = root / "Questions.json"
json_question_count = 0
if bank_path.is_file():
    data = json.loads(bank_path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        sys.exit("RELEASE BLOCKED: Questions.json must contain a list.")
    json_question_count = len(data)
question_count = max(swift_question_count, json_question_count)
if question_count < 325:
    sys.exit(f"RELEASE BLOCKED: only {question_count} bundled question records; require at least 325.")

icon_dir = root / "Assets.xcassets" / "AppIcon.appiconset"
if not (icon_dir / "Contents.json").is_file() or not list(icon_dir.glob("*.png")):
    sys.exit("RELEASE BLOCKED: missing native AppIcon asset catalog and PNG icon.")

if not re.fullmatch(r"\d+\.\d+\.\d+", os.environ.get("RELEASE_VERSION", "")):
    sys.exit("RELEASE BLOCKED: version must be MAJOR.MINOR.PATCH.")

print(f"PASS: release checked, {question_count} bundled questions, app icon found.")
