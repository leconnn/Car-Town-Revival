"""Export the original game's SWF art to PNG for Godot.

Output goes to assets/ea/art/ (gitignored). Needs Java and FFDec (see
docs/extraction.md) plus Python with Pillow.

Each SWF is rendered around its origin: we widen the SWF stage to a square
centred on (0, 0), remove the background colour, let FFDec render every frame,
then crop to the visible pixels. The manifest records where the SWF origin
ended up inside each cropped PNG ("o": [x, y]) so sprites can be placed
exactly like the original did.

Usage (from the repo root):
    python tools/export_art.py                     # everything
    python tools/export_art.py --groups items      # one group
    python tools/export_art.py --groups cars --ids 1,2,1002
    python tools/export_art.py --limit 20          # first N of each group
"""

from __future__ import annotations

import argparse
import json
import shutil
import struct
import subprocess
import sys
import zipfile
import zlib
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "alt" / "data" / "6"
OUT = ROOT / "assets" / "ea" / "art"
STAGE = ROOT / "_reference" / "art_stage"
FFDEC = ROOT / "_reference" / "tools" / "ffdec" / "ffdec-cli.jar"

CAR_VIEWS = ("front", "rear", "angle")
HALF = {"items": 700, "thumbs": 300, "cars": 450, "wheels": 250}


# --- SWF patching -----------------------------------------------------------

def _rect_bytes(xmin: int, xmax: int, ymin: int, ymax: int) -> bytes:
    nbits = 17
    bits = format(nbits, "05b") + "".join(format(v & ((1 << nbits) - 1), f"0{nbits}b") for v in (xmin, xmax, ymin, ymax))
    bits += "0" * ((8 - len(bits) % 8) % 8)
    return bytes(int(bits[k:k + 8], 2) for k in range(0, len(bits), 8))


def patch_swf(data: bytes, half: int) -> bytes:
    """Centre the stage on the origin and drop SetBackgroundColor."""
    sig, ver = data[:3], data[3]
    if sig == b"CWS":
        body = zlib.decompress(data[8:])
    elif sig == b"FWS":
        body = data[8:]
    else:
        raise ValueError(f"unsupported SWF signature {sig!r}")
    nbits = body[0] >> 3
    rect_len = (5 + 4 * nbits + 7) // 8
    rest = body[rect_len:]
    header, tags = rest[:4], rest[4:]
    kept = bytearray()
    pos = 0
    while pos < len(tags):
        code_len = struct.unpack("<H", tags[pos:pos + 2])[0]
        code, length, hdr = code_len >> 6, code_len & 0x3F, 2
        if length == 0x3F:
            length = struct.unpack("<I", tags[pos + 2:pos + 6])[0]
            hdr = 6
        if code != 9:
            kept += tags[pos:pos + hdr + length]
        pos += hdr + length
        if code == 0:
            break
    twips = half * 20
    new_body = _rect_bytes(-twips, twips, -twips, twips) + header + bytes(kept)
    return b"FWS" + bytes([ver]) + struct.pack("<I", len(new_body) + 8) + new_body


# --- FFDec batch rendering ----------------------------------------------------

class Batch:
    """Collects SWFs for one FFDec run, then crops the rendered frames."""

    def __init__(self, name: str, half: int) -> None:
        self.name = name
        self.half = half
        self.in_dir = STAGE / name / "in"
        self.out_dir = STAGE / name / "out"
        shutil.rmtree(STAGE / name, ignore_errors=True)
        self.in_dir.mkdir(parents=True)
        self.jobs: dict[str, Path] = {}  # staged name -> destination stem

    def add(self, key: str, swf_bytes: bytes, dest_stem: Path) -> None:
        try:
            patched = patch_swf(swf_bytes, self.half)
        except (ValueError, zlib.error, struct.error) as e:
            print(f"  skip {key}: {e}", file=sys.stderr)
            return
        (self.in_dir / f"{key}.swf").write_bytes(patched)
        self.jobs[key] = dest_stem

    def run(self) -> dict[str, list[dict]]:
        """Render and crop. Returns {key: [{"file", "o", "size"} per frame]}."""
        if not self.jobs:
            return {}
        print(f"  rendering {len(self.jobs)} SWFs ({self.name})...")
        subprocess.run(
            ["java", "-jar", str(FFDEC), "-format", "frame:png", "-export", "frame", str(self.out_dir), str(self.in_dir)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
        results: dict[str, list[dict]] = {}
        for key, dest in self.jobs.items():
            frame_dir = self.out_dir / f"{key}.swf"
            if not frame_dir.is_dir():
                continue
            frames = sorted(frame_dir.glob("*.png"), key=lambda p: int(p.stem))
            out: list[dict] = []
            for n, fp in enumerate(frames):
                img = Image.open(fp).convert("RGBA")
                bbox = img.getchannel("A").getbbox()
                if bbox is None:
                    out.append({"file": "", "o": [0, 0], "size": [0, 0]})
                    continue
                cropped = img.crop(bbox)
                target = dest.with_name(f"{dest.name}_{n}.png") if len(frames) > 1 else dest.with_suffix(".png")
                target.parent.mkdir(parents=True, exist_ok=True)
                cropped.save(target, optimize=True)
                out.append({
                    "file": target.relative_to(OUT).as_posix(),
                    "o": [self.half - bbox[0], self.half - bbox[1]],
                    "size": list(cropped.size),
                })
            results[key] = out
        shutil.rmtree(STAGE / self.name, ignore_errors=True)
        return results


def pick_ids(all_ids: list[str], ids: set[str] | None, limit: int | None) -> list[str]:
    chosen = [x for x in all_ids if ids is None or x in ids]
    return chosen[:limit] if limit else chosen


def write_manifest(name: str, data: dict) -> None:
    path = OUT / f"{name}.json"
    old = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    old.update(data)
    path.write_text(json.dumps(old, separators=(",", ":")), encoding="utf-8")
    print(f"  {name}.json: {len(old)} entries")


# --- Groups -----------------------------------------------------------------

def export_items(ids: set[str] | None, limit: int | None) -> None:
    src = SRC / "items"
    all_ids = sorted({p.stem[3:] for p in src.glob("it_*.swf") if p.stem[3:].isdigit()}, key=int)
    chosen = pick_ids(all_ids, ids, limit)
    batch = Batch("items", HALF["items"])
    thumbs = Batch("thumbs", HALF["thumbs"])
    for item_id in chosen:
        batch.add(f"it_{item_id}", (src / f"it_{item_id}.swf").read_bytes(), OUT / "items" / item_id)
        th = src / f"it_{item_id}_th.swf"
        if th.is_file():
            thumbs.add(f"th_{item_id}", th.read_bytes(), OUT / "item_thumbs" / item_id)
    # Floor textures are plain JPEGs.
    for jpg in src.glob("it_*.jpg"):
        item_id = jpg.stem[3:]
        if ids is None or item_id in ids:
            (OUT / "floors").mkdir(parents=True, exist_ok=True)
            shutil.copyfile(jpg, OUT / "floors" / f"{item_id}.jpg")
    frames = batch.run()
    th_frames = thumbs.run()
    manifest = {}
    for item_id in chosen:
        entry: dict = {"frames": frames.get(f"it_{item_id}", [])}
        th = th_frames.get(f"th_{item_id}")
        if th:
            entry["thumb"] = th[0]
        manifest[item_id] = entry
    write_manifest("items", manifest)


def _coords(xml_bytes: bytes) -> dict:
    root = ET.fromstring(xml_bytes)
    views: dict = {"_attrs": dict(root.attrib)}
    for view in root:
        entries = {}
        for c in view:
            label = c.findtext("label") or ""
            entries[label] = {k.tag: k.text for k in c if k.tag != "label"}
        views[view.tag] = entries
    return views


def export_cars(ids: set[str] | None, limit: int | None) -> None:
    src = SRC / "cars"
    all_ids = sorted((p.name for p in src.iterdir() if p.is_dir() and p.name.isdigit()), key=int)
    chosen = pick_ids(all_ids, ids, limit)
    batch = Batch("cars", HALF["cars"])
    thumbs = Batch("car_thumbs", HALF["thumbs"])
    meta: dict[str, dict] = {}
    for car_id in chosen:
        folder = src / car_id
        info: dict = {"coords": {}, "views": {}}
        if (folder / "coords.xml").is_file():
            info["coords"] = _coords((folder / "coords.xml").read_bytes())
        for view in CAR_VIEWS:
            vdir = folder / view
            if not vdir.is_dir():
                continue
            packs: dict[str, list[str]] = {}
            for z in sorted(vdir.glob("*.zip")):
                try:
                    zf = zipfile.ZipFile(z)
                except zipfile.BadZipFile:
                    continue
                layers = []
                for name in zf.namelist():
                    if name.endswith(".swf"):
                        layer = Path(name).stem
                        batch.add(f"c{car_id}__{view}__{layer}", zf.read(name), OUT / "cars" / car_id / view / layer)
                        layers.append(layer)
                    elif name.endswith("coords.xml"):
                        # Pack-level coords override the car-level ones for this view.
                        pack_coords = _coords(zf.read(name)).get(view, {})
                        info["coords"].setdefault(view, {}).update(pack_coords)
                packs[z.stem] = layers
            info["views"][view] = {"packs": packs, "layers": {}}
        th = folder / f"ca_{car_id}_th.swf"
        if th.is_file():
            thumbs.add(f"cth_{car_id}", th.read_bytes(), OUT / "car_thumbs" / car_id)
        meta[car_id] = info
    frames = batch.run()
    th_frames = thumbs.run()
    for key, fr in frames.items():
        car_id, view, layer = key[1:].split("__")
        if fr:
            meta[car_id]["views"][view]["layers"][layer] = fr[0]
    for car_id, info in meta.items():
        th = th_frames.get(f"cth_{car_id}")
        if th:
            info["thumb"] = th[0]
    write_manifest("cars", meta)


def export_wheels(ids: set[str] | None, limit: int | None) -> None:
    src = SRC / "wheels"
    all_ids = sorted({p.name.split("_")[0] for p in src.glob("*_?_?.swf") if p.name.split("_")[0].isdigit()}, key=int)
    chosen = pick_ids(all_ids, ids, limit)
    batch = Batch("wheels", HALF["wheels"])
    for asset_id in chosen:
        for kind in ("i_a", "i_b", "a_a"):
            f = src / f"{asset_id}_{kind}.swf"
            if f.is_file():
                batch.add(f"w{asset_id}__{kind}", f.read_bytes(), OUT / "wheels" / f"{asset_id}_{kind}")
    frames = batch.run()
    manifest: dict[str, dict] = {}
    for key, fr in frames.items():
        asset_id, kind = key[1:].split("__")
        manifest.setdefault(asset_id, {})[kind] = fr
    write_manifest("wheels", manifest)


def export_main(ids: set[str] | None, limit: int | None) -> None:
    """Bitmaps embedded in CarTownMain.swf (tires, UI pieces), named by class."""
    stage = STAGE / "main"
    shutil.rmtree(stage, ignore_errors=True)
    subprocess.run(
        ["java", "-jar", str(FFDEC), "-export", "image", str(stage), str(ROOT / "alt" / "CarTownMain.swf")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    dest = OUT / "main"
    dest.mkdir(parents=True, exist_ok=True)
    count = 0
    for p in [*stage.glob("*.png"), *stage.glob("*.jpg")]:
        # FFDec names files "<charId>_<class>_<class>.png"; keep the class name.
        parts = p.stem.split("_", 1)
        if len(parts) < 2 or "." not in parts[1]:
            continue
        cls = parts[1][: len(parts[1]) // 2] if parts[1][: len(parts[1]) // 2] == parts[1][len(parts[1]) // 2 + 1:] else parts[1]
        shutil.copyfile(p, dest / f"{cls}{p.suffix}")
        count += 1
    shutil.rmtree(stage, ignore_errors=True)
    print(f"  main: {count} images")


def export_town(ids: set[str] | None, limit: int | None) -> None:
    """GPS map location icons and the town location backgrounds."""
    static = ROOT / "alt" / "static"
    icons = Batch("town_icons", 300)
    for p in sorted((static / "gps" / "locationicons").glob("*.swf")):
        icons.add(f"icon_{p.stem}", p.read_bytes(), OUT / "town" / f"icon_{p.stem}")
    envs = Batch("town_envs", 1200)
    for p in sorted((static / "townracing").glob("environment_*.swf")):
        envs.add(p.stem, p.read_bytes(), OUT / "town" / p.stem)
    manifest: dict = {}
    for key, fr in {**icons.run(), **envs.run()}.items():
        if fr:
            manifest[key] = fr[0]
    write_manifest("town", manifest)


def export_audio(ids: set[str] | None, limit: int | None) -> None:
    """Music loops and the sound effects embedded in CarTownMain.swf."""
    audio = ROOT / "assets" / "ea" / "audio"
    (audio / "music").mkdir(parents=True, exist_ok=True)
    (audio / "sfx").mkdir(parents=True, exist_ok=True)
    for mp3 in (ROOT / "alt" / "music").glob("*.mp3"):
        shutil.copyfile(mp3, audio / "music" / mp3.name)
    stage = STAGE / "sounds"
    shutil.rmtree(stage, ignore_errors=True)
    subprocess.run(
        ["java", "-jar", str(FFDEC), "-format", "sound:mp3_wav", "-export", "sound", str(stage), str(ROOT / "alt" / "CarTownMain.swf")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    count = 0
    for p in stage.glob("*.*"):
        # "<charId>_swcassets.sound.ClickSound01.mp3" -> "ClickSound01.mp3"
        name = p.stem.split(".")[-1]
        shutil.copyfile(p, audio / "sfx" / f"{name}{p.suffix}")
        count += 1
    shutil.rmtree(stage, ignore_errors=True)
    print(f"  audio: 2 music loops, {count} sound effects")


GROUPS = {
    "items": export_items, "cars": export_cars, "wheels": export_wheels,
    "main": export_main, "town": export_town, "audio": export_audio,
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--groups", default=",".join(GROUPS), help="comma list: " + ",".join(GROUPS))
    ap.add_argument("--ids", default=None, help="comma list of ids to export (per group)")
    ap.add_argument("--limit", type=int, default=None, help="export only the first N of each group")
    args = ap.parse_args()
    if not FFDEC.is_file():
        print(f"error: FFDec not found at {FFDEC} (see docs/extraction.md)", file=sys.stderr)
        return 1
    ids = set(args.ids.split(",")) if args.ids else None
    OUT.mkdir(parents=True, exist_ok=True)
    for g in args.groups.split(","):
        print(f"{g}:")
        GROUPS[g](ids, args.limit)
    return 0


if __name__ == "__main__":
    sys.exit(main())
