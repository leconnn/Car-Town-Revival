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


def export_posters(ids: set[str] | None, limit: int | None) -> None:
    """Signs and posters as they hang on walls: the flat artwork the game
    skewed onto the wall (items/flatPosters, WallObj.applyRotation)."""
    src = SRC / "items" / "flatPosters"
    all_ids = sorted({p.stem[3:] for p in src.glob("it_*.swf") if p.stem[3:].isdigit()}, key=int)
    batch = Batch("posters", HALF["items"])
    for item_id in pick_ids(all_ids, ids, limit):
        batch.add(f"it_{item_id}", (src / f"it_{item_id}.swf").read_bytes(), OUT / "posters" / item_id)
    write_manifest("posters", {k[3:]: fr[0] for k, fr in batch.run().items() if fr})


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
    fields: dict[str, dict] = {}
    for p in sorted((static / "gps" / "locationicons").glob("*.swf")):
        key = f"icon_{p.stem}"
        swf_bytes, fields[key] = strip_icon_text(p)
        icons.add(key, swf_bytes, OUT / "town" / key)
    manifest: dict = {}
    for key, fr in icons.run().items():
        if fr:
            manifest[key] = {**fr[0], **fields.get(key, {})}
    for p in sorted((static / "townracing").glob("environment_*.swf")):
        env = export_town_environment(p)
        if env:
            manifest[p.stem] = env
    write_manifest("town", manifest)


def strip_icon_text(swf: Path) -> tuple[bytes, dict]:
    """GPS icons carry fldTitle/fldSubtitle text fields that the game filled
    in (GPSLocationButton); some still hold a placeholder. Remove them before
    rendering and return where they were: {"title": [x0, y0, x1, y1, size]}."""
    work = STAGE / "town_icon_text" / swf.stem
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    xml_path = work / "icon.xml"
    subprocess.run(["java", "-jar", str(FFDEC), "-swf2xml", str(swf), str(xml_path)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    if not xml_path.is_file():
        return swf.read_bytes(), {}
    tree = ET.parse(xml_path)
    tags = tree.getroot().find("tags")
    texts = {t.get("characterID"): t for t in tags if t.get("type") == "DefineEditTextTag"}
    out: dict = {}
    for pl in [t for t in tags if t.get("type", "").startswith("PlaceObject")]:
        name = pl.get("name") or ""
        if name not in ("fldTitle", "fldSubtitle"):
            continue
        text = texts.get(pl.get("characterId"))
        m = pl.find("matrix")
        if text is not None:
            b = text.find("bounds")
            tx = int(m.get("translateX", 0)) / 20 if m is not None else 0
            ty = int(m.get("translateY", 0)) / 20 if m is not None else 0
            out["title" if name == "fldTitle" else "subtitle"] = [
                tx + int(b.get("Xmin")) / 20, ty + int(b.get("Ymin")) / 20,
                tx + int(b.get("Xmax")) / 20, ty + int(b.get("Ymax")) / 20,
                int(text.get("fontHeight", 360)) / 20,
            ]
        tags.remove(pl)
    if not out:
        shutil.rmtree(work, ignore_errors=True)
        return swf.read_bytes(), {}
    tree.write(work / "stripped.xml", encoding="utf-8", xml_declaration=True)
    subprocess.run(["java", "-jar", str(FFDEC), "-xml2swf", str(work / "stripped.xml"), str(work / "stripped.swf")],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    data = (work / "stripped.swf").read_bytes() if (work / "stripped.swf").is_file() else swf.read_bytes()
    shutil.rmtree(work, ignore_errors=True)
    return data, out


# Town locations (AbstractTownLocation): "bg" is the ground and building,
# "fg" what's drawn over parked cars; the rest are invisible parking markers.
ENV_HALF = 2500
# Each marker symbol sets carRotation in its own frame script.
MARKER_ROTATION = {"ParkingSpotHoriz": 0, "ParkingMarker": 1, "CarMarkerHorizLeft": 2, "CarMarkerUp": 3}


def export_town_environment(swf: Path) -> dict:
    """Renders an environment's bg, fg (and movie) layers separately at full
    size and lists its parking markers:
    {"bg": {file, o, pos}, "fg": {...}, "markers": {name: [x, y, car rotation]}}."""
    work = STAGE / "town_env" / swf.stem
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    xml_path = work / "env.xml"
    subprocess.run(["java", "-jar", str(FFDEC), "-swf2xml", str(swf), str(xml_path)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    if not xml_path.is_file():
        return {}
    tree = ET.parse(xml_path)
    tags = tree.getroot().find("tags")
    classes: dict[str, str] = {}
    for t in tags:
        if t.get("type") == "SymbolClassTag":
            ids = [e.text for e in t.find("tags") or []]
            names = [e.text for e in t.find("names") or []]
            for cid, name in zip(ids, names):
                classes[cid] = name.split(".")[-1].rsplit("_", 1)[0]
    places = [t for t in tags if t.get("type", "").startswith("PlaceObject")]
    result: dict = {"markers": {}}
    for pl in places:
        name = pl.get("name") or ""
        m = pl.find("matrix")
        tx = int(m.get("translateX", 0)) / 20 if m is not None else 0
        ty = int(m.get("translateY", 0)) / 20 if m is not None else 0
        rot = MARKER_ROTATION.get(classes.get(pl.get("characterId", ""), ""), 0)
        if name.startswith("row"):
            result["markers"][name] = [tx, ty, rot]
    # "movie" is the drive-in's screen, drawn over the night-time shade.
    for layer in ("bg", "fg", "movie"):
        # Keep only this layer on the stage, moved to the stage's top-left
        # corner so all 4500 x 3915 px of it fit; render, crop.
        pos = [0.0, 0.0]
        for pl in places:
            m = pl.find("matrix")
            if pl.get("name") == layer and m is not None:
                pos = [int(m.get("translateX", 0)) / 20, int(m.get("translateY", 0)) / 20]
                m.set("translateX", str(-ENV_HALF * 20))
                m.set("translateY", str(-ENV_HALF * 20))
                m.set("nTranslateBits", "17")
        for pl in places:
            if pl.get("name") != layer and pl in list(tags):
                tags.remove(pl)
        for pl in places:
            if pl.get("name") == layer and pl not in list(tags):
                tags.insert(len(tags) - 2, pl)
        one = work / f"{layer}.xml"
        tree.write(one, encoding="utf-8", xml_declaration=True)
        raw = work / f"{layer}_raw.swf"
        subprocess.run(["java", "-jar", str(FFDEC), "-xml2swf", str(one), str(raw)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if not raw.is_file():
            continue
        batch = Batch(f"town_env_{swf.stem}_{layer}", ENV_HALF)
        batch.add(layer, raw.read_bytes(), OUT / "town" / f"{swf.stem}_{layer}")
        fr = batch.run().get(layer, [])
        if fr and fr[0]["file"]:
            # "o" relative to the layer's own origin; "pos" is where the
            # layer sat in the environment (the markers use those coordinates).
            info = fr[0]
            info["o"] = [info["o"][0] - ENV_HALF, info["o"][1] - ENV_HALF]
            info["pos"] = pos
            result[layer] = info
        # Put everything back for the next layer.
        for pl in places:
            if pl not in list(tags):
                tags.insert(len(tags) - 2, pl)
    shutil.rmtree(work, ignore_errors=True)
    return result if "bg" in result else {}


def export_static_ui(ids: set[str] | None, limit: int | None) -> None:
    """UI art the game loaded at runtime from static/ui (the work bay menu's
    service icon)."""
    batch = Batch("static_ui", 300)
    for p in pick_ids(sorted((ROOT / "alt" / "static" / "ui").glob("*.swf")), None, limit):
        batch.add(p.stem, p.read_bytes(), OUT / "static_ui" / p.stem)
    write_manifest("static_ui", {k: fr[0] for k, fr in batch.run().items() if fr})


def export_mysterybox(ids: set[str] | None, limit: int | None) -> None:
    """Mystery box art loaded as whole movies: the slot machine's backdrop per
    box (MysteryBoxBG_<level>), the claim popup's (MysteryBoxClaimBG_<level>)
    and the boxed car in Buy Cars (cars/mysterybox/angle_<level>)."""
    batch = Batch("mysterybox", 500)
    sources = sorted((ROOT / "alt" / "static" / "mysterybox").glob("MysteryBox*BG_*.swf"))
    sources += sorted((ROOT / "alt" / "data" / "6" / "cars" / "mysterybox").glob("angle_*.swf"))
    for p in pick_ids(sources, None, limit):
        batch.add(p.stem, p.read_bytes(), OUT / "mysterybox" / p.stem)
    write_manifest("mysterybox", {k: fr[0] for k, fr in batch.run().items() if fr})


def export_restoration(ids: set[str] | None, limit: int | None) -> None:
    """Car restoration art loaded as whole movies: the build part icons
    (carbuild/parts/part_<id>), the Junk Yard's two mechanics (first frame;
    they're animated) and the construction popup's backdrop."""
    batch = Batch("restoration", 400)
    sources = sorted((ROOT / "alt" / "static" / "carbuild" / "parts").glob("part_*.swf"))
    resto = ROOT / "alt" / "static" / "carrestoration"
    sources += [resto / n for n in ("JunkyardNPC.swf", "JunkyardNPC-mastermechanic.swf", "carrestorationConstructionBG.swf",
                                    "carrestorationCarLiftAngle.swf")]
    for p in pick_ids([s for s in sources if s.is_file()], None, limit):
        batch.add(p.stem, p.read_bytes(), OUT / "restoration" / p.stem)
    frames = batch.run()
    # Keep only the first frame of animated ones.
    for key, fr in frames.items():
        for extra in fr[1:]:
            if extra.get("file"):
                (OUT / extra["file"]).unlink(missing_ok=True)
    write_manifest("restoration", {k: fr[0] for k, fr in frames.items() if fr})


def export_avatar(ids: set[str] | None, limit: int | None) -> None:
    """Avatars. The 2D pieces from data/6/avatar (<id>_l.swf on the portrait,
    <id>_s.swf store icons, <id>_lb.swf hair backs), and the 3D worker: the
    Collada model and settings map embedded in CarTownMain.swf plus the
    textures in data/6/avatar/assets3d."""
    src = ROOT / "alt" / "data" / "6" / "avatar"
    batch = Batch("avatar", 300)
    for p in pick_ids(sorted(src.glob("*.swf")), None, limit):
        batch.add(p.stem, p.read_bytes(), OUT / "avatar" / p.stem)
    frames = batch.run()
    for key, fr in frames.items():
        for extra in fr[1:]:
            if extra.get("file"):
                (OUT / extra["file"]).unlink(missing_ok=True)
    write_manifest("avatar", {k: fr[0] for k, fr in frames.items() if fr})
    three_d = ROOT / "assets" / "ea" / "avatar3d"
    three_d.mkdir(parents=True, exist_ok=True)
    for jpg in (src / "assets3d").glob("*.jpg"):
        shutil.copyfile(jpg, three_d / jpg.name)
    stage = STAGE / "avatar3d"
    shutil.rmtree(stage, ignore_errors=True)
    classes = ("com.ciestudios.garage.components.avatar.AvatarGenerator__Animated,"
               "com.ciestudios.garage.components.avatar.AvatarGenerator__AvatarSettingsMap,"
               "com.ciestudios.garage.components.avatar.assets.EyesAsset__irisBytes")
    subprocess.run(["java", "-jar", str(FFDEC), "-selectclass", classes, "-export", "binaryData", str(stage),
                    str(ROOT / "alt" / "CarTownMain.swf")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    for b in stage.glob("*.bin"):
        if b.name.endswith("__Animated.bin"):
            shutil.copyfile(b, three_d / "avatar.dae")
        elif b.name.endswith("__AvatarSettingsMap.bin"):
            shutil.copyfile(b, three_d / "avatar_settings.xml")
        elif b.name.endswith("__irisBytes.bin"):
            shutil.copyfile(b, three_d / "iris.bin")
    # The iris (EyesAsset__irisBytes): a clip with a frame per eye colour.
    iris_swf = three_d / "iris.bin"
    if iris_swf.is_file():
        work = stage / "iris"
        work.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(iris_swf, work / "iris.swf")
        subprocess.run(["java", "-jar", str(FFDEC), "-format", "sprite:png", "-export", "sprite", str(work / "out"),
                        str(work / "iris.swf")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        for frame in (work / "out").glob("*/*.png"):
            img = Image.open(frame).convert("RGBA")
            box = img.getchannel("A").getbbox()
            if box:
                img.crop(box).save(OUT / "avatar" / f"iris_{int(frame.stem) - 1}.png")
    shutil.rmtree(stage, ignore_errors=True)
    print("  avatar3d: model, settings and textures")


def export_title(ids: set[str] | None, limit: int | None) -> None:
    """The original loading screen's art (preloader.swf) for the title
    screen: the Car Town logo (vector, drawn at 3x) and the yellow sunburst
    background."""
    swf = ROOT / "alt" / "preloader.swf"
    stage = STAGE / "title"
    shutil.rmtree(stage, ignore_errors=True)
    sprites = {"23": "logo"}
    subprocess.run(["java", "-jar", str(FFDEC), "-zoom", "3", "-selectid", ",".join(sprites),
                    "-export", "sprite", str(stage / "sprites"), str(swf)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["java", "-jar", str(FFDEC), "-selectid", "1", "-export", "image", str(stage / "images"), str(swf)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    out = OUT / "title"
    out.mkdir(parents=True, exist_ok=True)
    manifest: dict = {}
    for sid, name in sprites.items():
        src = stage / "sprites" / f"DefineSprite_{sid}" / "1.png"
        if not src.is_file():
            continue
        img = Image.open(src).convert("RGBA")
        img = img.crop(img.getchannel("A").getbbox())
        img.save(out / f"{name}.png", optimize=True)
        manifest[name] = {"file": f"title/{name}.png", "scale": 3}
    bg = next(iter((stage / "images").glob("1.*")), None)
    if bg is not None:
        Image.open(bg).convert("RGB").save(out / "bg.png", optimize=True)
        manifest["bg"] = {"file": "title/bg.png", "scale": 1}
    shutil.rmtree(stage, ignore_errors=True)
    write_manifest("title", manifest)


def export_audio(ids: set[str] | None, limit: int | None) -> None:
    """Music loops and the sound effects embedded in CarTownMain.swf."""
    audio = ROOT / "assets" / "ea" / "audio"
    (audio / "music").mkdir(parents=True, exist_ok=True)
    (audio / "sfx").mkdir(parents=True, exist_ok=True)
    for mp3 in (ROOT / "alt" / "music").glob("*.mp3"):
        shutil.copyfile(mp3, audio / "music" / mp3.name)
    stage = STAGE / "sounds"
    shutil.rmtree(stage, ignore_errors=True)
    # The main client's sounds, plus ones loaded with a feature's art (the
    # mystery box slot machine's).
    for swf in [ROOT / "alt" / "CarTownMain.swf", ROOT / "alt" / "static" / "mysterybox" / "MysteryBoxSlotMachine.swf"]:
        subprocess.run(
            ["java", "-jar", str(FFDEC), "-format", "sound:mp3_wav", "-export", "sound", str(stage), str(swf)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
    count = 0
    for p in stage.glob("*.*"):
        # "<charId>_swcassets.sound.ClickSound01.mp3" -> "ClickSound01.mp3"
        name = p.stem.split(".")[-1]
        # Classes without a package keep the id: "1_SlotReveal" -> "SlotReveal".
        head, _, rest = name.partition("_")
        if head.isdigit() and rest:
            name = rest
        shutil.copyfile(p, audio / "sfx" / f"{name}{p.suffix}")
        count += 1
    shutil.rmtree(stage, ignore_errors=True)
    print(f"  audio: music loops, {count} sound effects")


def export_missions(ids: set[str] | None, limit: int | None) -> None:
    """Mission, step and reward pictures (already PNGs in the revival files)."""
    src = ROOT / "alt" / "static" / "missions"
    dest = OUT / "missions"
    dest.mkdir(parents=True, exist_ok=True)
    count = 0
    for p in sorted(src.glob("*.png")):
        shutil.copyfile(p, dest / p.name)
        count += 1
    print(f"  missions: {count} pictures")


GROUPS = {
    "items": export_items, "posters": export_posters, "cars": export_cars, "wheels": export_wheels,
    "main": export_main, "town": export_town, "missions": export_missions, "static_ui": export_static_ui, "mysterybox": export_mysterybox, "restoration": export_restoration, "avatar": export_avatar, "title": export_title, "audio": export_audio,
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
