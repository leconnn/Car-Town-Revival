// Server copy of scripts/rules/game_logic.gd. Same functions, same order,
// same messages. Change both together; the golden transcripts check it.
import type { Catalog, Dict } from "./catalog.ts";
import { CAT_FLOOR_TILE, CAT_WALL, CAT_WORK_BAY, GarageGrid, isFloorObject, rotatedSize } from "./grid.ts";
import { MissionTracker } from "./missions.ts";
import { key, posmod, roundi, SimpleRng } from "./util.ts";

export const CURRENT_SAVE_VERSION = 2;

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
  }

  // --- New game -------------------------------------------------------------

  static newSave(cat: Catalog, playerName: string, now: number): Dict {
    const start: Dict = cat.tune("start", {});
    const s: Dict = {
      save_version: CURRENT_SAVE_VERSION,
      created_at: now,
      updated_at: now,
      player: { name: playerName, coins: start.coins ?? 10000, blue: start.blue ?? 0, xp: 0, level: 1 },
      next_uid: 1,
      rng: now % SimpleRng.MODULUS,
      garage: {
        land_id: start.land_id ?? 1,
        floor_item_id: start.floor_item_id ?? 0,
        wall_item_id: start.wall_item_id ?? 0,
        items: [],
        wall_items: [],
      },
      cars: [],
      storage: {},
      jobs: {},
      car_tasks: {},
      job_mastery: {},
      customers: [],
      next_customer_at: now,
      missions: { progress: {}, completed: [], daily: {} },
      tutorial: { step: 0, done: false },
      visited_locations: [],
      stats: {},
    };
    const logic = new GameLogic(cat, s);
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
    for (const it of this.save.garage.items) total += this.catalog.item(it.item_id).price ?? 0;
    return total;
  }

  garageValueTier(): number { return this.catalog.garageValueTier(this.garageValue()); }

  maxWorkers(): number { return this.catalog.levelInfo(this.player.level).max_workers; }

  busyWorkers(): number {
    return Object.keys(this.save.jobs).length + Object.keys(this.save.car_tasks).length;
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
    const result: number[] = [];
    for (const [id, c] of this.catalog.cars) {
      if (c.price < minPrice) continue;
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
    if (!isStock) {
      let err = this.levelOk(p);
      if (err) return GameResult.fail(err);
      err = this.charge(p, useBlue);
      if (err) return GameResult.fail(err);
    }
    car.parts[catKey] = partId;
    const result = GameResult.success();
    if (!isStock) {
      this.addRewards(0, 0, p.xp ?? 0, result);
      this.emit("INSTALLED_CAR_PART_CATEGORY", p.category_id, now, result);
    }
    return result;
  }

  remove_part(uid: number, categoryId: number): GameResult {
    const car = this.get_car(uid);
    if (!car) return GameResult.fail("Car not found.");
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
    if (Object.keys(def).length === 0 || !isFloorObject(def)) return GameResult.fail("That item can't be placed on the floor.");
    let err = this.levelOk(def);
    if (err) return GameResult.fail(err);
    if (!this.itemFits(itemId, x, y, rot)) return GameResult.fail("There's no room there.");
    err = this.charge(def, useBlue);
    if (err) return GameResult.fail(err);
    const entry = this.addItem(itemId, x, y, rot);
    const result = GameResult.success({ uid: entry.uid });
    this.addRewards(0, 0, def.xp ?? 0, result);
    this.emit("BOUGHT_ITEM_ID", itemId, now, result);
    this.emit("BOUGHT_ITEM_CATEGORY", def.category, now, result);
    if (def.category !== CAT_WORK_BAY) this.emit("DECORATE_GARAGE", 0, now, result);
    return result;
  }

  move_item(uid: number, x: number, y: number, rot: number): GameResult {
    const entry = this.findItem(uid);
    if (!entry) return GameResult.fail("Item not found.");
    if (this.bayBusy(uid)) return GameResult.fail("Clear the work bay before moving it.");
    if (!this.itemFits(entry.item_id, x, y, rot, `item:${uid}`)) return GameResult.fail("There's no room there.");
    entry.x = x;
    entry.y = y;
    entry.rot = posmod(rot, 4);
    return GameResult.success();
  }

  store_item(uid: number): GameResult {
    const entry = this.findItem(uid);
    if (!entry) return GameResult.fail("Item not found.");
    if (this.bayBusy(uid)) return GameResult.fail("Clear the work bay before storing it.");
    this.save.garage.items.splice(this.save.garage.items.indexOf(entry), 1);
    this.storeItemId(entry.item_id);
    return GameResult.success();
  }

  clear_floor(cars: boolean, items: boolean, bays: boolean): GameResult {
    const stored = { cars: 0, items: 0, bays: 0 };
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
    if (!isFloorObject(this.catalog.item(itemId)) || !this.itemFits(itemId, x, y, rot)) {
      return GameResult.fail("There's no room there.");
    }
    this.save.storage[k] -= 1;
    if (this.save.storage[k] === 0) delete this.save.storage[k];
    const entry = this.addItem(itemId, x, y, rot);
    return GameResult.success({ uid: entry.uid });
  }

  sell_item(uid: number): GameResult {
    const entry = this.findItem(uid);
    if (!entry) return GameResult.fail("Item not found.");
    if (this.bayBusy(uid)) return GameResult.fail("Clear the work bay before selling it.");
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

  set_surface(itemId: number, useBlue: boolean, now: number): GameResult {
    const def = this.catalog.item(itemId);
    const cat: number = def.category ?? 0;
    if (cat !== CAT_FLOOR_TILE && cat !== CAT_WALL) return GameResult.fail("That isn't a floor or wall style.");
    const k = cat === CAT_FLOOR_TILE ? "floor_item_id" : "wall_item_id";
    if (this.save.garage[k] === itemId) return GameResult.fail("Your garage already uses that style.");
    let err = this.levelOk(def);
    if (err) return GameResult.fail(err);
    const land = this.catalog.land(this.save.garage.land_id);
    const tiles = cat === CAT_FLOOR_TILE ? land.size_x * land.size_y : land.size_x + land.size_y;
    err = this.charge(def, useBlue, tiles);
    if (err) return GameResult.fail(err);
    this.save.garage[k] = itemId;
    const result = GameResult.success();
    this.emit("BOUGHT_ITEM_ID", itemId, now, result);
    this.emit("BOUGHT_ITEM_CATEGORY", cat, now, result);
    this.emit("DECORATE_GARAGE", 0, now, result);
    return result;
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
      result.notices.push({ kind: "mastery", job_id: jobId, level: after, coins: bonus.coin_bonus ?? 0, blue: bonus.blue_bonus ?? 0 });
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

  collect_car_task(carUid: number, now: number): GameResult {
    const k = key(carUid);
    if (!(k in this.save.car_tasks)) return GameResult.fail("This car isn't out on a job.");
    const task = this.save.car_tasks[k];
    if (now < task.ends_at) return GameResult.fail("The job isn't finished yet.");
    const jobId: number = task.job_id;
    delete this.save.car_tasks[k];
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
