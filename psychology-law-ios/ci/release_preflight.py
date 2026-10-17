#!/usr/bin/env python3
"""Fail closed: only a complete, valid native iOS bank may reach TestFlight."""
from pathlib import Path
import json, os, re, sys

root = Path(__file__).resolve().parents[1] / "full-project"
if os.environ.get("RELEASE_CONFIRM") != "FULL_BUILD_APPROVED":
    sys.exit("RELEASE BLOCKED: enter FULL_BUILD_APPROVED to confirm upload.")
if not re.fullmatch(r"\d+\.\d+\.\d+", os.environ.get("RELEASE_VERSION", "")):
    sys.exit("RELEASE BLOCKED: release_version must be like 1.0.0.")
bank_file = root / "PsychologyLawNative/Resources/questions.json"
icon_file = root / "PsychologyLawNative/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
project_file = root / "PsychologyLawNative.xcodeproj/project.pbxproj"
swift_app = root / "PsychologyLawNative/PsychologyLawApp.swift"
for p in (bank_file, icon_file, project_file, swift_app):
    if not p.is_file() or p.stat().st_size == 0:
        sys.exit(f"RELEASE BLOCKED: missing {p.relative_to(root)}")
bank = json.loads(bank_file.read_text(encoding="utf-8"))
if not isinstance(bank, list) or len(bank) != 325:
    sys.exit(f"RELEASE BLOCKED: require exactly 325 question records, found {len(bank)}.")
ids = set()
for item in bank:
    if not isinstance(item, dict) or not all(item.get(k) for k in ("id", "topic", "source", "question", "options", "explanation")):
        sys.exit("RELEASE BLOCKED: missing required question fields.")
    if item["id"] in ids or not isinstance(item["options"], list) or len(item["options"]) != 4 or not isinstance(item["correct"], int) or not 0 <= item["correct"] < 4:
        sys.exit(f"RELEASE BLOCKED: invalid or duplicated question {item['id']}.")
    ids.add(item["id"])
text = swift_app.read_text(encoding="utf-8")
if "import SwiftUI" not in text or "WebView" in text or "WKWebView" in text:
    sys.exit("RELEASE BLOCKED: expected native SwiftUI app without WebViews.")
if "com.simulapro.psychologylaw" not in project_file.read_text(encoding="utf-8"):
    sys.exit("RELEASE BLOCKED: wrong bundle ID.")
print(f"PASS: native app bundle contains {len(bank)} validated question records, icon, Xcode project.")
