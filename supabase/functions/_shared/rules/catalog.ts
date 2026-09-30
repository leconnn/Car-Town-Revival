// Server copy of scripts/data/catalog.gd. Keep the two in step: the golden
// transcripts in tests/fixtures/golden/ check that they behave the same.

// deno-lint-ignore-file no-explicit-any
export type Dict = Record<string, any>;

export const DEFAULT_PAINT = 0xcc2222;

export const REQUIRED_FILES = [
  "consts", "cars", "car_colors", "parts", "part_categories", "items",
  "lands", "levels", "garage_value_tiers", "jobs", "task_mastery_levels",
  "missions", "mission_steps", "locations", "consumables", "daily_rewards", "car_collections",
];

export class Catalog {
  consts: Dict = {};
  tuning: Dict = {};
  cars = new Map<number, Dict>();
  carColors = new Map<number, Dict[]>();
  parts = new Map<number, Dict>();
  partCategories = new Map<number, Dict>();
  items = new Map<number, Dict>();
  lands = new Map<number, Dict>();
  levels: Dict[] = [];
  garageValueTiers: Dict[] = [];
  jobs = new Map<number, Dict>();
  taskMasteryLevels: Dict[] = [];
  missions = new Map<number, Dict>();
  missionSteps = new Map<number, Dict>();
  locations = new Map<number, Dict>();
  consumables = new Map<number, Dict>();
  dailyRewards: Dict[] = [];
  carCollections = new Map<number, Dict>();
  stepsByMission = new Map<number, Dict[]>();
  stockParts = new Map<number, Map<number, number>>();
  /** Car ids with exported art. Empty means unknown (no filtering). */
  artCarIds = new Set<number>();

  /** Builds a catalog from already-parsed JSON files plus tuning. */
  static fromData(raw: Dict, tuning: Dict): Catalog {
    const c = new Catalog();
    c.tuning = tuning;
    c.consts = raw.consts;
    for (const x of raw.cars) c.cars.set(x.id, x);
    for (const key of Object.keys(raw.car_colors)) c.carColors.set(Number(key), raw.car_colors[key]);
    for (const p of raw.parts) {
      c.parts.set(p.id, p);
      if (p.is_stock && p.car_id !== 0) {
        if (!c.stockParts.has(p.car_id)) c.stockParts.set(p.car_id, new Map());
        c.stockParts.get(p.car_id)!.set(p.category_id, p.id);
      }
    }
    for (const pc of raw.part_categories) c.partCategories.set(pc.id, pc);
    for (const it of raw.items) c.items.set(it.id, it);
    for (const la of raw.lands) c.lands.set(la.id, la);
    c.levels = [...raw.levels].sort((a, b) => a.level - b.level);
    c.garageValueTiers = [...raw.garage_value_tiers].sort((a, b) => a.tier - b.tier);
    for (const j of raw.jobs) c.jobs.set(j.id, j);
    c.taskMasteryLevels = [...raw.task_mastery_levels];
    for (const m of raw.missions) c.missions.set(m.id, m);
    for (const s of raw.mission_steps) {
      c.missionSteps.set(s.id, s);
      for (const mid of s.mission_ids) {
        if (!c.stepsByMission.has(mid)) c.stepsByMission.set(mid, []);
        c.stepsByMission.get(mid)!.push(s);
      }
    }
    for (const loc of raw.locations) c.locations.set(loc.id, loc);
    for (const x of raw.consumables ?? []) c.consumables.set(x.id, x);
    c.dailyRewards = [...(raw.daily_rewards ?? [])];
    for (const x of raw.car_collections ?? []) c.carCollections.set(x.id, x);
    return c;
  }

  consumable(id: number): Dict {
    return this.consumables.get(id) ?? {};
  }

  car(id: number): Dict { return this.cars.get(id) ?? {}; }
  part(id: number): Dict { return this.parts.get(id) ?? {}; }
  item(id: number): Dict { return this.items.get(id) ?? {}; }
  /** A car colour as 0xRRGGBB. */
  colorRgb(carId: number, colorId: number): number {
    for (const c of this.colorsForCar(carId)) {
      if (c.id === colorId) return parseInt(String(c.hex).replace(/^#/, ""), 16);
    }
    return DEFAULT_PAINT;
  }

  job(id: number): Dict { return this.jobs.get(id) ?? {}; }
  land(id: number): Dict { return this.lands.get(id) ?? {}; }

  maxLevel(): number {
    return this.levels.length ? this.levels[this.levels.length - 1].level : 1;
  }

  levelInfo(level: number): Dict {
    const index = Math.min(Math.max(level, 1), this.maxLevel()) - 1;
    return this.levels[index];
  }

  levelForXp(xp: number): number {
    let result = 1;
    for (const lv of this.levels) {
      if (xp >= lv.xp) result = lv.level;
      else break;
    }
    return result;
  }

  garageValueTier(value: number): number {
    let result = 1;
    for (const t of this.garageValueTiers) if (value >= t.min_value) result = t.tier;
    return result;
  }

  colorsForCar(carId: number): Dict[] { return this.carColors.get(carId) ?? []; }

  stockPart(carId: number, categoryId: number): number {
    return this.stockParts.get(carId)?.get(categoryId) ?? 0;
  }

  tune(path: string, fallback: any = null): any {
    let node: any = this.tuning;
    for (const key of path.split(".")) {
      if (node === null || typeof node !== "object" || Array.isArray(node) || !(key in node)) return fallback;
      node = node[key];
    }
    return node;
  }
}
