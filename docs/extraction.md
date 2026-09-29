# Extracting the original game's files

The game uses the original Car Town art, sounds and data, but none of it is in Git. This page explains how to regenerate everything from a local copy of the original fan revival. Nothing produced here is committed: `_reference/` and `assets/ea/` are gitignored.

## What you need

- The revival files, placed at `alt/` in the repo root (gitignored). They must include `CarTownMain.swf`, `All/US`, `locale/`, `data/6/`, `static/` and `music/`.
- **Java 21** (Eclipse Adoptium works).
- **Python 3** with Pillow (`pip install pillow`).
- **JPEXS Free Flash Decompiler (FFDec) 26.3.0**, portable zip from
  https://github.com/jindrapetrik/jpexs-decompiler/releases/tag/version26.3.0.
  Unzip it to `_reference/tools/ffdec/`.
- **Godot 4.7.2** (standard, not .NET) from
  https://github.com/godotengine/godot/releases/tag/4.7.2-stable.
  The scripts look for the portable exe in `_reference/tools/godot/`.

`_reference/` and `alt/` each contain a `.gdignore` file so Godot doesn't import them.

## 1. Game data → `assets/ea/data/`

```sh
python tools/convert_catalog.py
```

This reads the zlib-compressed catalog (`alt/All/US`) and the English text tables (`alt/locale/300/en_US`, falling back to `431`). It writes 23 JSON files: cars, parts, colours, garage items, levels, lands, jobs, missions, locations and more. It takes a few seconds.

Our own balance changes are **not** here. They're in `data/tuning.json` (committed), which the game applies on top.

## 2. Art and sound → `assets/ea/art/`, `assets/ea/audio/`

```sh
python tools/export_art.py                 # everything (about 1.5 hours)
python tools/export_art.py --groups cars --ids 1,21
python tools/export_art.py --limit 20      # quick partial export
```

Groups:

| Group | Source | Output |
|---|---|---|
| `main` | Bitmaps inside `CarTownMain.swf` (tires, UI pieces) | `art/main/<class>.png` |
| `wheels` | `data/6/wheels/*_i_a.swf`, `_i_b`, `_a_a` | `art/wheels/`, `art/wheels.json` |
| `items` | `data/6/items/it_<id>.swf` (one frame per rotation), `_th` thumbnails, `.jpg` floor textures | `art/items/`, `art/item_thumbs/`, `art/floors/`, `art/items.json` |
| `cars` | `data/6/cars/<id>/{front,rear,angle}/*.zip` layers, `coords.xml`, thumbnails | `art/cars/<id>/<view>/<layer>.png`, `art/car_thumbs/`, `art/cars.json` |
| `town` | `static/gps/locationicons/`, `static/townracing/environment_*` | `art/town/`, `art/town.json` |
| `audio` | `music/*.mp3` and the sounds inside `CarTownMain.swf` | `audio/music/`, `audio/sfx/` |

How it works: each SWF is rendered by FFDec around its origin, then cropped. Before rendering, the script widens the SWF's stage so nothing is clipped and removes its background colour. The manifests record where the SWF origin sits in each PNG (`"o": [x, y]`), so the game can place sprites exactly like the original did.

The original art is pre-rendered bitmaps, not vectors, so it's exported at its native size. Rendering at 2x would only upscale it.

## 3. Decompiled code (reference only) → `_reference/`

Only needed if you want to read how the original worked:

```sh
java -jar _reference/tools/ffdec/ffdec-cli.jar -export script _reference/CarTownMain/scripts alt/CarTownMain.swf
python -c "import zlib; open('_reference/catalog/US.xml','wb').write(zlib.decompress(open('alt/All/US','rb').read()))"
python -c "import zlib; open('_reference/catalog/strings_en_US.xml','wb').write(zlib.decompress(open('alt/locale/300/en_US','rb').read()))"
```

The script export takes about 35 seconds and produces 5,200 ActionScript 3 classes. The game code is under `com/ciegames/cartown/` and `com/ciestudios/garage/`.

## 4. Open the project

Open the repo folder in Godot 4.7.2. The first import of `assets/ea/` takes a while.

Run the tests with:

```sh
tools/run_tests.sh
```
