#!/usr/bin/env python3
"""Portable checks for project graph, resources and bundled data. Not an iOS compiler."""
import json
import plistlib
import re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def parse_openstep(text):
    text = re.sub(r"//[^\n]*", "", text)
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text)
    position = 0
    def consume(expected):
        nonlocal position
        if tokens[position] != expected: raise ValueError(f"Expected {expected}, got {tokens[position]}")
        position += 1
    def value():
        nonlocal position
        token = tokens[position]; position += 1
        if token == "{":
            output = {}
            while tokens[position] != "}":
                key = value(); consume("="); output[key] = value(); consume(";")
            consume("}"); return output
        if token == "(":
            output = []
            while tokens[position] != ")": output.append(value()); consume(",")
            consume(")"); return output
        if token.startswith('"'): return json.loads(token)
        return token
    output = value()
    if position != len(tokens): raise ValueError("Trailing project data")
    return output

def validate_dataset(path):
    d = json.loads(path.read_text())
    assert d["schemaVersion"] == 1 and d["coordinateSpace"] == "normalized-image-v1"
    cats = {c["id"] for c in d["categories"]}
    assert len(cats) == len(d["categories"])
    assert len({m["id"] for m in d["markers"]}) == len(d["markers"])
    for marker in d["markers"]:
        assert marker["categoryID"] in cats and marker["title"]
        assert 0 <= marker["x"] <= 1 and 0 <= marker["y"] <= 1
    return d

def main():
    pbx = parse_openstep((ROOT / "M8TPGTAMap.xcodeproj/project.pbxproj").read_text())
    objects = pbx["objects"]
    assert objects[pbx["rootObject"]]["isa"] == "PBXProject"
    references = ["fileRef", "mainGroup", "productRefGroup", "productReference", "buildConfigurationList"]
    lists = ["children", "files", "targets", "buildPhases", "buildConfigurations"]
    for obj in objects.values():
        for key in references:
            if key in obj: assert obj[key] in objects, (key, obj[key])
        for key in lists:
            for ref in obj.get(key, []): assert ref in objects, ref
    def resolve_group(ref, parent):
        obj = objects[ref]
        if obj.get("sourceTree") == "BUILT_PRODUCTS_DIR": return
        path = parent / obj.get("path", "")
        if obj["isa"] == "PBXGroup":
            for child in obj["children"]: resolve_group(child, path)
        else: assert path.exists(), path
    resolve_group(objects[pbx["rootObject"]]["mainGroup"], ROOT)
    scheme = ET.parse(ROOT / "M8TPGTAMap.xcodeproj/xcshareddata/xcschemes/M8TPGTAMap.xcscheme")
    for buildable in scheme.findall(".//BuildableReference"):
        assert objects[buildable.attrib["BlueprintIdentifier"]]["isa"] == "PBXNativeTarget"
    source_files = {p.name for p in (ROOT / "M8TPGTAMap/Sources").glob("*.swift")}
    bundled_sources = {o["path"] for o in objects.values() if o.get("lastKnownFileType") == "sourcecode.swift"}
    assert source_files == bundled_sources
    catalog = validate_dataset(ROOT / "M8TPGTAMap/Resources/catalog.json")
    demo = validate_dataset(ROOT / "M8TPGTAMap/Resources/demo.json")
    assert not catalog["isDemo"] and len(catalog["markers"]) == 933
    counts = {c["id"]: sum(m["categoryID"] == c["id"] for m in catalog["markers"]) for c in catalog["categories"]}
    for key, count in {"playing-cards":54, "action-figures":100, "signal-jammers":50, "ld-organics":100}.items():
        assert counts[key] == count, (key, counts[key])
    assert counts["pumpkins"] == 0
    assert sum(count > 0 for count in counts.values()) == 38
    assert demo["isDemo"] and len(demo["markers"]) == 9
    for path in ["M8TPGTAMap/Info.plist", "M8TPGTAMap/Resources/PrivacyInfo.xcprivacy"]:
        plistlib.loads((ROOT / path).read_bytes())
    for contents in (ROOT / "M8TPGTAMap/Resources/Assets.xcassets").rglob("Contents.json"):
        asset = json.loads(contents.read_text())
        for image in asset.get("images", []):
            if "filename" in image: assert (contents.parent / image["filename"]).is_file()
    assert (ROOT / "M8TPGTAMap/Resources/GTAVAtlas.jpg").stat().st_size > 100_000
    assert (ROOT / "M8TPGTAMap/Resources/MapLicense.txt").is_file()
    assert (ROOT / "M8TPGTAMap/Resources/GTAVCommunity.jpg").stat().st_size > 100_000
    print("Portable project checks passed: Xcode graph, shared scheme, source membership, assets, plists and datasets.")
    print("Native compilation and device behavior still require the configured macOS build.")

if __name__ == "__main__": main()
