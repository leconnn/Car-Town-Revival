// Server copy of scripts/rules/game_logic.gd. Same functions, same order,
// same messages. Change both together; the golden transcripts check it.
import type { Catalog, Dict } from "./catalog.ts";
import {
  CAT_FLOOR_TILE, CAT_WORK_BAY, GarageGrid, HORIZONTAL, isFloorObject, isWall, isWallObject,
  rotatedSize, VERTICAL, wallLength, wallObjectLength,
} from "./grid.ts";
import { MissionTracker } from "./missions.ts";
import { key, posmod, roundi, SimpleRng } from "./util.ts";

export const CURRENT_SAVE_VERSION = 12;

export class GameResult {
  ok = true;
  error = "";
  data: Dict = {};
  notices: Dict[] = [];

  static fail(message: string): GameResult {
    const r = new GameResult();
    r.ok = false;
    r.error = message;
    return r;
  }

  static success(values: Dict = {}): GameResult {
    const r = new GameResult();
    r.data = values;
    return r;
  }

  toDict(): Dict {
    return { ok: this.ok, error: this.error, data: this.data, notices: this.notices };
  }
}

const RE_PLATE = /^[A-Z0-9 ]+$/;
/** Categories whose parts go into storage when taken off a car (UpdateUserCarCommand). */
const STORED_PART_CATEGORIES = [1, 2, 4, 5, 6, 10];
const AVATAR_SLOTS: Record<number, string> = { 1: "eyes", 2: "mouth", 3: "brows", 4: "facial_hair", 5: "hair", 6: "misc", 7: "hat", 8: "top", 9: "bottom", 10: "nose", 11: "head", 12: "bottom" };
const AVATAR_OPTIONAL = [4, 6, 7];
const AVATAR_COLORS: Record<number, number> = { 11: 8, 5: 8, 4: 8, 3: 8, 1: 9 };

export function defaultAvatar(): Dict {
  return {"head": 68, "eyes": 1, "mouth": 12, "brows": 20, "facial_hair": 0, "hair": 33, "misc": 0, "hat": 0, "top": 53, "bottom": 57, "nose": 60, "settings": {"head": 20000, "eyes": 5425, "mouth": 5300, "brows": 7226, "facial_hair": 0, "hair": 0, "misc": 0, "nose": 6200}};
}

const BUILD_RESTORATION = 42;
const BUILD_MASTER_MECHANIC = 43;
const BOX_NEW = 0;
const BOX_SPUN = 1;
const BOX_RESPUN = 2;
const BOX_SPUN_AGAIN = 3;
const DOCK_CRATES = 8;
const CRATE_CLOSED = 0;
const CRATE_OPEN = 1;
const CRATE_PASSED = 2;

function percentUp(amount: number, percent: number): number {
  return Math.trunc((amount * percent + 99) / 100);
}

/** WorkerTask.TASKID_ROADTRIP. */
const ROAD_TRIP_JOB = 34;

export class GameLogic {
  catalog: Catalog;
  save: Dict;
  missions: MissionTracker;
  private dealerIds = new Set<number>();

  constructor(catalog: Catalog, save: Dict) {
    this.catalog = catalog;
    this.save = save;
    this.missions = new MissionTracker(catalog);
    for (const id of this.dealer_car_ids()) this.dealerIds.add(id);
    this.upgradeLegacyWalls();
  }

  // --- New game -------------------------------------------------------------

  static newSave(cat: Catalog, playerName: string, now: number): Dict {
    const start: Dict = cat.tune("start", {});
    const s: Dict = {
      save_version: CURRENT_SAVE_VERSION,
      created_at: now,
      updated_at: now,
      player: { name: playerName, coins: start.coins ?? 10000, blue: start.blue ?? 0, xp: 0, level: 1, fuel: 0, fuel_at: now },
      next_uid: 1,
      rng: now % SimpleRng.MODULUS,
      garage: {
        land_id: start.land_id ?? 1,
        floor_item_id: start.floor_item_id ?? 0,
        floor_tiles: {},
        items: [],
        walls: [],
        wall_items: [],
      },
      cars: [],
      storage: {},
      part_storage: {},
      jobs: {},
      car_tasks: {},
      job_mastery: {},
      customers: [],
      next_customer_at: now,
      missions: { progress: {}, completed: [], daily: {} },
      tutorial: { step: 0, done: false },
      visited_locations: [],
      race: {},
      daily_reward: { last_day: -1, streak: 0 },
      collections_done: [],
      docks: { first_done: false, last_claim: -1, boat: {} },
      mystery_boxes: {},
      restoration: { builds: {}, inventory: {}, last_pile_at: -1, next_gift_at: -1, restored: [], count: 0 },
      avatar: defaultAvatar(),
      avatar_owned: [],
      stats: {},
    };
    const logic = new GameLogic(cat, s);
    s.player.fuel = logic.fuelTank();
    for (const it of start.items ?? []) logic.addItem(it.item_id, it.x, it.y, it.rot);
    const carId: number = start.car_id ?? 0;
    if (Object.keys(cat.car(carId)).length > 0) {
      const colors = cat.colorsForCar(carId);
      const colorIndex: number = start.car_color_index ?? 0;
      const colorId = colorIndex < colors.length ? colors[colorIndex].id : 0;
      const car = logic.addCar(carId, colorId);
      const jobId: number = start.job?.job_id ?? 0;
      const bay = s.garage.items.find((it: Dict) => logic.isBay(it.uid))?.uid ?? 0;
      if (jobId !== 0 && bay !== 0 && Object.keys(cat.job(jobId)).length > 0) {
        car.bay_uid = bay;
        car.placed = true;
        const minutes: number = cat.job(jobId).minutes;
        s.jobs[key(bay)] = { job_id: jobId, started_at: now - minutes * 60, ends_at: now };
      }
    }
    return s;
  }

  // --- Helpers ----------------------------------------------------------------

  private uid(): number {
    const id: number = this.save.next_uid;
    this.save.next_uid = id + 1;
    return id;
  }

  private get player(): Dict { return this.save.player; }

  private find(listKey: string, uid: number): Dict | undefined {
    return this.save[listKey].find((e: Dict) => e.uid === uid);
  }

  private findItem(uid: number): Dict | undefined {
    return this.save.garage.items.find((e: Dict) => e.uid === uid);
  }

  get_car(uid: number): Dict | undefined { return this.find("cars", uid); }
  get_customer(uid: number): Dict | undefined { return this.find("customers", uid); }

  private charge(def: Dict, useBlue: boolean, multiplier = 1.0): string {
    const p = this.player;
    if (useBlue) {
      const cost = Math.ceil((def.blue_price ?? 0) * multiplier);
      if (!(def.can_buy_with_blue ?? false) || cost <= 0) return "This can't be bought with blue coins.";
      if (p.blue < cost) return "Not enough blue coins.";
      p.blue -= cost;
    } else {
      const cost = Math.ceil((def.price ?? 0) * multiplier);
      if (!(def.can_buy_with_coins ?? true) && cost > 0) return "This can only be bought with blue coins.";
      if (p.coins < cost) return "Not enough coins.";
      p.coins -= cost;
    }
    return "";
  }

  private levelOk(def: Dict): string {
    if (this.player.level < (def.min_level ?? 0)) return `Requires level ${def.min_level}.`;
    if ((def.min_garage_value_tier ?? 0) > this.garageValueTier()) {
      return `Requires a more valuable garage (tier ${def.min_garage_value_tier}).`;
    }
    return "";
  }

  private bumpStat(k: string, amount = 1): void {
    this.save.stats[k] = (this.save.stats[k] ?? 0) + amount;
  }

  // --- Economy ------------------------------------------------------------------

  addRewards(coins: number, blue: number, xp: number, result: GameResult): void {
    const p = this.player;
    p.coins += coins;
    p.blue += blue;
    p.xp += xp;
    const newLevel = this.catalog.levelForXp(p.xp);
    while (p.level < newLevel) {
      p.level += 1;
      const info = this.catalog.levelInfo(p.level);
      const bonusBlue: number = this.catalog.tune("economy.blue_per_level_up", 0);
      p.coins += info.coin_bonus;
      p.blue += bonusBlue;
      result.notices.push({
        kind: "level_up", level: p.level, title: info.title ?? "", coins: info.coin_bonus, blue: bonusBlue,
      });
    }
  }

  garageValue(): number {
    let total = 0;
    for (const c of this.save.cars) total += this.catalog.car(c.car_id).price ?? 0;
    for (const list of ["items", "walls", "wall_items"]) {
      for (const it of this.save.garage[list] ?? []) total += this.catalog.item(it.item_id).price ?? 0;
    }
    for (const k of Object.keys(this.save.garage.floor_tiles ?? {})) {
      total += this.catalog.item(this.save.garage.floor_tiles[k]).price ?? 0;
    }
    return total;
  }

  garageValueTier(): number { return this.catalog.garageValueTier(this.garageValue()); }

  maxWorkers(): number { return this.catalog.levelInfo(this.player.level).max_workers; }

  busyWorkers(): number {
    return Object.keys(this.save.jobs).length + Object.keys(this.save.car_tasks).length + Object.keys(this.save.restoration.builds).length;
  }

  // --- Missions -------------------------------------------------------------------

  private emit(event: string, param: number, now: number, result: GameResult): void {
    this.missions.refreshDaily(this.save, now, this.dealerIds);
    const done = this.missions.record(this.save, event, param, now, this.dealerIds);
    for (const mid of done) this.completeMission(mid, now, result);
  }

  private completeMission(mid: number, now: number, result: GameResult): void {
    const m = this.catalog.missions.get(mid)!;
    this.missions.markDone(this.save, mid);
    this.addRewards(m.coins, m.blue, m.xp, result);
    const reward = this.giveReward(m.reward_type, m.reward_id);
    this.checkCollections(result);
    result.notices.push({
      kind: "mission_complete", mission_id: mid, title: m.title, text: m.complete_text,
      coins: m.coins, blue: m.blue, xp: m.xp, reward,
    });
    if (m.category === "daily") this.emit("COMPLETED_DAILY_MISSION", 0, now, result);
  }

  private giveReward(rewardType: string, rewardId: number): Dict {
    if (rewardId <= 0) return {};
    switch (rewardType.toLowerCase()) {
      case "item":
        if (Object.keys(this.catalog.item(rewardId)).length === 0) return {};
        this.storeItemId(rewardId);
        return { type: "item", id: rewardId };
      case "car": {
        if (Object.keys(this.catalog.car(rewardId)).length === 0) return {};
        const colors = this.catalog.colorsForCar(rewardId);
        this.addCar(rewardId, colors.length ? colors[0].id : 0);
        return { type: "car", id: rewardId };
      }
    }
    return {};
  }

  active_missions(now: number): number[] {
    this.missions.refreshDaily(this.save, now, this.dealerIds);
    return this.missions.activeIds(this.save, now, this.dealerIds);
  }

  // --- Dealer and cars ----------------------------------------------------------------

  dealer_car_ids(): number[] {
    const minPrice: number = this.catalog.tune("dealer.min_price", 100);
    const retired: boolean = this.catalog.tune("dealer.include_retired_cars", false);
    const needArt: boolean = this.catalog.tune("dealer.require_art", true);
    const limited: boolean = this.catalog.tune("dealer.include_retired_limited_cars", false);
    const result: number[] = [];
    for (const [id, c] of this.catalog.cars) {
      if (c.price < minPrice) continue;
      if (!limited && c.limited && Math.trunc(c.date_last_available ?? 0) > 0) continue;
      if (!(c.purchasable || c.always_purchasable || retired)) continue;
      if (needArt && this.catalog.artCarIds.size > 0 && !this.catalog.artCarIds.has(id)) continue;
      result.push(id);
    }
    result.sort((a, b) => {
      const ca = this.catalog.car(a), cb = this.catalog.car(b);
      return ca.price !== cb.price ? ca.price - cb.price : a - b;
    });
    return result;
  }

  private addCar(carId: number, colorId: number): Dict {
    const def = this.catalog.car(carId);
    const defaults: Dict = def.defaults ?? {};
    const parts: Dict = {};
    for (const k of Object.keys(defaults)) {
      const partId: number = defaults[k];
      if (partId > 0 && Object.keys(this.catalog.part(partId)).length > 0) {
        parts[key(this.catalog.part(partId).category_id)] = partId;
      }
    }
    const car: Dict = {
      uid: this.uid(), car_id: carId, color_id: colorId,
      paint: this.catalog.colorRgb(carId, colorId), parts,
      upgrades: [0, 0, 0, 0], ride_height: 0, plate: "",
      placed: false, x: 0, y: 0, rot: 0, bay_uid: 0,
    };
    const carSize = this.catalog.tune("garage.car_size", [4, 3]);
    const spot = GarageGrid.build(this.catalog, this.save).findFree({ x: carSize[0], y: carSize[1] });
    if (spot.x >= 0) {
      car.placed = true;
      car.x = spot.x;
      car.y = spot.y;
    }
    this.save.cars.push(car);
    return car;
  }

  buy_car(carId: number, colorId: number, useBlue: boolean, now: number): GameResult {
    const def = this.catalog.car(carId);
    if (Object.keys(def).length === 0 || !this.dealerIds.has(carId)) return GameResult.fail("That car isn't for sale.");
    let err = this.levelOk(def);
    if (err) return GameResult.fail(err);
    const colors = this.catalog.colorsForCar(carId);
    if (colors.length && !colors.some((c) => c.id === colorId)) colorId = colors[0].id;
    err = this.charge(def, useBlue);
    if (err) return GameResult.fail(err);
    const car = this.addCar(carId, colorId);
    const result = GameResult.success({ uid: car.uid, placed: car.placed });
    this.addRewards(0, 0, def.xp ?? 0, result);
    this.bumpStat("cars_bought");
    this.emit("BOUGHT_CAR_ID", carId, now, result);
    this.checkCollections(result);
    return result;
  }

  sell_car(uid: number, _now: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
    if (car.bay_uid !== 0 && key(car.bay_uid) in this.save.jobs) return GameResult.fail("Finish the job on this car first.");
    if (key(uid) in this.save.car_tasks) return GameResult.fail("This car is out on a job.");
    if (this.save.cars.length <= 1) return GameResult.fail("You can't sell your last car.");
    const fraction: number = this.catalog.tune("economy.resell_fraction", 0.1);
    const refund = Math.floor((this.catalog.car(car.car_id).price ?? 0) * fraction);
    this.save.cars.splice(this.save.cars.indexOf(car), 1);
    this.player.coins += refund;
    return GameResult.success({ coins: refund });
  }

  carPaint(car: Dict): number {
    return "paint" in car ? car.paint : this.catalog.colorRgb(car.car_id, car.color_id ?? 0);
  }

  paint_car(uid: number, rgb: number, useBlue: boolean, now: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
    if (rgb < 0 || rgb > 0xffffff) return GameResult.fail("That isn't a colour.");
    if (this.carPaint(car) === rgb) return GameResult.fail("The car is already that colour.");
    const err = this.charge(this.catalog.part(this.catalog.tune("parts.paint_part_id", 0)), useBlue);
    if (err) return GameResult.fail(err);
    car.paint = rgb;
    this.bumpStat("cars_painted");
    const result = GameResult.success();
    this.emit("PAINTED_CAR", 0, now, result);
    return result;
  }

  parts_for_car(carId: number, categoryId: number): number[] {
    const result: number[] = [];
    for (const [pid, p] of this.catalog.parts) {
      if (p.category_id !== categoryId) continue;
      if (p.car_id !== 0 && p.car_id !== carId) continue;
      if (p.car_id === 0 && !p.purchasable && !p.is_stock) continue;
      if (p.car_id !== 0 && !p.purchasable && pid !== this.catalog.stockPart(carId, categoryId)) continue;
      result.push(pid);
    }
    result.sort((a, b) => {
      const pa = this.catalog.part(a).price, pb = this.catalog.part(b).price;
      return pa !== pb ? pa - pb : a - b;
    });
    return result;
  }

  install_part(uid: number, partId: number, useBlue: boolean, now: number): GameResult {
    const car = this.get_car(uid);
    const p = this.catalog.part(partId);
    if (!car || Object.keys(p).length === 0) return GameResult.fail("Part not found.");
    const catKey = key(p.category_id);
    if ((car.parts[catKey] ?? 0) === partId) return GameResult.fail("That part is already installed.");
    if (!this.parts_for_car(car.car_id, p.category_id).includes(partId)) return GameResult.fail("That part doesn't fit this car.");
    const isStock = this.catalog.stockPart(car.car_id, p.category_id) === partId;
    const fromStorage = !isStock && this.storedParts(partId) > 0;
    const bought = !isStock && !fromStorage;
    if (bought) {
      let err = this.levelOk(p);
      if (err) return GameResult.fail(err);
      err = this.charge(p, useBlue);
      if (err) return GameResult.fail(err);
    }
    this.storePart(car, p.category_id);
    if (fromStorage) this.takeStoredPart(partId);
    car.parts[catKey] = partId;
    const result = GameResult.success({ from_storage: fromStorage });
    if (bought) {
      this.addRewards(0, 0, p.xp ?? 0, result);
      this.emit("INSTALLED_CAR_PART_CATEGORY", p.category_id, now, result);
    }
    return result;
  }

  storedParts(partId: number): number {
    return this.save.part_storage[key(partId)] ?? 0;
  }

  /** The part on the car in the category goes into storage, unless it's stock or the category isn't kept. */
  private storePart(car: Dict, categoryId: number): void {
    const old: number = car.parts[key(categoryId)] ?? 0;
    if (old === 0 || !STORED_PART_CATEGORIES.includes(categoryId) || old === this.catalog.stockPart(car.car_id, categoryId)) return;
    this.save.part_storage[key(old)] = this.storedParts(old) + 1;
  }

  private takeStoredPart(partId: number): void {
    const k = key(partId);
    this.save.part_storage[k] = this.storedParts(partId) - 1;
    if (this.save.part_storage[k] <= 0) delete this.save.part_storage[k];
  }

  remove_part(uid: number, categoryId: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
    this.storePart(car, categoryId);
    const stock = this.catalog.stockPart(car.car_id, categoryId);
    if (stock > 0) car.parts[key(categoryId)] = stock;
    else delete car.parts[key(categoryId)];
    return GameResult.success();
  }

  upgradeStagePrice(carId: number, stage: number): [number, number] {
    const base: number = this.catalog.car(carId).price ?? 0;
    const mult: number = this.catalog.consts[`upgrade_stage${stage}_multiplier`] ?? 0.1;
    const coins = Math.ceil(mult * base);
    if (stage < 5) return [Math.max(coins, Math.trunc(this.catalog.consts.upgrade_min_price ?? 25)), 0];
    return [0, Math.ceil(coins * Number(this.catalog.consts.upgrade_coins_to_blue_conversion ?? 0.001))];
  }

  upgrade_car(uid: number, track: number, now: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
    if (track < 1 || track > 4) return GameResult.fail("Unknown upgrade.");
    const stage: number = car.upgrades[track - 1] + 1;
    if (stage > Math.trunc(this.catalog.consts.upgrade_max_stage ?? 5)) return GameResult.fail("That upgrade is maxed out.");
    const price = this.upgradeStagePrice(car.car_id, stage);
    if (this.player.coins < price[0]) return GameResult.fail("Not enough coins.");
    if (this.player.blue < price[1]) return GameResult.fail("Not enough blue coins.");
    this.player.coins -= price[0];
    this.player.blue -= price[1];
    car.upgrades[track - 1] = stage;
    const result = GameResult.success({ track, stage });
    this.emit("INSTALLED_CAR_UPGRADE_TYPE", track, now, result);
    return result;
  }

  carScore(uid: number): number {
    const car = this.get_car(uid) ?? {};
    let score: number = this.catalog.car(car.car_id ?? 0).score ?? 0;
    for (const stage of car.upgrades ?? []) score += stage * Math.trunc(this.catalog.consts.upgrade_score_per_stage ?? 20);
    return score;
  }

  set_ride_height(uid: number, height: number, useBlue: boolean, _now: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
    if (height < 0 || height > this.catalog.tune("parts.max_ride_height", 4) || height === car.ride_height) {
      return GameResult.fail("Invalid ride height.");
    }
    const err = this.charge(this.catalog.part(this.catalog.tune("parts.ride_height_part_id", 0)), useBlue);
    if (err) return GameResult.fail(err);
    car.ride_height = height;
    return GameResult.success();
  }

  set_plate(uid: number, text: string, useBlue: boolean, _now: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
    const plate = text.trim().toUpperCase();
    const maxLen: number = this.catalog.tune("parts.plate_max_length", 7);
    if (plate === "" || plate.length > maxLen || !RE_PLATE.test(plate)) {
      return GameResult.fail(`Plates use up to ${maxLen} letters and numbers.`);
    }
    const err = this.charge(this.catalog.part(this.catalog.tune("parts.vanity_plate_part_id", 0)), useBlue);
    if (err) return GameResult.fail(err);
    car.plate = plate;
    return GameResult.success();
  }

  move_car(uid: number, x: number, y: number, rot: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
    if (car.bay_uid !== 0) return GameResult.fail("Take the car off the work bay first.");
    const carSize = this.catalog.tune("garage.car_size", [4, 3]);
    const size = rotatedSize(carSize[0], carSize[1], rot);
    if (!GarageGrid.build(this.catalog, this.save).canPlace(x, y, size, `car:${uid}`)) {
      return GameResult.fail("There's no room there.");
    }
    car.placed = true;
    car.x = x;
    car.y = y;
    car.rot = posmod(rot, 4);
    return GameResult.success();
  }

  store_car(uid: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
    if (car.bay_uid !== 0) return GameResult.fail("Take the car off the work bay first.");
    if (key(uid) in this.save.car_tasks) return GameResult.fail("This car is out on a job.");
    car.placed = false;
    return GameResult.success();
  }

  // --- Garage items -------------------------------------------------------------------

  private addItem(itemId: number, x: number, y: number, rot: number): Dict {
    const entry = { uid: this.uid(), item_id: itemId, x, y, rot: posmod(rot, 4) };
    this.save.garage.items.push(entry);
    return entry;
  }

  private storeItemId(itemId: number): void {
    const k = key(itemId);
    this.save.storage[k] = (this.save.storage[k] ?? 0) + 1;
  }

  private itemFits(itemId: number, x: number, y: number, rot: number, ignoreKey = ""): boolean {
    const def = this.catalog.item(itemId);
    const size = rotatedSize(def.size_x, def.size_y, rot);
    return GarageGrid.build(this.catalog, this.save).canPlace(x, y, size, ignoreKey);
  }

  buy_item(itemId: number, x: number, y: number, rot: number, useBlue: boolean, now: number): GameResult {
    const def = this.catalog.item(itemId);
    const kind = this.placementKind(def);
    if (kind === "") return GameResult.fail("That item can't be placed in the garage.");
    if (!(def.purchasable ?? false) && !(def.always_purchasable ?? false)) return GameResult.fail("That item isn't for sale.");
    let err = this.levelOk(def);
    if (err) return GameResult.fail(err);
    err = this.fitError(kind, itemId, x, y, rot);
    if (err) return GameResult.fail(err);
    err = this.charge(def, useBlue);
    if (err) return GameResult.fail(err);
    const entry = this.place(kind, itemId, x, y, rot);
    const result = GameResult.success({ uid: entry.uid ?? 0 });
    this.addRewards(0, 0, def.xp ?? 0, result);
    this.emit("BOUGHT_ITEM_ID", itemId, now, result);
    this.emit("BOUGHT_ITEM_CATEGORY", def.category, now, result);
    if (def.category !== CAT_WORK_BAY) this.emit("DECORATE_GARAGE", 0, now, result);
    return result;
  }

  move_item(uid: number, x: number, y: number, rot: number): GameResult {
    const entry = this.findItem(uid);
    if (!entry) {
      const found = this.findWallThing(uid);
      if (!found) return GameResult.fail("Item not found.");
      if (!this.wallFits(found.entry.item_id, x, y, rot, uid)) return GameResult.fail("There's no room there.");
      if (found.list === "walls") this.storePostersOn(uid);
      found.entry.x = x;
      found.entry.y = y;
      found.entry.rot = posmod(rot, 2);
      return GameResult.success();
    }
    if (this.bayBusy(uid)) return GameResult.fail("Clear the work bay before moving it.");
    if (!this.itemFits(entry.item_id, x, y, rot, `item:${uid}`)) return GameResult.fail("There's no room there.");
    entry.x = x;
    entry.y = y;
    entry.rot = posmod(rot, 4);
    return GameResult.success();
  }

  store_item(uid: number): GameResult {
    const entry = this.findItem(uid);
    if (!entry) {
      const found = this.takeWallThing(uid);
      if (!found) return GameResult.fail("Item not found.");
      this.storeItemId(found.item_id);
      return GameResult.success();
    }
    if (this.bayBusy(uid)) return GameResult.fail("Clear the work bay before storing it.");
    if (this.box(uid)) return GameResult.fail("Open the mystery box first.");
    this.save.garage.items.splice(this.save.garage.items.indexOf(entry), 1);
    this.storeItemId(entry.item_id);
    return GameResult.success();
  }

  clear_floor(cars: boolean, items: boolean, bays: boolean, walls: boolean, floors: boolean): GameResult {
    const stored = { cars: 0, items: 0, bays: 0, walls: 0, floors: 0 };
    if (walls) {
      for (const list of ["wall_items", "walls"]) {
        for (const entry of this.save.garage[list]) {
          this.storeItemId(entry.item_id);
          stored.walls += 1;
        }
        this.save.garage[list] = [];
      }
    }
    if (floors) {
      for (const k of Object.keys(this.save.garage.floor_tiles)) {
        if (this.keepsTile(this.save.garage.floor_tiles[k])) this.storeItemId(this.save.garage.floor_tiles[k]);
        stored.floors += 1;
      }
      this.save.garage.floor_tiles = {};
    }
    if (cars) {
      for (const car of this.save.cars) {
        if (!car.placed || key(car.uid) in this.save.car_tasks) continue;
        if (car.bay_uid !== 0) {
          if (key(car.bay_uid) in this.save.jobs) continue;
          car.bay_uid = 0;
        }
        car.placed = false;
        stored.cars += 1;
      }
    }
    for (const entry of [...this.save.garage.items]) {
      const isBay = this.isBay(entry.uid);
      if ((isBay && !bays) || (!isBay && !items)) continue;
      if (isBay && this.bayBusy(entry.uid)) continue;
      if (this.box(entry.uid)) continue;
      this.save.garage.items.splice(this.save.garage.items.indexOf(entry), 1);
      this.storeItemId(entry.item_id);
      if (isBay) stored.bays += 1;
      else stored.items += 1;
    }
    return GameResult.success(stored);
  }

  place_stored_item(itemId: number, x: number, y: number, rot: number): GameResult {
    const k = key(itemId);
    if ((this.save.storage[k] ?? 0) <= 0) return GameResult.fail("You don't have that item in storage.");
    const kind = this.placementKind(this.catalog.item(itemId));
    if (kind === "") return GameResult.fail("That item can't be placed in the garage.");
    const err = this.fitError(kind, itemId, x, y, rot);
    if (err) return GameResult.fail(err);
    this.save.storage[k] -= 1;
    if (this.save.storage[k] === 0) delete this.save.storage[k];
    const entry = this.place(kind, itemId, x, y, rot);
    return GameResult.success({ uid: entry.uid ?? 0 });
  }

  sell_item(uid: number): GameResult {
    const entry = this.findItem(uid);
    if (!entry) {
      const found = this.takeWallThing(uid);
      if (!found) return GameResult.fail("Item not found.");
      const wallRefund = Math.floor((this.catalog.item(found.item_id).price ?? 0) * Number(this.catalog.tune("economy.item_resell_fraction", 0.5)));
      this.player.coins += wallRefund;
      return GameResult.success({ coins: wallRefund });
    }
    if (this.bayBusy(uid)) return GameResult.fail("Clear the work bay before selling it.");
    if (this.box(uid)) return GameResult.fail("Open the mystery box first.");
    const fraction: number = this.catalog.tune("economy.item_resell_fraction", 0.5);
    const refund = Math.floor((this.catalog.item(entry.item_id).price ?? 0) * fraction);
    this.save.garage.items.splice(this.save.garage.items.indexOf(entry), 1);
    this.player.coins += refund;
    return GameResult.success({ coins: refund });
  }

  sell_stored_item(itemId: number): GameResult {
    const k = key(itemId);
    if ((this.save.storage[k] ?? 0) <= 0) return GameResult.fail("You don't have that item in storage.");
    this.save.storage[k] -= 1;
    if (this.save.storage[k] === 0) delete this.save.storage[k];
    const fraction: number = this.catalog.tune("economy.item_resell_fraction", 0.5);
    const refund = Math.floor((this.catalog.item(itemId).price ?? 0) * fraction);
    this.player.coins += refund;
    return GameResult.success({ coins: refund });
  }

  // --- Walls, posters and floor tiles -------------------------------------------------

  private placementKind(def: Dict): string {
    if (Object.keys(def).length === 0) return "";
    if (isFloorObject(def)) return "floor";
    if (isWall(def)) return "wall";
    if (isWallObject(def)) return "poster";
    if ((def.category ?? 0) === CAT_FLOOR_TILE) return "tile";
    return "";
  }

  private fitError(kind: string, itemId: number, x: number, y: number, rot: number): string {
    switch (kind) {
      case "floor":
        return this.itemFits(itemId, x, y, rot) ? "" : "There's no room there.";
      case "wall":
        return this.wallFits(itemId, x, y, rot) ? "" : "A wall can't go there.";
      case "poster":
        return this.wallFits(itemId, x, y, rot) ? "" : "That needs an empty wall to hang on.";
      case "tile": {
        const land = this.catalog.land(this.save.garage.land_id);
        if (x < 0 || y < 0 || x >= land.size_x || y >= land.size_y) return "That's outside your garage.";
        if (this.floorTile(x, y) === itemId) return "That tile already has that floor.";
        return "";
      }
    }
    return "That item can't be placed in the garage.";
  }

  private wallFits(itemId: number, x: number, y: number, rot: number, ignoreUid = 0): boolean {
    const def = this.catalog.item(itemId);
    const grid = GarageGrid.build(this.catalog, this.save);
    const horizontal = posmod(rot, 2) === HORIZONTAL;
    if (isWall(def)) return grid.canPlaceWall(x, y, wallLength(def), horizontal, ignoreUid);
    return grid.canPlacePoster(x, y, wallObjectLength(def), horizontal, ignoreUid);
  }

  private place(kind: string, itemId: number, x: number, y: number, rot: number): Dict {
    switch (kind) {
      case "floor":
        return this.addItem(itemId, x, y, rot);
      case "wall":
      case "poster": {
        const entry = { uid: this.uid(), item_id: itemId, x, y, rot: posmod(rot, 2) };
        this.save.garage[kind === "wall" ? "walls" : "wall_items"].push(entry);
        return entry;
      }
      case "tile": {
        const k = `${x},${y}`;
        const old: number = this.save.garage.floor_tiles[k] ?? 0;
        if (old !== 0 && this.keepsTile(old)) this.storeItemId(old);
        if (itemId === this.save.garage.floor_item_id) delete this.save.garage.floor_tiles[k];
        else this.save.garage.floor_tiles[k] = itemId;
        return { x, y };
      }
    }
    return {};
  }

  floorTile(x: number, y: number): number {
    return this.save.garage.floor_tiles[`${x},${y}`] ?? this.save.garage.floor_item_id;
  }

  private keepsTile(itemId: number): boolean {
    const def = this.catalog.item(itemId);
    return (def.price ?? 0) > 0 || (def.blue_price ?? 0) > 0;
  }

  private findWallThing(uid: number): { list: string; entry: Dict } | undefined {
    for (const list of ["walls", "wall_items"]) {
      for (const entry of this.save.garage[list]) if (entry.uid === uid) return { list, entry };
    }
    return undefined;
  }

  private takeWallThing(uid: number): Dict | undefined {
    const found = this.findWallThing(uid);
    if (!found) return undefined;
    if (found.list === "walls") this.storePostersOn(uid);
    const list: Dict[] = this.save.garage[found.list];
    list.splice(list.indexOf(found.entry), 1);
    return found.entry;
  }

  private storePostersOn(wallUid: number): void {
    const grid = GarageGrid.build(this.catalog, this.save);
    for (const posterUid of grid.postersOnWall(wallUid)) {
      const found = this.findWallThing(posterUid);
      if (found) {
        const list: Dict[] = this.save.garage.wall_items;
        list.splice(list.indexOf(found.entry), 1);
        this.storeItemId(found.entry.item_id);
      }
    }
  }

  /** Old saves' single back-wall style ("wall_item_id") becomes real walls. */
  private upgradeLegacyWalls(): void {
    const g: Dict | undefined = this.save.garage;
    if (!g || !("wall_item_id" in g)) return;
    const wallId: number = g.wall_item_id;
    delete g.wall_item_id;
    g.walls ??= [];
    g.floor_tiles ??= {};
    const def = this.catalog.item(wallId);
    if (wallId === 0 || !isWall(def)) return;
    const land = this.catalog.land(g.land_id);
    const step = wallLength(def);
    for (let v = 0; v < (land.size_y ?? 10); v += step) g.walls.push({ uid: this.uid(), item_id: wallId, x: 0, y: v, rot: VERTICAL });
    for (let h = 0; h < (land.size_x ?? 10); h += step) g.walls.push({ uid: this.uid(), item_id: wallId, x: h, y: 0, rot: HORIZONTAL });
  }

  nextLandId(): number {
    const next: number = this.save.garage.land_id + 1;
    if (next > this.catalog.tune("garage.max_land_id", 7) || Object.keys(this.catalog.land(next)).length === 0) return 0;
    return next;
  }

  expand_land(useBlue: boolean, now: number): GameResult {
    const next = this.nextLandId();
    if (next === 0) return GameResult.fail("Your garage is as big as it gets.");
    const def: Dict = { ...this.catalog.land(next) };
    def.can_buy_with_coins = def.price > 0;
    def.can_buy_with_blue = def.blue_price > 0;
    let err = this.levelOk(def);
    if (err) return GameResult.fail(err);
    err = this.charge(def, useBlue);
    if (err) return GameResult.fail(err);
    this.save.garage.land_id = next;
    const result = GameResult.success({ land_id: next });
    this.emit("LAND_EXPANDED", next, now, result);
    return result;
  }

  // --- Work bays and jobs -------------------------------------------------------------------

  private isBay(uid: number): boolean {
    const entry = this.findItem(uid);
    return entry !== undefined && (this.catalog.item(entry.item_id).category ?? 0) === CAT_WORK_BAY;
  }

  bayOccupant(bayUid: number): Dict {
    for (const c of this.save.cars) if (c.bay_uid === bayUid) return { kind: "car", entry: c };
    for (const c of this.save.customers) if ((c.bay_uid ?? 0) === bayUid) return { kind: "customer", entry: c };
    if (key(bayUid) in this.save.restoration.builds) return { kind: "build", entry: this.save.restoration.builds[key(bayUid)] };
    return {};
  }

  private bayBusy(uid: number): boolean {
    return Object.keys(this.bayOccupant(uid)).length > 0 || key(uid) in this.save.jobs;
  }

  put_car_on_bay(carUid: number, bayUid: number): GameResult {
    const car = this.get_car(carUid);
    if (!car) return GameResult.fail("Car not found.");
    if (!this.isBay(bayUid)) return GameResult.fail("That isn't a work bay.");
    if (Object.keys(this.bayOccupant(bayUid)).length > 0) return GameResult.fail("That work bay is taken.");
    if (car.bay_uid !== 0) return GameResult.fail("That car is already on a work bay.");
    if (key(carUid) in this.save.car_tasks) return GameResult.fail("This car is out on a job.");
    car.bay_uid = bayUid;
    car.placed = true;
    return GameResult.success();
  }

  take_car_off_bay(carUid: number): GameResult {
    const car = this.get_car(carUid);
    if (!car || car.bay_uid === 0) return GameResult.fail("That car isn't on a work bay.");
    if (key(car.bay_uid) in this.save.jobs) return GameResult.fail("Finish the job first.");
    car.bay_uid = 0;
    const carSize = this.catalog.tune("garage.car_size", [4, 3]);
    const spot = GarageGrid.build(this.catalog, this.save).findFree({ x: carSize[0], y: carSize[1] });
    if (spot.x >= 0) {
      car.x = spot.x;
      car.y = spot.y;
      car.rot = 0;
    } else {
      car.placed = false;
    }
    return GameResult.success({ placed: car.placed });
  }

  available_job_ids(): number[] {
    const result: number[] = [];
    for (const [id, j] of this.catalog.jobs) {
      if (j.type !== 2 || j.is_car_build || j.specific_car_id !== 0) continue;
      if (j.coins <= 0 && j.xp <= 0) continue;
      result.push(id);
    }
    result.sort((a, b) => {
      const ja = this.catalog.job(a), jb = this.catalog.job(b);
      return ja.min_level !== jb.min_level ? ja.min_level - jb.min_level : ja.minutes - jb.minutes;
    });
    return result;
  }

  /** A job started on an empty lift gets a random factory car to work on
   * (WorkBayFloorObj.createRandomCar), drawn from the customers' pool. */
  private addJobCar(jobState: Dict): void {
    const pool = this.customerPool();
    if (pool.length === 0) return;
    const pick = SimpleRng.rangeInt(this.save.rng, 0, pool.length - 1);
    this.save.rng = pick[0];
    const carId = pool[pick[1]];
    const colors = this.catalog.colorsForCar(carId);
    const colorPick = SimpleRng.rangeInt(this.save.rng, 0, Math.max(0, colors.length - 1));
    this.save.rng = colorPick[0];
    jobState.car_id = carId;
    jobState.color_id = colors.length > 0 ? colors[colorPick[1]].id : 0;
  }

  start_job(bayUid: number, jobId: number, now: number): GameResult {
    if (!this.isBay(bayUid)) return GameResult.fail("That isn't a work bay.");
    if (key(bayUid) in this.save.jobs) return GameResult.fail("That work bay is already busy.");
    const def = this.catalog.job(jobId);
    if (Object.keys(def).length === 0 || !this.available_job_ids().includes(jobId)) return GameResult.fail("Unknown job.");
    const occ = this.bayOccupant(bayUid);
    if (occ.kind === "build") return GameResult.fail("A car is being restored on that work bay.");
    if (occ.kind === "customer" && ![0, jobId].includes(occ.entry.job_id ?? 0)) {
      return GameResult.fail(`This customer wants a ${this.catalog.job(occ.entry.job_id).name ?? "different job"}.`);
    }
    if (this.player.level < def.min_level) return GameResult.fail(`Requires level ${def.min_level}.`);
    if (this.busyWorkers() >= this.maxWorkers()) {
      return GameResult.fail("All your workers are busy. Level up to hire more.");
    }
    const cost = Math.ceil(def.price * Number(this.catalog.tune("jobs.start_cost_multiplier", 1.0)));
    if (this.player.coins < cost) return GameResult.fail("Not enough coins.");
    this.player.coins -= cost;
    const jobState: Dict = { job_id: jobId, started_at: now, ends_at: now + def.minutes * 60 };
    if (Object.keys(occ).length === 0) this.addJobCar(jobState);
    this.save.jobs[key(bayUid)] = jobState;
    this.bumpStat("jobs_started");
    const result = GameResult.success({ ends_at: now + def.minutes * 60 });
    this.emit("STARTED_WORKBAY_TASK_ID", jobId, now, result);
    return result;
  }

  masteryLevel(jobId: number): number {
    const count: number = this.save.job_mastery[key(jobId)] ?? 0;
    const thresholds: number[] = this.catalog.job(jobId).mastery_thresholds ?? [0];
    let level = 1;
    for (let i = 1; i < thresholds.length; i++) {
      if (thresholds[i] > 0 && count >= thresholds[i]) level = i + 1;
    }
    return level;
  }

  jobPayout(jobId: number): { coins: number; xp: number } {
    const def = this.catalog.job(jobId);
    const level = this.masteryLevel(jobId);
    const xpList: number[] = def.mastery_xp ?? [def.xp ?? 0];
    let xp = xpList[Math.min(level - 1, xpList.length - 1)];
    if (xp <= 0) xp = def.xp ?? 0;
    return {
      coins: roundi((def.coins ?? 0) * Number(this.catalog.tune("jobs.coin_multiplier", 1.0))),
      xp: roundi(xp * Number(this.catalog.tune("jobs.xp_multiplier", 1.0))),
    };
  }

  collect_job(bayUid: number, now: number): GameResult {
    const k = key(bayUid);
    if (!(k in this.save.jobs)) return GameResult.fail("There's no job on that work bay.");
    const jobState = this.save.jobs[k];
    if (now < jobState.ends_at) return GameResult.fail("The job isn't finished yet.");
    const jobId: number = jobState.job_id;
    delete this.save.jobs[k];
    const result = this.payJob(jobId);
    const occ = this.bayOccupant(bayUid);
    if (occ.kind === "customer") this.save.customers.splice(this.save.customers.indexOf(occ.entry), 1);
    this.bumpStat("jobs_collected");
    this.emit("COLLECTED_WORKBAY_TASK_ID", jobId, now, result);
    return result;
  }

  payJob(jobId: number): GameResult {
    const pay = this.jobPayout(jobId);
    const before = this.masteryLevel(jobId);
    this.save.job_mastery[key(jobId)] = (this.save.job_mastery[key(jobId)] ?? 0) + 1;
    const result = GameResult.success(pay);
    this.addRewards(pay.coins, 0, pay.xp, result);
    const after = this.masteryLevel(jobId);
    if (after > before) {
      let bonus: Dict = {};
      for (const tm of this.catalog.taskMasteryLevels) if (tm.level === after) bonus = tm;
      this.addRewards(bonus.coin_bonus ?? 0, bonus.blue_bonus ?? 0, bonus.xp_bonus ?? 0, result);
      // Mastering a job for good earns its plaque (ri5), into storage.
      let plaque: number = this.catalog.job(jobId).mastery_reward_item_id ?? 0;
      if (after === (this.catalog.job(jobId).mastery_thresholds ?? []).length && Object.keys(this.catalog.item(plaque)).length > 0) {
        this.save.storage[key(plaque)] = (this.save.storage[key(plaque)] ?? 0) + 1;
      } else {
        plaque = 0;
      }
      result.notices.push({ kind: "mastery", job_id: jobId, level: after, coins: bonus.coin_bonus ?? 0, blue: bonus.blue_bonus ?? 0, item_id: plaque });
    }
    return result;
  }

  stop_job(bayUid: number): GameResult {
    const k = key(bayUid);
    if (!(k in this.save.jobs)) return GameResult.fail("There's no job on that work bay.");
    delete this.save.jobs[k];
    const occ = this.bayOccupant(bayUid);
    if (occ.kind === "customer") this.save.customers.splice(this.save.customers.indexOf(occ.entry), 1);
    return GameResult.success();
  }

  finishNowPrice(bayUid: number, now: number): number {
    const jobState = this.save.jobs[key(bayUid)];
    return jobState ? this.finishPrice(jobState.ends_at - now) : 0;
  }

  finishPrice(remaining: number): number {
    const perHour = Number(this.catalog.tune("jobs.finish_now_blue_per_hour", 1));
    const minBlue: number = this.catalog.tune("jobs.finish_now_min_blue", 1);
    return Math.max(minBlue, Math.ceil(Math.max(0, remaining) / 3600.0 * perHour));
  }

  finish_job_now(bayUid: number, now: number): GameResult {
    const jobState = this.save.jobs[key(bayUid)];
    if (!jobState) return GameResult.fail("There's no job on that work bay.");
    if (now >= jobState.ends_at) return this.collect_job(bayUid, now);
    const price = this.finishNowPrice(bayUid, now);
    if (this.player.blue < price) return GameResult.fail("Not enough blue coins.");
    this.player.blue -= price;
    jobState.ends_at = now;
    return this.collect_job(bayUid, now);
  }

  // --- Car tasks ------------------------------------------------------------------------

  car_task_ids(carUid: number): number[] {
    const car = this.get_car(carUid);
    const result: number[] = [];
    if (!car) return result;
    const category: number = this.catalog.car(car.car_id).category ?? 0;
    for (const raw of this.catalog.tune("car_tasks.enabled", []) as number[]) {
      const id = Math.trunc(raw);
      const def = this.catalog.job(id);
      if (Object.keys(def).length === 0 || def.type !== 1) continue;
      const cats: number[] = def.car_categories ?? [];
      if (cats.includes(0) || cats.includes(category) || (def.car_ids ?? []).includes(car.car_id)) result.push(id);
    }
    return result;
  }

  start_car_task(carUid: number, jobId: number, now: number): GameResult {
    const car = this.get_car(carUid);
    if (!car) return GameResult.fail("Car not found.");
    if (!car.placed) return GameResult.fail("Put the car in your garage first.");
    if (car.bay_uid !== 0) return GameResult.fail("Take the car off the work bay first.");
    if (key(carUid) in this.save.car_tasks) return GameResult.fail("This car is already out on a job.");
    if (!this.car_task_ids(carUid).includes(jobId)) return GameResult.fail("This car can't do that job.");
    if (jobId === ROAD_TRIP_JOB) return GameResult.fail("Pick where the road trip goes.");
    const def = this.catalog.job(jobId);
    if (this.player.level < def.min_level) return GameResult.fail(`Requires level ${def.min_level}.`);
    if (this.busyWorkers() >= this.maxWorkers()) {
      return GameResult.fail("All your workers are busy. Level up to hire more.");
    }
    const cost = Math.ceil(def.price * Number(this.catalog.tune("jobs.start_cost_multiplier", 1.0)));
    if (this.player.coins < cost) return GameResult.fail("Not enough coins.");
    this.player.coins -= cost;
    const endsAt = now + def.minutes * 60;
    this.save.car_tasks[key(carUid)] = { job_id: jobId, started_at: now, ends_at: endsAt };
    this.bumpStat("jobs_started");
    const result = GameResult.success({ ends_at: endsAt });
    this.emit("STARTED_WORKBAY_TASK_ID", jobId, now, result);
    return result;
  }

  // --- Avatar -----------------------------------------------------------------------------

  avatar_item_owned(itemId: number): boolean {
    const it = this.catalog.avatarItems.get(itemId);
    if (!it) return false;
    if (Math.trunc(it.price ?? 0) === 0 && Math.trunc(it.blue_price ?? 0) === 0) return true;
    return this.save.avatar_owned.includes(itemId);
  }

  buy_avatar_item(itemId: number, useBlue: boolean, now: number): GameResult {
    const it = this.catalog.avatarItems.get(itemId);
    if (!it || !(it.purchasable || it.always_purchasable)) return GameResult.fail("That isn't for sale.");
    if (this.avatar_item_owned(itemId)) return GameResult.fail("You already have that.");
    let err = this.levelOk(it);
    if (err) return GameResult.fail(err);
    err = this.charge(it, useBlue);
    if (err) return GameResult.fail(err);
    this.save.avatar_owned.push(itemId);
    const result = GameResult.success({ item_id: itemId });
    this.addRewards(0, 0, Math.trunc(it.xp ?? 0), result);
    return result;
  }

  set_avatar_part(slot: number, itemId: number, setting: number): GameResult {
    const key = AVATAR_SLOTS[slot];
    if (key === undefined) return GameResult.fail("Unknown avatar part.");
    if (itemId === 0) {
      if (!AVATAR_OPTIONAL.includes(slot)) return GameResult.fail("That can't be left off.");
    } else {
      const it = this.catalog.avatarItems.get(itemId);
      const t = Math.trunc(it?.type ?? 0);
      if (!it || (t !== slot && !(key === "bottom" && [9, 12].includes(t)))) return GameResult.fail("That doesn't go there.");
      if (!this.avatar_item_owned(itemId)) return GameResult.fail("Buy it first.");
    }
    if (setting < 0 || setting > 99999) return GameResult.fail("Bad setting.");
    const colors = AVATAR_COLORS[slot] ?? 10;
    if (Math.trunc(setting / 10000) % 10 >= colors) return GameResult.fail("Bad colour.");
    const a = this.save.avatar;
    a[key] = itemId;
    if (key in a.settings || setting !== 0) a.settings[key] = setting;
    return GameResult.success();
  }

  // --- Car restoration --------------------------------------------------------------------

  private get resto(): Dict {
    return this.save.restoration;
  }

  restorations_done(): number {
    return this.resto.restored.length;
  }

  is_master_mechanic(): boolean {
    return this.restorations_done() >= Math.trunc(this.catalog.consts.restorations_to_master_mechanic ?? 10);
  }

  restoration_build_ids(): number[] {
    const out: number[] = [];
    const master = this.is_master_mechanic();
    for (const [id, b] of this.catalog.carBuilds) {
      const task: number = b.task_id;
      if (task !== BUILD_RESTORATION && !(task === BUILD_MASTER_MECHANIC && master)) continue;
      if (Object.keys(this.catalog.car(Math.trunc(b.car_id))).length === 0 || Object.keys(this.catalog.car(Math.trunc(b.primer_car_id))).length === 0) continue;
      if (this.catalog.artCarIds.size > 0 && !(this.catalog.artCarIds.has(Math.trunc(b.car_id)) && this.catalog.artCarIds.has(Math.trunc(b.primer_car_id)))) continue;
      out.push(id);
    }
    out.sort((a, b) => {
      const la: number = this.catalog.car(Math.trunc(this.catalog.carBuilds.get(a)!.car_id)).min_level ?? 0;
      const lb: number = this.catalog.car(Math.trunc(this.catalog.carBuilds.get(b)!.car_id)).min_level ?? 0;
      return la !== lb ? la - lb : a - b;
    });
    return out;
  }

  junkyard_build_ids(): number[] {
    const fresh: number[] = [];
    const done: number[] = [];
    for (const id of this.restoration_build_ids()) {
      if (this.catalog.carBuilds.get(id)!.task_id !== BUILD_RESTORATION) continue;
      if (this.resto.restored.includes(id)) done.push(id);
      else fresh.push(id);
    }
    return [...fresh, ...done].slice(0, Math.trunc(this.catalog.tune("restoration.junkyard_cars", 4)));
  }

  bay_build(bayUid: number): Dict {
    return this.resto.builds[key(bayUid)] ?? {};
  }

  build_parts_needed(bayUid: number): Dict {
    const build = this.bay_build(bayUid);
    const out: Dict = {};
    if (Object.keys(build).length === 0) return out;
    for (const p of this.catalog.carBuilds.get(Math.trunc(build.build_id))!.parts) {
      const have = Math.trunc(build.parts[key(p.part_id)] ?? 0);
      if (have < Math.trunc(p.quantity)) out[p.part_id] = Math.trunc(p.quantity) - have;
    }
    return out;
  }

  private partsWanted(): number[] {
    const want = new Map<number, number>();
    for (const k of Object.keys(this.resto.builds)) {
      const needed = this.build_parts_needed(Number(k));
      for (const pid of Object.keys(needed)) want.set(Number(pid), (want.get(Number(pid)) ?? 0) + needed[pid]);
    }
    const out: number[] = [];
    for (const [pid, n] of want) if (n > Math.trunc(this.resto.inventory[key(pid)] ?? 0)) out.push(pid);
    out.sort((a, b) => a - b);
    return out;
  }

  restoration_currency(): string {
    return this.catalog.tune("restoration.currency", "coins") === "blue" ? "blue" : "coins";
  }

  build_part_price(partId: number): number {
    const blue = Math.trunc(this.catalog.carBuildParts.get(partId)?.blue_price ?? 0);
    if (this.restoration_currency() === "blue") return blue;
    return blue * Math.trunc(this.catalog.tune("restoration.coins_per_blue", 2500));
  }

  private givePart(partId: number, count = 1): void {
    this.resto.inventory[key(partId)] = Math.trunc(this.resto.inventory[key(partId)] ?? 0) + count;
  }

  start_restoration(buildId: number, bayUid: number, now: number): GameResult {
    if (!this.restoration_build_ids().includes(buildId)) return GameResult.fail("That car can't be restored.");
    if (!this.isBay(bayUid)) return GameResult.fail("That isn't a work bay.");
    if (this.bayBusy(bayUid)) return GameResult.fail("That work bay is busy.");
    const b = this.catalog.carBuilds.get(buildId)!;
    const lvl: number = this.catalog.car(Math.trunc(b.car_id)).min_level ?? 0;
    if (this.player.level < lvl) return GameResult.fail(`Requires level ${lvl}.`);
    if (this.busyWorkers() >= this.maxWorkers()) return GameResult.fail("All your workers are busy. Level up to hire more.");
    this.resto.builds[key(bayUid)] = { build_id: buildId, started_at: now, parts: {} };
    if (Math.trunc(this.resto.next_gift_at) < 0) this.resto.next_gift_at = now + Math.trunc(this.catalog.tune("restoration.gift_minutes", 240)) * 60;
    const result = GameResult.success();
    this.emit("STARTED_WORKBAY_TASK_ID", Math.trunc(b.task_id), now, result);
    return result;
  }

  collect_junkyard_part(now: number): GameResult {
    const last = Math.trunc(this.resto.last_pile_at);
    const wait = Math.trunc(this.catalog.tune("restoration.pile_hours", 24)) * 3600;
    if (last >= 0 && now - last < wait) return GameResult.fail("You've already found today's part. Come back tomorrow!");
    let choices = this.partsWanted();
    if (choices.length === 0) {
      for (const id of this.restoration_build_ids()) {
        for (const p of this.catalog.carBuilds.get(id)!.parts) if (!choices.includes(Math.trunc(p.part_id))) choices.push(Math.trunc(p.part_id));
      }
      choices.sort((a, b) => a - b);
    }
    if (choices.length === 0) return GameResult.fail("There's nothing in the piles today.");
    const partId = choices[this.rng(0, choices.length - 1)];
    this.givePart(partId);
    this.resto.last_pile_at = now;
    return GameResult.success({ part_id: partId });
  }

  buy_build_part(partId: number, now: number): GameResult {
    if (!this.catalog.carBuildParts.has(partId)) return GameResult.fail("Unknown part.");
    const cost = this.build_part_price(partId);
    const k = this.restoration_currency();
    if (cost <= 0 || this.player[k] < cost) return GameResult.fail(k === "blue" ? "Not enough Blue Coins." : "Not enough coins.");
    this.player[k] -= cost;
    this.givePart(partId);
    return GameResult.success({ part_id: partId, cost });
  }

  install_build_part(bayUid: number, partId: number): GameResult {
    if (Object.keys(this.bay_build(bayUid)).length === 0) return GameResult.fail("There's no restoration on that work bay.");
    if (!(partId in this.build_parts_needed(bayUid))) return GameResult.fail("This car doesn't need that part.");
    const have = Math.trunc(this.resto.inventory[key(partId)] ?? 0);
    if (have <= 0) return GameResult.fail("You don't have that part.");
    if (have === 1) delete this.resto.inventory[key(partId)];
    else this.resto.inventory[key(partId)] = have - 1;
    const parts = this.bay_build(bayUid).parts;
    parts[key(partId)] = Math.trunc(parts[key(partId)] ?? 0) + 1;
    return GameResult.success({ done: Object.keys(this.build_parts_needed(bayUid)).length === 0 });
  }

  finish_restoration(bayUid: number, now: number): GameResult {
    const build = this.bay_build(bayUid);
    if (Object.keys(build).length === 0) return GameResult.fail("There's no restoration on that work bay.");
    if (Object.keys(this.build_parts_needed(bayUid)).length > 0) return GameResult.fail("It still needs parts.");
    const buildId: number = build.build_id;
    const b = this.catalog.carBuilds.get(buildId)!;
    delete this.resto.builds[key(bayUid)];
    if (Object.keys(this.resto.builds).length === 0) this.resto.next_gift_at = -1;
    const wasMaster = this.is_master_mechanic();
    if (!this.resto.restored.includes(buildId)) this.resto.restored.push(buildId);
    this.resto.count = Math.trunc(this.resto.count) + 1;
    const carId: number = b.car_id;
    const colors = this.catalog.colorsForCar(carId);
    const car = this.addCar(carId, colors.length ? colors[0].id : 0);
    const result = GameResult.success({ car_id: carId, uid: car.uid, build_id: buildId });
    this.bumpStat("restorations");
    this.emit("COLLECTED_WORKBAY_TASK_ID", Math.trunc(b.task_id), now, result);
    this.emit("COMPLETED_CAR_BUILD_ID", buildId, now, result);
    this.emit("COMPLETED_CAR_RESTORATION_CAR_ID", carId, now, result);
    if (!wasMaster && this.is_master_mechanic()) result.notices.push({ kind: "master_mechanic" });
    this.checkCollections(result);
    return result;
  }

  abandon_restoration(bayUid: number): GameResult {
    const build = this.bay_build(bayUid);
    if (Object.keys(build).length === 0) return GameResult.fail("There's no restoration on that work bay.");
    for (const k of Object.keys(build.parts)) this.givePart(Number(k), Math.trunc(build.parts[k]));
    delete this.resto.builds[key(bayUid)];
    if (Object.keys(this.resto.builds).length === 0) this.resto.next_gift_at = -1;
    return GameResult.success();
  }

  private restorationGifts(now: number, result: GameResult): void {
    const r = this.resto;
    if (Object.keys(r.builds).length === 0 || Math.trunc(r.next_gift_at) < 0) return;
    const every = Math.max(60, Math.trunc(this.catalog.tune("restoration.gift_minutes", 240)) * 60);
    const names: string[] = this.catalog.tune("restoration.helper_names", ["A neighbor"]);
    let given = 0;
    while (Math.trunc(r.next_gift_at) <= now && given < 24) {
      const wanted = this.partsWanted();
      if (wanted.length === 0) {
        r.next_gift_at = now + every;
        return;
      }
      const partId = wanted[this.rng(0, wanted.length - 1)];
      this.givePart(partId);
      result.notices.push({ kind: "part_gift", part_id: partId, name: String(names[this.rng(0, names.length - 1)]) });
      r.next_gift_at = Math.trunc(r.next_gift_at) + every;
      given += 1;
    }
    if (Math.trunc(r.next_gift_at) <= now) r.next_gift_at = now + every;
  }

  // --- Mystery boxes ----------------------------------------------------------------------

  mystery_box_levels(): number[] {
    const out: number[] = [];
    for (const [level, b] of this.catalog.mysteryBoxes) {
      if (b.available && Object.keys(this.catalog.item(Math.trunc(b.item_id))).length > 0 && this.mystery_pool(level).length > 0) out.push(level);
    }
    out.sort((a, b) => {
      const pa = this.mystery_box_price(a), pb = this.mystery_box_price(b);
      return pa !== pb ? pa - pb : a - b;
    });
    return out;
  }

  mystery_pool(level: number): number[] {
    const excluded: number[] = this.catalog.consts.mystery_excluded_cars ?? [];
    const out: number[] = [];
    for (const id of this.catalog.mysteryBoxes.get(level)?.car_ids ?? []) {
      const carId = Math.trunc(id);
      if (out.includes(carId) || excluded.includes(carId) || Object.keys(this.catalog.car(carId)).length === 0) continue;
      if (this.catalog.artCarIds.size > 0 && !this.catalog.artCarIds.has(carId)) continue;
      out.push(carId);
    }
    out.sort((a, b) => a - b);
    return out;
  }

  mystery_box_currency(): string {
    return this.catalog.tune("mystery_boxes.currency", "coins") === "blue" ? "blue" : "coins";
  }

  mystery_box_price(level: number): number {
    const b: Dict = this.catalog.mysteryBoxes.get(level) ?? {};
    if (this.mystery_box_currency() === "blue") return Math.trunc(b.blue_price ?? 0);
    return Math.trunc(this.catalog.item(Math.trunc(b.item_id ?? 0)).price ?? 0);
  }

  mystery_box_respin_price(level: number): number {
    const b: Dict = this.catalog.mysteryBoxes.get(level) ?? {};
    const respin = Math.trunc(b.respin_blue ?? 0);
    if (this.mystery_box_currency() === "blue") return respin;
    const blue = Math.max(1, Math.trunc(b.blue_price ?? 1));
    return Math.trunc((this.mystery_box_price(level) * respin + blue - 1) / blue);
  }

  private boxPay(cost: number): string {
    const k = this.mystery_box_currency();
    if (this.player[k] < cost) return k === "blue" ? "Not enough Blue Coins." : "Not enough coins.";
    this.player[k] -= cost;
    return "";
  }

  private boxPick(level: number, notThis: number): number {
    const pool = this.mystery_pool(level);
    if (pool.length > 1) {
      const at = pool.indexOf(notThis);
      if (at >= 0) pool.splice(at, 1);
    }
    return pool[this.rng(0, pool.length - 1)];
  }

  buy_mystery_box(level: number, x: number, y: number, rot: number, now: number): GameResult {
    if (!this.mystery_box_levels().includes(level)) return GameResult.fail("That mystery box isn't for sale.");
    const itemId: number = this.catalog.mysteryBoxes.get(level)!.item_id;
    let err = this.fitError("floor", itemId, x, y, rot);
    if (err) return GameResult.fail(err);
    err = this.boxPay(this.mystery_box_price(level));
    if (err) return GameResult.fail(err);
    const entry = this.place("floor", itemId, x, y, rot);
    const carId = this.boxPick(level, 0);
    this.save.mystery_boxes[key(entry.uid)] = { level, car_id: carId, spin: BOX_NEW };
    this.bumpStat("mystery_boxes");
    return GameResult.success({ uid: entry.uid, car_id: carId });
  }

  private box(uid: number): Dict | undefined {
    return this.save.mystery_boxes[key(uid)];
  }

  mystery_box_spun(uid: number): GameResult {
    const box = this.box(uid);
    if (!box) return GameResult.fail("That's not a mystery box.");
    if (box.spin === BOX_NEW || box.spin === BOX_RESPUN) box.spin = Math.trunc(box.spin) + 1;
    return GameResult.success({ car_id: box.car_id, spin: box.spin });
  }

  mystery_box_respin(uid: number, now: number): GameResult {
    const box = this.box(uid);
    if (!box) return GameResult.fail("That's not a mystery box.");
    if (box.spin !== BOX_SPUN) return GameResult.fail("This box can't be spun again.");
    const err = this.boxPay(this.mystery_box_respin_price(Math.trunc(box.level)));
    if (err) return GameResult.fail(err);
    box.car_id = this.boxPick(Math.trunc(box.level), Math.trunc(box.car_id));
    box.spin = BOX_RESPUN;
    return GameResult.success({ car_id: box.car_id });
  }

  mystery_box_claim(uid: number, now: number): GameResult {
    const box = this.box(uid);
    if (!box) return GameResult.fail("That's not a mystery box.");
    if (box.spin !== BOX_SPUN && box.spin !== BOX_SPUN_AGAIN) return GameResult.fail("Spin the wheel first.");
    const entry = this.findItem(uid);
    if (entry) this.save.garage.items.splice(this.save.garage.items.indexOf(entry), 1);
    delete this.save.mystery_boxes[key(uid)];
    const carId: number = box.car_id;
    const colors = this.catalog.colorsForCar(carId);
    const car = this.addCar(carId, colors.length ? colors[0].id : 0);
    if (entry) {
      car.placed = true;
      car.x = entry.x;
      car.y = entry.y;
      car.rot = entry.rot;
    }
    const result = GameResult.success({ car_id: carId, uid: car.uid });
    this.addRewards(0, 0, Math.trunc(this.catalog.car(carId).xp ?? 0), result);
    this.checkCollections(result);
    return result;
  }

  // --- The Docks ---------------------------------------------------------------------------

  docks_pool(boatId: number, now: number): number[] {
    const excluded: number[] = this.catalog.consts.docks_excluded_cars ?? [];
    const minBlue: number = boatId === 2 ? this.catalog.tune("docks.special_min_blue", 40) : 0;
    const out: number[] = [];
    for (const [id, c] of this.catalog.cars) {
      if (!c.purchasable || !c.limited) continue;
      if (this.catalog.artCarIds.size > 0 && !this.catalog.artCarIds.has(id)) continue;
      const last: number = c.date_last_available ?? 0;
      if (last <= 0 || last >= now || excluded.includes(id) || Math.trunc(c.blue_price ?? 0) < minBlue) continue;
      out.push(id);
    }
    out.sort((a, b) => a - b);
    return out;
  }

  docks_special_boat(now: number): boolean {
    const last: number = this.save.docks.last_claim;
    return last >= 0 && now - last < Math.trunc(this.catalog.tune("docks.special_boat_hours", 24)) * 3600;
  }

  docks_search_price(): number {
    const d = this.save.docks;
    if (!d.first_done) return 0;
    return percentUp(Math.trunc(d.boat.price ?? 0), Math.trunc(this.catalog.consts.docks_search_percent ?? 60));
  }

  docks_currency(): string {
    return this.catalog.tune("docks.currency", "coins") === "blue" ? "blue" : "coins";
  }

  private docksPriceField(): string {
    return this.docks_currency() === "blue" ? "blue_price" : "price";
  }

  private docksPay(cost: number): string {
    const key = this.docks_currency();
    if (this.player[key] < cost) return key === "blue" ? "Not enough Blue Coins." : "Not enough coins.";
    this.player[key] -= cost;
    return "";
  }

  docks_search_again_price(): number {
    return percentUp(Math.trunc(this.save.docks.boat.price ?? 0), Math.trunc(this.catalog.consts.docks_search_again_percent ?? 20));
  }

  docks_manifest(boatId: number, wantedCarId: number, now: number): GameResult {
    const d = this.save.docks;
    if (d.boat.active) return GameResult.fail("Finish searching this boat first.");
    if (boatId !== 1 && boatId !== 2) return GameResult.fail("There's no such boat.");
    if (boatId === 2 && !this.docks_special_boat(now)) return GameResult.fail("Tony's special boat isn't in.");
    const pool = this.docks_pool(boatId, now);
    if (wantedCarId > 0) {
      if (!this.docks_pool(1, now).includes(wantedCarId)) return GameResult.fail("Tony can't get that car.");
      const at = pool.indexOf(wantedCarId);
      if (at >= 0) pool.splice(at, 1);
    }
    const need = DOCK_CRATES - (wantedCarId > 0 ? 1 : 0);
    if (pool.length < need) return GameResult.fail("No boats are in today.");
    for (let i = 0; i < need; i++) {
      const j = this.rng(i, pool.length - 1);
      const t = pool[i];
      pool[i] = pool[j];
      pool[j] = t;
    }
    const cars = pool.slice(0, need);
    if (wantedCarId > 0) cars.unshift(wantedCarId);
    const field = this.docksPriceField();
    let total = 0;
    for (const id of cars) total += Math.trunc(this.catalog.car(id)[field] ?? 0);
    let price = roundi(Math.trunc((total + DOCK_CRATES / 2) / DOCK_CRATES) * Number(this.catalog.tune("docks.price_multiplier", 1.0)));
    if (wantedCarId > 0) price = Math.trunc(this.catalog.car(wantedCarId)[field] ?? 0);
    const crates = [...cars];
    for (let i = crates.length - 1; i > 0; i--) {
      const j = this.rng(0, i);
      const t = crates[i];
      crates[i] = crates[j];
      crates[j] = t;
    }
    const states = new Array(DOCK_CRATES).fill(CRATE_CLOSED);
    d.boat = { id: boatId, cars, crates, states, price, wanted: wantedCarId, active: false };
    return GameResult.success({ cars, price: this.docks_search_price() });
  }

  docks_search(now: number): GameResult {
    const boat = this.save.docks.boat;
    if (Object.keys(boat).length === 0) return GameResult.fail("There's no boat in.");
    if (boat.active) return GameResult.fail("You're already searching this boat.");
    const cost = this.docks_search_price();
    const pay = this.docksPay(cost);
    if (pay) return GameResult.fail(pay);
    boat.active = true;
    this.bumpStat("docks_searches");
    return GameResult.success({ cost });
  }

  docks_open_crate(index: number, now: number): GameResult {
    const boat = this.save.docks.boat;
    if (!boat.active) return GameResult.fail("Search the boat first.");
    if (index < 0 || index >= DOCK_CRATES) return GameResult.fail("There's no such crate.");
    if (boat.states.indexOf(CRATE_OPEN) >= 0) return GameResult.fail("Claim this car or search again first.");
    if (boat.states[index] !== CRATE_CLOSED) return GameResult.fail("That crate's already open.");
    boat.states[index] = CRATE_OPEN;
    const carId: number = boat.crates[index];
    return GameResult.success({ index, car_id: carId, wanted: carId === boat.wanted });
  }

  docks_search_again(now: number): GameResult {
    const boat = this.save.docks.boat;
    const open = boat.active ? boat.states.indexOf(CRATE_OPEN) : -1;
    if (open < 0) return GameResult.fail("Open a crate first.");
    if (!boat.states.includes(CRATE_CLOSED)) return GameResult.fail("That was the last crate.");
    const cost = this.docks_search_again_price();
    const pay = this.docksPay(cost);
    if (pay) return GameResult.fail(pay);
    boat.states[open] = CRATE_PASSED;
    return GameResult.success({ cost });
  }

  docks_claim(now: number): GameResult {
    const d = this.save.docks;
    const boat = d.boat;
    const open = boat.active ? boat.states.indexOf(CRATE_OPEN) : -1;
    if (open < 0) return GameResult.fail("Open a crate first.");
    const carId: number = boat.crates[open];
    const colors = this.catalog.colorsForCar(carId);
    const car = this.addCar(carId, colors.length ? colors[0].id : 0);
    d.boat = {};
    d.first_done = true;
    d.last_claim = now;
    this.bumpStat("docks_claims");
    const result = GameResult.success({ car_id: carId, uid: car.uid });
    this.checkCollections(result);
    return result;
  }

  road_trip_ids(carUid: number): number[] {
    const car = this.get_car(carUid);
    const out: number[] = [];
    if (!car || !this.car_task_ids(carUid).includes(ROAD_TRIP_JOB)) return out;
    const hidden: number[] = this.catalog.tune("road_trips.hidden", []);
    for (const [id, t] of this.catalog.roadTrips) {
      if (hidden.includes(id)) continue;
      const only: number = t.specific_car_id ?? 0;
      if (only === 0 || only === car.car_id) out.push(id);
    }
    out.sort((a, b) => {
      const sa: number = this.catalog.roadTrips.get(a)!.sort ?? 0;
      const sb: number = this.catalog.roadTrips.get(b)!.sort ?? 0;
      return sa !== sb ? sb - sa : a - b;
    });
    return out;
  }

  carSeats(carId: number): number {
    return Math.max(1, Math.trunc(this.catalog.car(carId).seats ?? 1));
  }

  roadTripPay(carId: number, tripId: number, passengers: number): Dict {
    const cls: Dict = this.catalog.carClasses.get(Math.trunc(this.catalog.car(carId).class_id ?? 0)) ?? {};
    const trip: Dict = this.catalog.roadTrips.get(tripId) ?? {};
    const perCoins = roundi(Math.trunc(cls.coins_per_passenger ?? 0) * Number(trip.coin_multiplier ?? 1.0));
    const perXp = roundi(Math.trunc(cls.xp_per_passenger ?? 0) * Number(trip.xp_multiplier ?? 1.0));
    const full = passengers >= this.carSeats(carId);
    return { coins: perCoins * passengers + (full ? Math.trunc(cls.fill_up_bonus ?? 0) : 0), xp: perXp * passengers, full, per_coins: perCoins, per_xp: perXp, bonus: Math.trunc(cls.fill_up_bonus ?? 0) };
  }

  roadTripPassengers(task: Dict, now: number): number {
    let n = 1;
    for (const p of task.passengers ?? []) if (Math.trunc(p.at) <= now) n += 1;
    return n;
  }

  start_road_trip(carUid: number, tripId: number, now: number): GameResult {
    const car = this.get_car(carUid);
    if (!car) return GameResult.fail("Car not found.");
    if (!car.placed) return GameResult.fail("Put the car in your garage first.");
    if (car.bay_uid !== 0) return GameResult.fail("Take the car off the work bay first.");
    if (key(carUid) in this.save.car_tasks) return GameResult.fail("This car is already out on a job.");
    if (!this.road_trip_ids(carUid).includes(tripId)) return GameResult.fail("This car can't go there.");
    const def = this.catalog.job(ROAD_TRIP_JOB);
    if (this.player.level < def.min_level) return GameResult.fail(`Requires level ${def.min_level}.`);
    if (this.busyWorkers() >= this.maxWorkers()) return GameResult.fail("All your workers are busy. Level up to hire more.");
    const cost = Math.ceil(def.price * Number(this.catalog.tune("jobs.start_cost_multiplier", 1.0)));
    if (this.player.coins < cost) return GameResult.fail("Not enough coins.");
    this.player.coins -= cost;
    const duration: number = def.minutes * 60;
    const chance: number = this.catalog.tune("road_trips.passenger_chance_percent", 70);
    const window = Math.max(1, Math.trunc(duration * Math.trunc(this.catalog.tune("road_trips.join_window_percent", 80)) / 100));
    const names: string[] = this.catalog.tune("road_trips.passenger_names", ["Friend"]);
    const passengers: Dict[] = [];
    for (let i = 0; i < this.carSeats(car.car_id) - 1; i++) {
      if (this.rng(0, 99) < chance) passengers.push({ at: now + this.rng(0, window), name: String(names[this.rng(0, names.length - 1)]) });
    }
    passengers.sort((a, b) => Math.trunc(a.at) - Math.trunc(b.at));
    const endsAt = now + duration;
    this.save.car_tasks[key(carUid)] = { job_id: ROAD_TRIP_JOB, started_at: now, ends_at: endsAt, road_trip: tripId, passengers };
    this.bumpStat("jobs_started");
    const result = GameResult.success({ ends_at: endsAt });
    this.emit("STARTED_WORKBAY_TASK_ID", ROAD_TRIP_JOB, now, result);
    return result;
  }

  private finishRoadTrip(carUid: number, task: Dict, now: number): GameResult {
    const car = this.get_car(carUid)!;
    const trip: number = task.road_trip ?? 0;
    const aboard = this.roadTripPassengers(task, Math.trunc(task.ends_at));
    const pay = this.roadTripPay(car.car_id, trip, aboard);
    const result = GameResult.success({ coins: pay.coins, xp: pay.xp, passengers: aboard, seats: this.carSeats(car.car_id), full: pay.full, road_trip: trip });
    this.addRewards(pay.coins, 0, pay.xp, result);
    this.bumpStat("jobs_collected");
    this.bumpStat("road_trips");
    const carId: number = car.car_id;
    this.emit("COLLECTED_WORKBAY_TASK_ID", ROAD_TRIP_JOB, now, result);
    this.emit("FINISHED_ROAD_TRIP_WITH_CAR_ID", carId, now, result);
    this.emit("FINISHED_ROAD_TRIP_WITH_ID", trip, now, result);
    if (pay.full) this.emit("FINISHED_ROAD_TRIP_CAR_FULL_WITH_ROADTRIP_ID", trip, now, result);
    if (trip === 1) this.emit("FINISHED_BEACH_ROAD_TRIP_WITH_CAR_ID", carId, now, result);
    if (trip === 2 && pay.full) this.emit("FINISHED_FULL_CAMPING_ROAD_TRIP_WITH_CAR_ID", carId, now, result);
    return result;
  }

  collect_car_task(carUid: number, now: number): GameResult {
    const k = key(carUid);
    if (!(k in this.save.car_tasks)) return GameResult.fail("This car isn't out on a job.");
    const task = this.save.car_tasks[k];
    if (now < task.ends_at) return GameResult.fail("The job isn't finished yet.");
    const jobId: number = task.job_id;
    delete this.save.car_tasks[k];
    if (jobId === ROAD_TRIP_JOB) return this.finishRoadTrip(carUid, task, now);
    const result = this.payJob(jobId);
    this.bumpStat("jobs_collected");
    this.emit("COLLECTED_WORKBAY_TASK_ID", jobId, now, result);
    return result;
  }

  stop_car_task(carUid: number): GameResult {
    if (!(key(carUid) in this.save.car_tasks)) return GameResult.fail("This car isn't out on a job.");
    delete this.save.car_tasks[key(carUid)];
    return GameResult.success();
  }

  carTaskFinishPrice(carUid: number, now: number): number {
    const task = this.save.car_tasks[key(carUid)];
    return task ? this.finishPrice(task.ends_at - now) : 0;
  }

  finish_car_task_now(carUid: number, now: number): GameResult {
    const task = this.save.car_tasks[key(carUid)];
    if (!task) return GameResult.fail("This car isn't out on a job.");
    if (now >= task.ends_at) return this.collect_car_task(carUid, now);
    const price = this.carTaskFinishPrice(carUid, now);
    if (this.player.blue < price) return GameResult.fail("Not enough blue coins.");
    this.player.blue -= price;
    task.ends_at = now;
    return this.collect_car_task(carUid, now);
  }

  // --- Customers --------------------------------------------------------------------------

  tick(now: number): GameResult {
    const result = GameResult.success();
    this.refillFuel(now);
    const interval = Math.trunc(this.catalog.tune("customers.interval_minutes", 2)) * 60;
    const maxWaiting: number = this.catalog.tune("customers.max_waiting", 3);
    const pool = this.customerPool();
    while (this.save.next_customer_at <= now && pool.length > 0) {
      if (this.waitingCustomers() >= maxWaiting) {
        this.save.next_customer_at = now + interval;
        break;
      }
      const pick = SimpleRng.rangeInt(this.save.rng, 0, pool.length - 1);
      this.save.rng = pick[0];
      const carId = pool[pick[1]];
      const colors = this.catalog.colorsForCar(carId);
      const colorPick = SimpleRng.rangeInt(this.save.rng, 0, Math.max(0, colors.length - 1));
      this.save.rng = colorPick[0];
      const jobs = this.customerJobs();
      let jobId = 0;
      if (jobs.length > 0) {
        const jobPick = SimpleRng.rangeInt(this.save.rng, 0, jobs.length - 1);
        this.save.rng = jobPick[0];
        jobId = jobs[jobPick[1]];
      }
      this.save.customers.push({
        uid: this.uid(), car_id: carId,
        color_id: colors.length ? colors[colorPick[1]].id : 0,
        arrived_at: this.save.next_customer_at, bay_uid: 0, job_id: jobId,
      });
      this.save.next_customer_at += interval;
      result.data.arrived = (result.data.arrived ?? 0) + 1;
    }
    if (pool.length === 0) this.save.next_customer_at = now + interval;
    this.restorationGifts(now, result);
    this.missions.refreshDaily(this.save, now, this.dealerIds);
    return result;
  }

  private customerJobs(): number[] {
    const maxMinutes: number = this.catalog.tune("customers.max_job_minutes", 5);
    return this.available_job_ids().filter((id) => {
      const j = this.catalog.job(id);
      return j.min_level <= this.player.level && j.minutes <= maxMinutes;
    });
  }

  private waitingCustomers(): number {
    return this.save.customers.filter((c: Dict) => (c.bay_uid ?? 0) === 0).length;
  }

  private customerPool(): number[] {
    const level: number = this.player.level;
    return this.dealer_car_ids().filter((id) => this.catalog.car(id).min_level <= level + 5);
  }

  accept_customer(customerUid: number, bayUid: number): GameResult {
    const cust = this.get_customer(customerUid);
    if (!cust || (cust.bay_uid ?? 0) !== 0) return GameResult.fail("That customer isn't waiting.");
    if (!this.isBay(bayUid)) return GameResult.fail("That isn't a work bay.");
    if (Object.keys(this.bayOccupant(bayUid)).length > 0) return GameResult.fail("That work bay is taken.");
    cust.bay_uid = bayUid;
    this.bumpStat("customers_accepted");
    return GameResult.success();
  }

  dismiss_customer(customerUid: number): GameResult {
    const cust = this.get_customer(customerUid);
    if (!cust) return GameResult.fail("Customer not found.");
    if ((cust.bay_uid ?? 0) !== 0 && key(cust.bay_uid) in this.save.jobs) return GameResult.fail("Finish the job first.");
    this.save.customers.splice(this.save.customers.indexOf(cust), 1);
    return GameResult.success();
  }

  // --- Town -------------------------------------------------------------------------------

  town_location_ids(): number[] {
    return (this.catalog.tune("town.v1_locations", []) as number[]).filter((id) => this.catalog.locations.has(id));
  }

  open_gps(now: number): GameResult {
    const result = GameResult.success();
    this.emit("OPEN_GPS", 0, now, result);
    return result;
  }

  visit_location(locationId: number, now: number): GameResult {
    if (!this.town_location_ids().includes(locationId)) return GameResult.fail("You can't go there yet.");
    const loc = this.catalog.locations.get(locationId)!;
    if (this.player.level < loc.min_level) return GameResult.fail(`Requires level ${loc.min_level}.`);
    if (!this.save.visited_locations.includes(locationId)) this.save.visited_locations.push(locationId);
    const result = GameResult.success();
    this.emit("WENT_TO_LOCATION", locationId, now, result);
    return result;
  }

  // --- Car collections --------------------------------------------------------------------

  collection_progress(collectionId: number): number[] {
    const ids: number[] = this.catalog.carCollections.get(collectionId)?.car_ids ?? [];
    let owned = 0;
    for (const id of ids) if (this.save.cars.some((c: Dict) => c.car_id === id)) owned += 1;
    return [owned, ids.length];
  }

  private checkCollections(result: GameResult): void {
    for (const [id, c] of this.catalog.carCollections) {
      if (this.save.collections_done.includes(id)) continue;
      const progress = this.collection_progress(id);
      if (progress[1] === 0 || progress[0] < progress[1]) continue;
      this.save.collections_done.push(id);
      this.addRewards(c.coins, 0, c.xp, result);
      const plaque: number = c.plaque_item_id ?? 0;
      if (plaque > 0 && Object.keys(this.catalog.item(plaque)).length > 0) this.storeItemId(plaque);
      const prize = this.giveReward(c.reward_type ?? "", c.reward_id ?? 0);
      result.notices.push({ kind: "collection_complete", collection_id: id, name: c.name, coins: c.coins, xp: c.xp, plaque_id: plaque, prize });
    }
  }

  // --- Daily rewards ----------------------------------------------------------------------

  private dayNumber(now: number): number {
    return Math.trunc(now / 86400);
  }

  daily_reward_status(now: number): Dict {
    const list = this.catalog.dailyRewards;
    if (list.length === 0) return { available: false };
    const d = this.save.daily_reward;
    const today = this.dayNumber(now);
    let streak: number = d.last_day !== today - 1 ? 1 : Math.trunc(d.streak) + 1;
    if (d.last_day === today) streak = Math.trunc(d.streak);
    const index = (streak - 1) % list.length;
    return { available: d.last_day !== today, streak, day: index + 1, reward: list[index], next_reward: list[(index + 1) % list.length] };
  }

  claim_daily_reward(now: number): GameResult {
    const status = this.daily_reward_status(now);
    if (!status.available) return GameResult.fail("You've already collected today's prize.");
    const reward: Dict = status.reward;
    const d = this.save.daily_reward;
    d.last_day = this.dayNumber(now);
    d.streak = status.streak;
    const result = GameResult.success({ streak: status.streak, day: status.day, type: reward.type, id: reward.id, amount: reward.amount });
    const amount: number = reward.amount;
    switch (reward.type) {
      case "Point":
        this.addRewards(0, amount, 0, result);
        break;
      case "Coins":
        this.addRewards(amount, 0, 0, result);
        break;
      case "XP":
        this.addRewards(0, 0, amount, result);
        break;
      case "Petrol":
        this.refillFuel(now);
        this.player.fuel = Math.trunc(this.player.fuel) + amount;
        break;
      case "Item":
      case "Car": {
        const given = this.giveReward(reward.type, reward.id);
        if (Object.keys(given).length === 0) this.dailyFallback(result);
        break;
      }
      default:
        this.dailyFallback(result);
    }
    this.checkCollections(result);
    return result;
  }

  private dailyFallback(result: GameResult): void {
    const coins: number = this.catalog.tune("daily_rewards.fallback_coins", 250);
    this.addRewards(coins, 0, 0, result);
    result.data.type = "Coins";
    result.data.amount = coins;
  }

  // --- Street racing and fuel -------------------------------------------------------------

  fuelTank(): number {
    return Math.trunc(this.catalog.levelInfo(this.player.level).fuel_tank ?? 5) + Math.trunc(this.catalog.tune("racing.fuel_tank_bonus", 0));
  }

  fuelRefillSeconds(): number {
    return Math.trunc(this.catalog.tune("racing.fuel_refill_seconds", this.catalog.consts.fuel_refill_seconds ?? 560));
  }

  private refillFuel(now: number): void {
    const p = this.player;
    const tank = this.fuelTank();
    if (!("fuel" in p)) {
      p.fuel = tank;
      p.fuel_at = now;
    }
    if (p.fuel >= tank) {
      p.fuel_at = now;
      return;
    }
    const per = this.fuelRefillSeconds();
    const gained = Math.trunc(Math.max(0, now - p.fuel_at) / per);
    if (gained > 0) {
      p.fuel = Math.min(tank, p.fuel + gained);
      p.fuel_at = p.fuel_at + gained * per;
    }
    if (p.fuel >= tank) p.fuel_at = now;
  }

  fuel(now: number): number {
    const p = this.player;
    const tank = this.fuelTank();
    const have: number = p.fuel ?? tank;
    if (have >= tank) return have;
    return Math.min(tank, have + Math.trunc(Math.max(0, now - (p.fuel_at ?? now)) / this.fuelRefillSeconds()));
  }

  raceLocations(): number[] {
    const towns = this.town_location_ids();
    return (this.catalog.tune("racing.locations", []) as number[]).filter((id) => towns.includes(id));
  }

  bestCarPower(): number {
    let best = 0;
    for (const c of this.save.cars) best = Math.max(best, this.carScore(c.uid));
    return best;
  }

  raceOpponents(locationId: number, now: number): Dict[] {
    const out: Dict[] = [];
    const pool = this.dealer_car_ids();
    if (pool.length === 0) return out;
    const best = Math.max(this.bestCarPower(), 100);
    const span: number[] = this.catalog.tune("racing.opponent_power_range", [0.6, 1.3]);
    const lo = best * Number(span[0]);
    const hi = best * Number(span[1]);
    const count: number = this.catalog.tune("racing.opponents_per_location", 6);
    let candidates: number[] = [];
    for (const id of pool) {
      const power: number = this.catalog.car(id).score ?? 0;
      if (power >= lo && power <= hi) candidates.push(id);
    }
    if (candidates.length < count) {
      candidates = [...pool];
      candidates.sort((a, b) => {
        const da = Math.abs((this.catalog.car(a).score ?? 0) - best);
        const db = Math.abs((this.catalog.car(b).score ?? 0) - best);
        return da !== db ? da - db : a - b;
      });
      candidates = candidates.slice(0, count * 3);
    }
    const names: string[] = this.catalog.tune("racing.opponent_names", ["Racer"]);
    let state = locationId * 7919 + Math.trunc(now / 3600);
    for (let i = 0; i < count; i++) {
      state = SimpleRng.next(state);
      const carId = candidates[(state >> 8) % candidates.length];
      const colors = this.catalog.colorsForCar(carId);
      const colorId: number = colors.length > 0 ? colors[(state >> 12) % colors.length].id : 0;
      out.push({ index: i, car_id: carId, color_id: colorId, power: Math.trunc(this.catalog.car(carId).score ?? 0), name: String(names[(state >> 4) % names.length]) });
    }
    return out;
  }

  racePrize(power: number): Dict {
    const c = this.catalog.consts;
    const minP = Number(c.race_prize_min_power ?? 100);
    const maxP = Number(c.race_prize_max_power ?? 1350);
    const t = Math.min(1, Math.max(0, (power - minP) / Math.max(1, maxP - minP)));
    const lerp = (a: number, b: number) => a + (b - a) * t;
    return {
      coins: Math.floor(lerp(Number(c.race_prize_min_coins ?? 50), Number(c.race_prize_max_coins ?? 500))),
      xp: Math.floor(lerp(Number(c.race_prize_min_xp ?? 2), Number(c.race_prize_max_xp ?? 10))),
    };
  }

  start_race(locationId: number, index: number, carUid: number, now: number): GameResult {
    if (!this.raceLocations().includes(locationId)) return GameResult.fail("There's no racing here.");
    const car = this.get_car(carUid);
    if (!car) return GameResult.fail("Car not found.");
    if (key(carUid) in this.save.car_tasks) return GameResult.fail("This car is out on a job.");
    const opponents = this.raceOpponents(locationId, now);
    if (index < 0 || index >= opponents.length) return GameResult.fail("That car has left.");
    this.refillFuel(now);
    const p = this.player;
    if (p.fuel < 1) return GameResult.fail("You're out of fuel.");
    const full = p.fuel >= this.fuelTank();
    p.fuel -= 1;
    if (full) p.fuel_at = now;
    const opponent = opponents[index];
    const opponentScore = this.opponentScore(opponent.power);
    this.save.race = { location_id: locationId, car_uid: carUid, power: this.carScore(carUid), opponent, opponent_score: opponentScore, started_at: now };
    this.bumpStat("races_started");
    return GameResult.success({ opponent, opponent_score: opponentScore });
  }

  private opponentScore(power: number): number {
    const bonusChance: number = this.catalog.tune("racing.opponent_bonus_chance_percent", 25);
    let total = 0;
    let roll = this.rng(0, 99);
    if (roll < bonusChance) total += Math.floor(power * 2 * (1 - this.rng(0, 49) / 1000));
    else total += Math.floor(power * (1 - this.rng(50, 600) / 1000));
    for (let i = 0; i < 3; i++) {
      roll = this.rng(0, 99);
      if (roll < bonusChance) {
        const deg = this.rng(241, 247);
        total += roundi(2 * power * (244 - Math.abs(244 - deg)) / 244);
      } else {
        total += roundi(power * this.rng(150, 240) / 244);
      }
    }
    return total;
  }

  private rng(lo: number, hi: number): number {
    const pick = SimpleRng.rangeInt(this.save.rng, lo, hi);
    this.save.rng = pick[0];
    return pick[1];
  }

  finish_race(score: number, perfectShifts: number, redlined: boolean, now: number): GameResult {
    const race: Dict = this.save.race ?? {};
    if (Object.keys(race).length === 0) return GameResult.fail("You aren't racing.");
    this.save.race = {};
    const power: number = race.power;
    const nitrous: number = this.catalog.tune("racing.nitrous_per_shift", 50);
    score = Math.min(8 * power + 3 * nitrous, Math.max(-4 * power, score));
    perfectShifts = Math.min(3, Math.max(0, perfectShifts));
    const opponent: Dict = race.opponent;
    const opponentScore: number = race.opponent_score;
    const win = score >= opponentScore;
    const result = GameResult.success({ win, score, opponent_score: opponentScore });
    const stats = this.save.stats;
    stats.race_high_score = Math.max(Math.trunc(stats.race_high_score ?? 0), score);
    const location: number = race.location_id;
    if (win) {
      const prize = this.racePrize(opponent.power);
      this.addRewards(prize.coins, 0, prize.xp, result);
      result.data.coins = prize.coins;
      result.data.xp = prize.xp;
      this.bumpStat("races_won");
      this.emit("WON_TOWN_RACE", 0, now, result);
      this.emit("WON_TOWN_RACE_AT_LOCATION", location, now, result);
      if (!redlined) this.emit("WON_TOWN_RACE_WITHOUT_REDLINING_AT_LOCATION", location, now, result);
      if (perfectShifts > 0) this.emit("WON_TOWN_RACE_WITH_PERFECT_SHIFTS", perfectShifts, now, result);
      if (Math.trunc(opponent.power) > power) this.emit("WON_TOWN_RACE_AGAINST_FASTER_OPPONENT", 0, now, result);
    } else {
      const xp = Math.trunc(this.catalog.consts.race_start_xp ?? 1);
      const coins: number = this.catalog.tune("racing.loss_coins", 0);
      this.addRewards(coins, 0, xp, result);
      result.data.coins = coins;
      result.data.xp = xp;
      this.bumpStat("races_lost");
    }
    return result;
  }

  buy_fuel(consumableId: number, now: number): GameResult {
    const def = this.catalog.consumable(consumableId);
    if (Object.keys(def).length === 0 || !(this.catalog.tune("racing.fuel_can_ids", []) as number[]).includes(consumableId)) {
      return GameResult.fail("That isn't for sale.");
    }
    this.refillFuel(now);
    const p = this.player;
    const price: number = def.blue_price ?? 0;
    if (p.blue < price) return GameResult.fail("Not enough blue coins.");
    p.blue -= price;
    if ((def.kind ?? 1) === 2) p.fuel = Math.max(p.fuel, this.fuelTank());
    else p.fuel = p.fuel + Math.trunc(def.amount ?? 1);
    p.fuel_at = now;
    return GameResult.success({ fuel: p.fuel });
  }

  // --- Tutorial ---------------------------------------------------------------------------

  set_tutorial(step: number, done: boolean): GameResult {
    this.save.tutorial = { step, done };
    return GameResult.success();
  }

  rename(playerName: string): GameResult {
    const n = playerName.trim();
    if (n === "" || n.length > 20) return GameResult.fail("Names are 1 to 20 characters.");
    this.player.name = n;
    return GameResult.success();
  }
}
