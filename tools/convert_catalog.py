"""Convert the original game catalog and string tables into JSON for the game.

The output goes to assets/ea/data/ (gitignored) because it is derived from
the original game's data. Our own tuning lives in data/ and is applied on top
by the game at load time.

Usage (from the repo root):
    python tools/convert_catalog.py
    python tools/convert_catalog.py --catalog alt/All/US --out assets/ea/data \
        --strings alt/locale/300/en_US --strings alt/locale/431/en_US

String tables are merged in order; the first one that has an ID wins.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import zlib
from pathlib import Path
from xml.etree import ElementTree as ET

DEFAULT_CATALOG = "alt/All/US"
DEFAULT_STRINGS = ["alt/locale/300/en_US", "alt/locale/431/en_US"]
DEFAULT_OUT = "assets/ea/data"

STR_RE = re.compile(r'<str id="(\d+)"><!\[CDATA\[(.*?)\]\]></str>', re.S)
TAG_RE = re.compile(r"<[^>]+>")


def read_maybe_zlib(path: Path) -> str:
    raw = path.read_bytes()
    try:
        raw = zlib.decompress(raw)
    except zlib.error:
        pass
    return raw.decode("utf-8", "replace")


def load_strings(paths: list[Path]) -> dict[str, str]:
    strings: dict[str, str] = {}
    for p in paths:
        if not p.is_file():
            print(f"warning: string table {p} not found, skipping", file=sys.stderr)
            continue
        for sid, text in STR_RE.findall(read_maybe_zlib(p)):
            strings.setdefault(sid, text)
    return strings


class Ctx:
    def __init__(self, strings: dict[str, str]) -> None:
        self.strings = strings
        self.missing: set[str] = set()

    def text(self, sid: str | None, strip_markup: bool = True) -> str:
        if not sid or sid == "0":
            return ""
        t = self.strings.get(sid)
        if t is None:
            self.missing.add(sid)
            return ""
        # Strings are HTML-ish: drop the tags and decode entities (&reg; etc.).
        return html.unescape(TAG_RE.sub("", t)).strip() if strip_markup else t


def i(e: ET.Element, key: str, default: int = 0) -> int:
    v = e.get(key)
    if v is None or v == "":
        return default
    try:
        return int(float(v))
    except ValueError:
        return default


def f(e: ET.Element, key: str, default: float = 0.0) -> float:
    v = e.get(key)
    try:
        return float(v) if v not in (None, "") else default
    except ValueError:
        return default


def b(e: ET.Element, key: str) -> bool:
    return i(e, key) != 0


def id_list(e: ET.Element | None) -> list[int]:
    if e is None:
        return []
    return [int(x.text) for x in e if x.text and x.text.strip().lstrip("-").isdigit()]


def csv_ints(s: str | None) -> list[int]:
    if not s:
        return []
    return [int(x) for x in s.split(",") if x.strip().lstrip("-").isdigit()]


def shop_fields(e: ET.Element) -> dict:
    """Fields shared by everything sold in a shop."""
    return {
        "price": i(e, "p"),
        "blue_price": i(e, "cp"),
        "can_buy_with_coins": b(e, "cm"),
        "can_buy_with_blue": b(e, "cc"),
        "min_level": i(e, "ml"),
        "min_garage_value_tier": i(e, "mgv"),
        "purchasable": b(e, "ip"),
        "always_purchasable": b(e, "ipo"),
        "limited": b(e, "il"),
        "xp": i(e, "xp"),
        "sort": i(e, "so"),
        "date_added": i(e, "da"),
    }


def convert_consts(e: ET.Element) -> dict:
    # Keep every raw constant; the names we know are mapped for readability.
    known = {
        "ncd": "new_cutoff_days",
        "rp": "resell_fraction",
        "cus": "upgrade_score_per_stage",
        "cum": "upgrade_max_stage",
        "cmi": "upgrade_min_price",
        "cs1": "upgrade_stage1_multiplier",
        "cs2": "upgrade_stage2_multiplier",
        "cs3": "upgrade_stage3_multiplier",
        "cs4": "upgrade_stage4_multiplier",
        "cs5": "upgrade_stage5_multiplier",
        "csc": "upgrade_coins_to_blue_conversion",
        "vp": "vanity_plate_price",
        "vcp": "vanity_plate_blue_price",
        "crp": "ride_height_price",
        "crcp": "ride_height_blue_price",
        "hp": "help_neighbor_coins",
        "tcd": "trial_car_days",
        "tcw": "trial_car_min_race_wins",
        "rmx": "max_races_per_day",
        "rwm": "race_win_coins",
        "rwx": "race_win_xp",
        "rsx": "race_start_xp",
        # Street race prizes: coins and XP scale with the opponent's power
        # (TownRacingHelper.getPrizeObject).
        "rlmim": "race_prize_min_coins",
        "rlmam": "race_prize_max_coins",
        "rlmip": "race_prize_min_power",
        "rlmap": "race_prize_max_power",
        "rlmix": "race_prize_min_xp",
        "rlmax": "race_prize_max_xp",
        "ert": "fuel_refill_seconds",
        # The Docks (DocksDataSet): searching costs this % of the boat's
        # price, searching again this %.
        "dckpc": "docks_search_percent",
        "dckpcr": "docks_search_again_percent",
    }
    out: dict = {"raw": dict(e.attrib)}
    for k, name in known.items():
        if k in e.attrib:
            out[name] = f(e, k)
    # Cars the Docks never brings in.
    out["docks_excluded_cars"] = [int(x) for x in e.get("dckce", "").split(",") if x.strip()]
    return out


def convert(catalog_xml: str, ctx: Ctx) -> dict[str, object]:
    root = ET.fromstring(catalog_xml)
    sec = {c.tag: c for c in root}
    out: dict[str, object] = {}

    out["consts"] = convert_consts(sec["consts"])
    # Mystery boxes (MysteryBoxDataSet): a level per box, its garage item,
    # Blue Coin price and respin price, whether it was on sale, and the cars
    # it can hold. "ex" lists cars no box ever gives.
    myss = sec.get("myss")
    out["consts"]["mystery_excluded_cars"] = [int(x) for x in (myss.get("ex", "") if myss is not None else "").split(",") if x.strip()]
    out["mystery_boxes"] = [
        {"level": i(c, "id"), "item_id": i(c, "itid"), "blue_price": i(c, "cp"), "respin_blue": i(c, "rsp"),
         "available": c.get("a") == "1",
         "car_ids": [int(x) for x in c.get("cids", "").split(",") if x.strip()]}
        for c in (myss if myss is not None else [])
    ]

    out["car_classes"] = [
        {
            "id": i(c, "id"),
            "name": ctx.text(c.get("n")),
            "coins_per_passenger": i(c, "mep"),
            "xp_per_passenger": i(c, "xep"),
            "fill_up_bonus": i(c, "fb"),
            "join_coins": i(c, "me"),
            "join_xp": i(c, "xe"),
        }
        for c in sec["cls"]
    ]

    cars = []
    for c in sec["cs"]:
        d = {
            "id": i(c, "id"),
            "year": i(c, "y"),
            "make": html.unescape(c.get("m", "")),
            "model": html.unescape(c.get("md", "")),
            "description": ctx.text(c.get("d")) if (c.get("d") or "").isdigit() else (c.get("d") or ""),
            "score": i(c, "s"),
            "class_id": i(c, "cl"),
            "seats": i(c, "ns"),
            "collection_id": i(c, "ccid"),
            "category": i(c, "ct"),
            "date_first_available": i(c, "dfa"),
            "date_last_available": i(c, "dla"),
            "defaults": {
                "wheels": i(c, "dwh"),
                "tires": i(c, "dt"),
                "wing": i(c, "dw"),
                "body_kit": i(c, "dbk"),
                "hood": i(c, "dho"),
                "headlights": i(c, "dhl"),
                "taillights": i(c, "dtl"),
                "hood_accessory": i(c, "dha"),
                "graphics": i(c, "dg"),
            },
        }
        d.update(shop_fields(c))
        cars.append(d)
    out["cars"] = cars

    colors: dict[int, list[dict]] = {}
    for c in sec["ccs"]:
        colors.setdefault(i(c, "cid"), []).append({"id": i(c, "id"), "hex": (c.text or "").strip()})
    out["car_colors"] = {str(k): v for k, v in sorted(colors.items())}

    out["part_categories"] = [
        {"id": i(c, "id"), "name": ctx.text(c.get("n")), "universal": b(c, "iu"), "score": i(c, "s")}
        for c in sec["cpcs"]
    ]

    parts = []
    for c in sec["cps"]:
        d = {
            "id": i(c, "id"),
            "category_id": i(c, "cpid"),
            "car_id": i(c, "cid"),
            "name": ctx.text(c.get("n")),
            "size": i(c, "sz"),
            "is_stock": b(c, "is"),
            "asset_id": i(c, "ai"),
            "brand_id": i(c, "bi"),
        }
        d.update(shop_fields(c))
        parts.append(d)
    out["parts"] = parts

    items = []
    for c in sec["is"]:
        d = {
            "id": i(c, "id"),
            "category": i(c, "ic"),
            "group_id": i(c, "gid"),
            "name": ctx.text(c.get("n")),
            "description": ctx.text(c.get("d")) if (c.get("d") or "0") != "0" else "",
            "size_x": i(c, "x"),
            "size_y": i(c, "y"),
            "color_group": i(c, "cg"),
            # Walls with p1 = 1 are half height and can't hold posters (StageWall).
            "half_wall": i(c, "p1") == 1,
        }
        d.update(shop_fields(c))
        items.append(d)
    out["items"] = items

    out["item_colors"] = [
        {"id": i(c, "id"), "group": i(c, "cg"), "hex": (c.text or "").strip()} for c in sec["ics"]
    ]

    out["lands"] = [
        {
            "id": i(c, "id"),
            "size_x": i(c, "x"),
            "size_y": i(c, "y"),
            "price": i(c, "p"),
            "blue_price": i(c, "cp"),
            "min_level": i(c, "ml"),
            "min_garage_value_tier": i(c, "mgv"),
            "floors": i(c, "mf"),
        }
        for c in sec["las"]
    ]

    out["levels"] = [
        {
            "level": i(c, "id"),
            "xp": i(c, "xp"),
            "coin_bonus": i(c, "m"),
            "max_workers": i(c, "w"),
            "fuel_tank": i(c, "e"),
            "title": (c.text or "").strip(),
        }
        for c in sec["ls"]
    ]

    out["garage_value_tiers"] = [
        {"tier": i(c, "l"), "min_value": i(c, "mn"), "name": ctx.text(c.get("n")), "xp": i(c, "xp"), "blue": i(c, "c")}
        for c in sec["gvs"]
    ]

    jobs = []
    for c in sec["wts"]:
        jobs.append(
            {
                "id": i(c, "id"),
                "type": i(c, "tt"),  # 1 = special/event task, 2 = work bay job
                "name": ctx.text(c.get("n")),
                "price": i(c, "p"),
                "blue_price": i(c, "cp"),
                "finish_now_blue": i(c, "fp"),
                "minutes": i(c, "mc"),
                "coins": i(c, "me"),
                "xp": i(c, "xe"),
                "score_for_max_coins": i(c, "ms"),
                "min_level": i(c, "ml"),
                "specific_car_id": i(c, "sc"),
                "color": c.get("c", ""),
                "button_label": c.get("bl", ""),
                "dirt_type": i(c, "d"),
                "uses_lift": b(c, "l"),
                "anim_type": i(c, "a"),
                "is_delivery": b(c, "dv"),
                "is_car_build": b(c, "icb"),
                "mastery_thresholds": [0, i(c, "m2"), i(c, "m3"), i(c, "m4"), i(c, "m5")],
                "mastery_xp": [i(c, "xe"), i(c, "x2"), i(c, "x3"), i(c, "x4"), i(c, "x5")],
                "mastery_reward_item_id": i(c, "ri5"),
                "sort": i(c, "so"),
            }
        )
    # Which cars can do each car task (CarTasksHelper): car categories
    # (0 = all, -1 = none) and specific car ids (0 = none).
    ctas = {i(c, "id"): c for c in sec["ctas"]} if "ctas" in sec else {}
    for job in jobs:
        ct = ctas.get(job["id"])
        job["car_categories"] = csv_ints(ct.get("ccs")) if ct is not None else []
        job["car_ids"] = [x for x in csv_ints(ct.get("cids")) if x != 0] if ct is not None else []
    out["jobs"] = jobs

    out["task_mastery_levels"] = [
        {"level": i(c, "l"), "coin_bonus": i(c, "m"), "blue_bonus": i(c, "c"), "xp_bonus": i(c, "x")}
        for c in sec["tls"]
    ]

    out["item_jobs"] = [
        {"item_id": i(c, "id"), "name": ctx.text(c.get("n")), "minutes": i(c, "mc"), "coins": i(c, "me")}
        for c in sec["its"]
    ]

    out["locations"] = [
        {
            "id": i(c, "id"),
            "name": ctx.text(c.get("n")),
            "type": i(c, "t"),
            "min_level": i(c, "ml"),
            "sort": i(c, "s"),
            "raw": dict(c.attrib),
        }
        for c in sec["locs"]
    ]

    out["road_trips"] = [
        {
            "id": i(c, "id"),
            "name": ctx.text(c.get("c")),
            "title": ctx.text(c.get("jt")),
            "sort": i(c, "so"),
            "specific_car_id": i(c, "sc"),
            "coin_multiplier": f(c, "mm", 1.0),
            "xp_multiplier": f(c, "xm", 1.0),
        }
        for c in sec["rts"]
    ]

    out["consumables"] = [
        {"id": i(c, "id"), "kind": i(c, "cid"), "name": ctx.text(c.get("n")), "amount": i(c, "sz"), **shop_fields(c)}
        for c in sec["cns"]
    ]

    missions = []
    for c in sec["mdos"]:
        rt = c.find("rt")
        missions.append(
            {
                "id": i(c, "mid"),
                "index": f(c, "mi"),
                "category": (c.findtext("mc") or "").strip(),
                "title": ctx.text(c.get("tid")),
                "description": ctx.text(c.get("did")),
                "complete_text": ctx.text(c.get("cid")),
                "button_text": ctx.text(c.get("bid")),
                "min_level": i(c, "mlr"),
                "max_level": i(c, "mla"),
                "requires_missions": id_list(c.find("pmir")),
                "hidden_after_missions": id_list(c.find("dsami")),
                "coins": i(c, "me"),
                "xp": i(c, "xpe"),
                "blue": i(c, "ce"),
                "reward_type": (rt.text or "").strip() if rt is not None else "",
                "reward_id": i(c, "rid"),
                "location_id": i(c, "lid"),
                "start_date": i(c, "sd"),
                "end_date": i(c, "ed"),
                "icon_id": i(c, "aid"),
                "user_group": i(c, "ugid"),
                "hidden": b(c, "hrod"),
            }
        )
    out["missions"] = missions

    steps = []
    for c in sec["msdos"]:
        event = (c.findtext("ste") or "").strip()
        steps.append(
            {
                "id": i(c, "msid"),
                "event": event.split(".")[-1],
                "params": id_list(c.find("step")),
                "count": i(c, "ttc", 1),
                "mission_ids": id_list(c.find("mids")),
                "title": ctx.text(c.get("tid")),
                "description": ctx.text(c.get("did")),
                "icon_id": i(c, "aid"),
                "label": c.get("stl", ""),
            }
        )
    out["mission_steps"] = steps

    out["car_collections"] = [
        {
            "id": i(c, "id"),
            "name": ctx.text(c.get("n")),
            "coins": i(c, "me"),
            "xp": i(c, "xpe"),
            "plaque_item_id": i(c, "pid"),
            "reward_type": c.get("rt", ""),
            "reward_id": i(c, "rid"),
            "car_ids": [i(x, "id") for x in c.findall("c")],
        }
        for c in sec["ccls"]
    ]

    # One prize per day of the login streak (DailyRewardsDataSet); the
    # streak runs through them in order and starts over after the last.
    out["daily_rewards"] = [
        {"day": i(c, "d"), "type": c.get("t", ""), "id": i(c, "id"), "amount": i(c, "q")}
        for c in sorted(sec["dr"], key=lambda x: int(x.get("d", "0")))
    ]

    out["avatar_items"] = [
        {"id": i(c, "id"), "type": i(c, "t"), "group_id": i(c, "gid"), "name": ctx.text(c.get("n")), **shop_fields(c), "raw": dict(c.attrib)}
        for c in sec["as"]
    ]

    # NPC garages (used for street traffic/customers and later for racing).
    npcs = []
    for c in root.findall("npc"):
        u = c.find("u")
        cars_el = c.find("cs")
        npcs.append(
            {
                "id": i(u, "id") if u is not None else 0,
                "raw_user": dict(u.attrib) if u is not None else {},
                "cars": [dict(x.attrib) for x in cars_el] if cars_el is not None else [],
            }
        )
    out["npcs"] = npcs

    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", default=DEFAULT_CATALOG)
    ap.add_argument("--strings", action="append", default=None)
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    catalog = Path(args.catalog)
    if not catalog.is_file():
        print(f"error: catalog {catalog} not found", file=sys.stderr)
        return 1
    ctx = Ctx(load_strings([Path(p) for p in (args.strings or DEFAULT_STRINGS)]))
    data = convert(read_maybe_zlib(catalog), ctx)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, value in data.items():
        (out_dir / f"{name}.json").write_text(
            json.dumps(value, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
        )
        count = len(value) if isinstance(value, (list, dict)) else 1
        print(f"  {name}.json: {count}")
    if ctx.missing:
        print(f"note: {len(ctx.missing)} text IDs had no string (left blank)")
    print(f"wrote {len(data)} files to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
