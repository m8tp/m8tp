#!/usr/bin/env python3
"""Reproduce the bundled atlas from a pinned public source (Pillow required)."""
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import urllib.request
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "scripts/map-source.json").read_text())
DEST = ROOT / "M8TPGTAMap/Resources"

def download(name):
    url = f"https://raw.githubusercontent.com/{CONFIG['repository']}/{CONFIG['commit']}/{CONFIG['variant']}/{name}"
    with urllib.request.urlopen(url, timeout=45) as response:
        data = response.read()
    image = Image.open(io.BytesIO(data)).convert("RGB")
    if image.size != (256, 256):
        raise ValueError(f"Unexpected tile size: {name}")
    return name, image, hashlib.sha256(data).hexdigest()

def main():
    names = CONFIG["tiles"]
    locations = [tuple(map(int, n.split("-")[1].split(".")[0].split("_"))) for n in names]
    width = (max(x for x, y in locations) + 1) * 256
    height = (max(y for x, y in locations) + 1) * 256
    atlas = Image.new("RGB", (width, height))
    hashes = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for name, image, digest in pool.map(download, names):
            x, y = map(int, name.split("-")[1].split(".")[0].split("_"))
            atlas.paste(image, (x * 256, y * 256))
            hashes[name] = digest
    # Remove only the black padding around the source tile canvas.
    # This crop is recorded; normalized marker coordinates use the cropped image.
    crop = atlas.getbbox()
    if crop is None:
        raise ValueError("Map tiles are empty")
    atlas = atlas.crop(crop)
    DEST.mkdir(parents=True, exist_ok=True)
    atlas.save(DEST / "GTAVAtlas.jpg", quality=94, optimize=True)
    manifest = dict(CONFIG, width=atlas.width, height=atlas.height,
                    tileCanvasWidth=width, tileCanvasHeight=height, crop=list(crop), sha256=hashes)
    (ROOT / "Docs/map-provenance.json").write_text(json.dumps(manifest, indent=2))
    license_url = f"https://raw.githubusercontent.com/{CONFIG['repository']}/{CONFIG['commit']}/LICENSE"
    with urllib.request.urlopen(license_url, timeout=45) as response:
        (DEST / "MapLicense.txt").write_bytes(response.read())
    print(f"Bundled atlas: {atlas.width} × {atlas.height}, {len(names)} tiles")

if __name__ == "__main__":
    main()
