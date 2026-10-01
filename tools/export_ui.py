"""Export the original UI (HUD, buttons, popups, panels) from the game's SWFs.

Output (gitignored): assets/ea/ui/
  symbols.json     every exported symbol's layers per frame (see below)
  layers/*.png     pre-rendered static art
  fonts/*.ttf      fonts embedded in the SWFs
  styles/*.ttf     fonts behind the game's text styles, styles.json maps them

How it works: FFDec dumps each SWF to XML. For each sprite we simulate its
display list frame by frame. Children that the game's code addresses by name
(text fields, needles, bars, buttons) are kept as separate entries so the
remake can change them; runs of unnamed children between them are rendered
together as one image. To render, we rebuild the SWF with a new main timeline
that shows one job per frame on a stage centred on (0, 0), let FFDec draw
every frame, and crop each PNG, recording where the origin landed.

Several SWFs are processed (the main client plus UI loaded at runtime). Keys
are namespaced "<lib>:<id>" so ids from different files can't clash.

symbols.json layout:
  {"classes": {class name: "lib:id"},
   "fonts": {"lib:id": {"name", "file"}},
   "chars": {"lib:id": {"type": "sprite", "frames": [[layer, ...], ...], "labels": {name: frame},
                        "grid": [x0, y0, x1, y1]?}
                       {"type": "text", "bounds": [x0,y0,x1,y1], "font": "lib:id", "size": px,
                        "color": "#rrggbb", "align": 0-3, "html": str, "text": str, "multiline", "wrap"}},
   "layers": {key: {"file", "o": [x, y]}}}
  layer = {"layer": key} | {"char": "lib:id", "name": str, "m": [a, b, c, d, tx, ty], "ct": [8] | null,
                            "f": [{"type", "color": "#rrggbbaa", "blur", "strength", "distance", "inner"}]?,
                            "blend": int?}  (SWF blend mode: 3 multiply, 4 screen, 8 add, 9 subtract)

Usage: python tools/export_ui.py [--only main,missions]
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ALT = ROOT / "alt"
FFDEC = ROOT / "_reference" / "tools" / "ffdec" / "ffdec-cli.jar"
STAGE = ROOT / "_reference" / "ui_stage"
OUT = ROOT / "assets" / "ea" / "ui"
HALF = 900  # px each side of the origin
# Libraries with bigger art: the Junk Yard is a whole scrolling scene.
HALF_BY_LIB = {"junkyard": 3200}
MAX_FRAMES = 100
# Classes that aren't UI (handled by other exporters or not needed).
SKIP_PREFIXES = ("swcassets.bmd.", "swcassets.sound.", "swcassets.tire.", "swcassets.car.")

# lib key -> SWF path (relative to alt/). The main client comes first so its
# class names win if a later file reuses one.
LIBS: dict[str, str] = {
    "main": "CarTownMain.swf",
    "missions": "static/missionsystem/MissionAssets.swf",
    "missionstatus": "static/missionsystem/MissionStatusPopup_v2.swf",
    "missiondone": "static/missionsystem/MissionCompletedPopup.swf",
    "finishtask": "static/gamepopups/FinishTaskNowPopup.swf",
    "gvlevelup": "static/garagevalue/GarageValueTierLevelUpPopup_v2.swf",
    "gvinfo": "static/garagevalue/GarageValueSelfInfoPopup_v4.swf",
    "locunlocked": "static/locations/LocationUnlockedPopupGraphic.swf",
    "locdenied": "static/locations/AccessDeniedPopupGraphic.swf",
    "billboard": "static/leaderboards/leaderboardsBillboard.swf",
    "trdialogs": "static/townracing/town_racing_dialogs.swf",
    "trwin": "static/townracing/town_racing_you_win_dialog.swf",
    "trlose": "static/townracing/town_racing_you_lose_dialog.swf",
    "trbuyfuel": "static/townracing/town_racing_buy_fuel_dialog.swf",
    "trfuelask": "static/townracing/town_racing_ask_for_fuel.swf",
    "dailyrewards": "static/gamepopups/DailyRewardsPopupV2.swf",
    "collections": "static/gamepopups/CarCollectionsPopupContent.swf",
    "collectiondone": "static/gamepopups/CarCollectionCompletePopupContent.swf",
    "collectiondetails": "static/gamepopups/CarCollectionDelegatePopupContent.swf",
    "trbottom": "static/townracing/racing_view_bottom_panel.swf",
    "clearfloor": "static/gamepopups/ClearGarageFloorPopup.swf",
    "newui": "static/gamepopups/NewUIPopup.swf",
    "features": "static/gamepopups/TutorialFeaturesPopup.swf",
    "docks": "static/docks/docks2.swf",
    "docksmanifest": "static/docks/shippingManifestPopup.swf",
    "tonymanhole": "static/docks/TonyInManHole.swf",
    "mbslot": "static/mysterybox/MysteryBoxSlotMachine.swf",
    "mbclaim": "static/mysterybox/MysteryBoxClaimOrRespinPopup.swf",
    "junkyard": "static/carrestoration/junkYard_v2.swf",
    "crassets": "static/carrestoration/CarRestorationUIAssets.swf",
    "crlist": "static/carrestoration/carRestorationCarListPopupContent_v2.swf",
    "crrestore": "static/carrestoration/carRestorationRestorePopupContent_v2.swf",
    "crdone": "static/carrestoration/carRestorationRestorationCompletePopupContent_v3.swf",
    "crpiles": "static/carrestoration/pilePopups.swf",
    "crbar": "static/carrestoration/carRestorationProgressBar.swf",
    "crconstruct": "static/carrestoration/carrestorationConstructionBG.swf",
    "crlift": "static/carrestoration/carrestorationCarLiftAngle.swf",
    "mmdone": "static/carrestoration/masterMechanicAchievedPopup.swf",
    "mmlist": "static/carrestoration/masterMechanicCarListPopup.swf",
    "mminfo": "static/carrestoration/masterMechanicInfoPopup.swf",
}

PLACE_TAGS = ("PlaceObject2Tag", "PlaceObject3Tag", "PlaceObjectTag")


def ffdec(*args: str) -> None:
    subprocess.run(["java", "-jar", str(FFDEC), *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def matrix_of(el: ET.Element | None) -> list[float]:
    if el is None:
        return [1, 0, 0, 1, 0, 0]
    sx = float(el.get("scaleX", 1)) if el.get("hasScale") == "true" else 1.0
    sy = float(el.get("scaleY", 1)) if el.get("hasScale") == "true" else 1.0
    r0 = float(el.get("rotateSkew0", 0)) if el.get("hasRotate") == "true" else 0.0
    r1 = float(el.get("rotateSkew1", 0)) if el.get("hasRotate") == "true" else 0.0
    # Flash: x' = a*x + c*y + tx ; y' = b*x + d*y + ty  (a=scaleX b=rotateSkew0 c=rotateSkew1 d=scaleY)
    return [sx, r0, r1, sy, int(el.get("translateX", 0)) / 20.0, int(el.get("translateY", 0)) / 20.0]


def ctransform_of(el: ET.Element | None) -> list[float] | None:
    if el is None:
        return None
    mult = el.get("hasMultTerms") == "true"
    add = el.get("hasAddTerms") == "true"
    vals = [int(el.get(f"{k}MultTerm", 256)) / 256.0 if mult else 1.0 for k in ("red", "green", "blue", "alpha")]
    vals += [int(el.get(f"{k}AddTerm", 0)) / 255.0 if add else 0.0 for k in ("red", "green", "blue", "alpha")]
    return vals


def filters_of(el: ET.Element | None) -> list[dict]:
    """Glow and drop shadow filters on a placement (text outlines, mostly)."""
    out: list[dict] = []
    for f in (el if el is not None else []):
        t = f.get("type")
        if t not in ("GLOWFILTER", "DROPSHADOWFILTER"):
            continue
        c = f.find("glowColor" if t == "GLOWFILTER" else "dropShadowColor")
        if c is None:
            continue
        out.append({
            "type": "glow" if t == "GLOWFILTER" else "shadow",
            "color": "#%02x%02x%02x%02x" % tuple(int(c.get(k)) for k in ("red", "green", "blue", "alpha")),
            "blur": (float(f.get("blurX", 0)) + float(f.get("blurY", 0))) / 2,
            "strength": float(f.get("strength", 1)),
            "distance": float(f.get("distance", 0)),
            "inner": f.get("innerGlow", f.get("innerShadow")) == "true",
        })
    return out


def simulate(sprite: ET.Element) -> tuple[list[dict[int, dict]], dict[str, int]]:
    """Display list snapshot per frame ([{depth: placement}]) and frame labels."""
    frames: list[dict[int, dict]] = []
    labels: dict[str, int] = {}
    current: dict[int, dict] = {}
    sub = sprite.find("subTags")
    for tag in (sub if sub is not None else []):
        t = tag.get("type")
        if t in PLACE_TAGS:
            depth = int(tag.get("depth"))
            move = tag.get("placeFlagMove") == "true"
            entry = dict(current.get(depth, {})) if move else {}
            if tag.get("characterId") is not None and tag.get("placeFlagHasCharacter") == "true":
                entry["char"] = int(tag.get("characterId"))
            if tag.find("matrix") is not None:
                entry["m"] = matrix_of(tag.find("matrix"))
            if tag.find("colorTransform") is not None:
                entry["ct"] = ctransform_of(tag.find("colorTransform"))
            if tag.get("name") is not None:
                entry["name"] = tag.get("name")
            filters = filters_of(tag.find("surfaceFilterList"))
            if filters:
                entry["f"] = filters
            if tag.get("placeFlagHasBlendMode") == "true":
                entry["blend"] = int(tag.get("blendMode", "0"))
            if tag.get("placeFlagHasClipDepth") == "true":
                entry["clip"] = int(tag.get("clipDepth"))
            entry.setdefault("m", [1, 0, 0, 1, 0, 0])
            entry["depth"] = depth
            entry["_xml"] = tag
            if "char" in entry:
                current[depth] = entry
        elif t in ("RemoveObject2Tag", "RemoveObjectTag"):
            current.pop(int(tag.get("depth")), None)
        elif t == "FrameLabelTag":
            labels[tag.get("name")] = len(frames)
        elif t == "ShowFrameTag":
            frames.append(dict(current))
    return frames, labels


def _matrix_xml(m: list[float]) -> dict[str, str]:
    return {"type": "MATRIX", "hasRotate": "true", "hasScale": "true", "nRotateBits": "0", "nScaleBits": "0",
            "nTranslateBits": "0", "scaleX": repr(float(m[0])), "scaleY": repr(float(m[3])),
            "rotateSkew0": repr(float(m[1])), "rotateSkew1": repr(float(m[2])),
            "translateX": str(int(round(m[4] * 20))), "translateY": str(int(round(m[5] * 20)))}


def process(lib: str, swf: Path, db: dict) -> None:
    work = STAGE / lib
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    xml_path = work / "swf.xml"
    ffdec("-swf2xml", str(swf), str(xml_path))
    if not xml_path.is_file():
        print(f"  {lib}: could not read {swf.name}", file=sys.stderr)
        return
    tree = ET.parse(xml_path)
    root = tree.getroot()
    tags = root.find("tags")

    def key(cid: int) -> str:
        return f"{lib}:{cid}"

    sprites: dict[int, ET.Element] = {}
    texts: dict[int, ET.Element] = {}
    grids: dict[int, list[float]] = {}
    fonts: dict[int, str] = {}
    max_id = 0
    for tag in tags:
        t = tag.get("type")
        if t not in PLACE_TAGS:
            for attr in ("spriteId", "shapeId", "characterID", "characterId", "fontID", "buttonId", "bitmapId"):
                v = tag.get(attr)
                if v is not None and v.isdigit():
                    max_id = max(max_id, int(v))
        if t == "DefineSpriteTag":
            sprites[int(tag.get("spriteId"))] = tag
        elif t == "DefineEditTextTag":
            texts[int(tag.get("characterID"))] = tag
        elif t == "DefineScalingGridTag":
            r = tag.find("splitter")
            grids[int(tag.get("characterId"))] = [int(r.get(k)) / 20.0 for k in ("Xmin", "Ymin", "Xmax", "Ymax")]
        elif t in ("DefineFont3Tag", "DefineFont2Tag"):
            fonts[int(tag.get("fontID"))] = tag.get("fontName", "").replace("\\u0000", "").strip(chr(0))
    classes: dict[str, int] = {}
    for tag in tags:
        if tag.get("type") == "SymbolClassTag":
            classes = dict(zip([x.text for x in tag.find("names")], [int(x.text) for x in tag.find("tags")]))
    for name, cid in classes.items():
        db["classes"].setdefault(name, key(cid))

    # Layers per sprite frame.
    jobs: list[tuple[str, list[dict]]] = []
    todo = [cid for name, cid in classes.items() if cid in sprites and not name.startswith(SKIP_PREFIXES)]
    seen: set[int] = set()
    while todo:
        cid = todo.pop()
        if cid in seen or cid not in sprites:
            continue
        seen.add(cid)
        frames, labels = simulate(sprites[cid])
        out_frames = []
        for fi, dl in enumerate(frames[:MAX_FRAMES]):
            layers: list[dict] = []
            run: list[dict] = []
            for depth in sorted(dl):
                p = dl[depth]
                dynamic = ("name" in p and "clip" not in p) or p["char"] in texts
                if dynamic:
                    if run:
                        lk = f"{lib}_{cid}_{fi}_{len(layers)}"
                        jobs.append((lk, list(run)))
                        layers.append({"layer": lk})
                        run = []
                    part = {"char": key(p["char"]), "name": p.get("name", ""), "m": p["m"], "ct": p.get("ct")}
                    if p.get("f"):
                        part["f"] = p["f"]
                    if p.get("blend", 0) > 2:
                        part["blend"] = p["blend"]
                    layers.append(part)
                    if p["char"] in sprites:
                        todo.append(p["char"])
                else:
                    run.append(p)
            if run:
                lk = f"{lib}_{cid}_{fi}_{len(layers)}"
                jobs.append((lk, list(run)))
                layers.append({"layer": lk})
            out_frames.append(layers)
        entry = {"type": "sprite", "frames": out_frames, "labels": labels, "frame_count": len(frames)}
        if cid in grids:
            entry["grid"] = grids[cid]
        db["chars"][key(cid)] = entry

    for tid, tag in texts.items():
        b = tag.find("bounds")
        col = tag.find("textColor")
        html = tag.get("html") == "true"
        db["chars"][key(tid)] = {
            "type": "text",
            "bounds": [int(b.get(k)) / 20 for k in ("Xmin", "Ymin", "Xmax", "Ymax")],
            "font": key(int(tag.get("fontId"))) if tag.get("hasFont") == "true" else "",
            "size": int(tag.get("fontHeight", 240)) / 20,
            "color": "#%02x%02x%02x" % tuple(int(col.get(c)) for c in ("red", "green", "blue")) if col is not None else "#000000",
            "align": int(tag.get("align", 0)),
            "html": tag.get("initialText", "") if html else "",
            "text": "" if html else tag.get("initialText", ""),
            "multiline": tag.get("multiline") == "true",
            "wrap": tag.get("wordWrap") == "true",
            "leading": int(tag.get("leading", 0)) / 20,
        }

    # Rebuild the SWF with one job per frame.
    keep = [t for t in list(tags) if t.get("type") not in PLACE_TAGS + (
        "ShowFrameTag", "FrameLabelTag", "RemoveObject2Tag", "RemoveObjectTag", "SetBackgroundColorTag", "EndTag")]
    for t in list(tags):
        tags.remove(t)
    for t in keep:
        tags.append(t)
    next_id = max_id + 1
    order: list[str] = []
    for lk, placements in jobs:
        sid = next_id
        next_id += 1
        sprite = ET.SubElement(tags, "item", {"type": "DefineSpriteTag", "forceWriteAsLong": "false",
                                               "frameCount": "1", "hasEndTag": "true", "spriteId": str(sid)})
        sub = ET.SubElement(sprite, "subTags")
        for p in placements:
            x = copy.deepcopy(p["_xml"])
            x.set("characterId", str(p["char"]))
            x.set("placeFlagHasCharacter", "true")
            x.set("placeFlagMove", "false")
            x.set("placeFlagHasMatrix", "true")
            for old in x.findall("matrix"):
                x.remove(old)
            x.insert(0, ET.Element("matrix", _matrix_xml(p["m"])))
            if "clip" not in p and "name" in x.attrib:
                del x.attrib["name"]
                x.set("placeFlagHasName", "false")
            sub.append(x)
        ET.SubElement(sub, "item", {"type": "ShowFrameTag", "forceWriteAsLong": "false"})
        place = ET.SubElement(tags, "item", {
            "type": "PlaceObject2Tag", "characterId": str(sid), "depth": "1", "forceWriteAsLong": "false",
            "placeFlagHasCharacter": "true", "placeFlagHasClipActions": "false", "placeFlagHasClipDepth": "false",
            "placeFlagHasColorTransform": "false", "placeFlagHasMatrix": "true", "placeFlagHasName": "false",
            "placeFlagHasRatio": "false", "placeFlagMove": "false"})
        ET.SubElement(place, "matrix", _matrix_xml([1, 0, 0, 1, 0, 0]))
        ET.SubElement(tags, "item", {"type": "ShowFrameTag", "forceWriteAsLong": "false"})
        ET.SubElement(tags, "item", {"type": "RemoveObject2Tag", "depth": "1", "forceWriteAsLong": "false"})
        order.append(lk)
    ET.SubElement(tags, "item", {"type": "EndTag", "forceWriteAsLong": "false"})
    root.set("frameCount", str(max(1, len(order))))
    rect = root.find("displayRect")
    half = HALF_BY_LIB.get(lib, HALF)
    for k, v in (("Xmin", -half), ("Xmax", half), ("Ymin", -half), ("Ymax", half)):
        rect.set(k, str(v * 20))
    rect.set("nbits", "17")
    tree.write(work / "render.xml", encoding="utf-8", xml_declaration=True)
    ffdec("-xml2swf", str(work / "render.xml"), str(work / "render.swf"))
    print(f"  {lib}: {len(seen)} symbols, rendering {len(order)} layers...")
    if order:
        ffdec("-format", "frame:png", "-export", "frame", str(work / "frames"), str(work / "render.swf"))
    (OUT / "layers").mkdir(parents=True, exist_ok=True)
    for n, lk in enumerate(order):
        fp = work / "frames" / f"{n + 1}.png"
        if not fp.is_file():
            continue
        img = Image.open(fp).convert("RGBA")
        bbox = img.getchannel("A").getbbox()
        if bbox is None:
            continue
        img.crop(bbox).save(OUT / "layers" / f"{lk}.png", optimize=True)
        db["layers"][lk] = {"file": f"layers/{lk}.png", "o": [half - bbox[0], half - bbox[1]]}

    ffdec("-format", "font:ttf", "-export", "font", str(work / "fonts"), str(swf))
    (OUT / "fonts").mkdir(parents=True, exist_ok=True)
    for f in (work / "fonts").glob("*.ttf"):
        m = re.match(r"(\d+)", f.stem)
        if m:
            shutil.copyfile(f, OUT / "fonts" / f"{lib}_{m.group(1)}.ttf")
            db["fonts"][key(int(m.group(1)))] = {"name": fonts.get(int(m.group(1)), ""), "file": f"fonts/{lib}_{m.group(1)}.ttf"}


def export_style_fonts() -> None:
    """Fonts behind the game's text styles (locale/styles/en_US.styles.xml)."""
    styles_dir = ALT / "locale" / "styles"
    stage = STAGE / "style_fonts"
    shutil.rmtree(stage, ignore_errors=True)
    ffdec("-format", "font:ttf", "-export", "font", str(stage), str(styles_dir / "fonts"))
    out = OUT / "styles"
    out.mkdir(parents=True, exist_ok=True)
    by_def: dict[str, str] = {}
    for f in stage.rglob("*.ttf"):
        # "<n>_<DefName>_<font name>.ttf" -> DefName (e.g. DomDiagonalFont_Bold)
        parts = f.stem.split("_")
        if len(parts) >= 3:
            def_name = parts[1] + "_" + parts[2]
            shutil.copyfile(f, out / f"{def_name}.ttf")
            by_def[def_name] = f"styles/{def_name}.ttf"
    styles: dict[str, dict] = {}
    for s in ET.parse(styles_dir / "en_US.styles.xml").getroot().findall("style"):
        d = s.get("def", "")
        if d in by_def:
            styles[s.get("id")] = {"file": by_def[d], "bold": s.get("bold") == "true"}
    (OUT / "styles.json").write_text(json.dumps(styles, indent=1), encoding="utf-8")
    print(f"text styles: {len(styles)}")


def heal_seams(png: Path) -> bool:
    """Fill hairline gaps between adjacent vector fills in a 9-slice panel.

    The rasterizer leaves a half-transparent 1 px line where two shapes meet;
    Flash never showed it, but stretching the slice would. A column (or row)
    is a seam when, along most of its length, it's noticeably more
    transparent than both neighbours while they're opaque.
    """
    from PIL import Image

    im = Image.open(png).convert("RGBA")
    w, h = im.size
    px = im.load()
    fixed = False
    for axis in ("x", "y"):
        n, m = (w, h) if axis == "x" else (h, w)
        for i in range(1, n - 1):
            hits = 0
            for j in range(m):
                a, b, c = ((px[i - 1, j], px[i, j], px[i + 1, j]) if axis == "x"
                           else (px[j, i - 1], px[j, i], px[j, i + 1]))
                if a[3] == 255 and c[3] == 255 and b[3] < 250:
                    hits += 1
            if hits < m * 0.5:
                continue
            for j in range(m):
                pos = (i, j) if axis == "x" else (j, i)
                a = px[i - 1, j] if axis == "x" else px[j, i - 1]
                c = px[i + 1, j] if axis == "x" else px[j, i + 1]
                if a[3] == 255 and c[3] == 255:
                    px[pos] = tuple((a[k] + c[k]) // 2 for k in range(4))
            fixed = True
    if fixed:
        im.save(png)
    return fixed


def heal_grid_layers(db: dict) -> None:
    for entry in db["chars"].values():
        if "grid" not in entry:
            continue
        for frame in entry["frames"]:
            for part in frame:
                info = db["layers"].get(part.get("layer", ""), {})
                if info.get("file") and heal_seams(OUT / info["file"]):
                    print(f"  healed seam in {info['file']}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="comma list of lib keys to (re)export; others are kept")
    ap.add_argument("--heal-only", action="store_true", help="only re-run the 9-slice seam fix on existing output")
    args = ap.parse_args()
    if not FFDEC.is_file():
        print("error: FFDec not found (see docs/extraction.md)", file=sys.stderr)
        return 1
    only = set(filter(None, args.only.split(",")))
    db_path = OUT / "symbols.json"
    if args.heal_only:
        heal_grid_layers(json.loads(db_path.read_text(encoding="utf-8")))
        return 0
    db = {"classes": {}, "fonts": {}, "chars": {}, "layers": {}}
    if only and db_path.is_file():
        old = json.loads(db_path.read_text(encoding="utf-8"))
        if "main:" in "".join(list(old.get("classes", {}).values())[:1]):
            # Keep entries from libs we aren't re-exporting.
            for section in db:
                for k, v in old.get(section, {}).items():
                    owner = (v if section == "classes" else k).split(":")[0].split("_")[0]
                    if owner not in only:
                        db[section][k] = v
    STAGE.mkdir(parents=True, exist_ok=True)
    for lib, rel in LIBS.items():
        if only and lib not in only:
            continue
        swf = ALT / rel
        if swf.is_file():
            process(lib, swf, db)
        else:
            print(f"  {lib}: {rel} not found, skipped")
    OUT.mkdir(parents=True, exist_ok=True)
    heal_grid_layers(db)
    db_path.write_text(json.dumps(db, separators=(",", ":")), encoding="utf-8")
    export_style_fonts()
    print(f"done: {len(db['chars'])} chars, {len(db['layers'])} layers, {len(db['fonts'])} fonts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
