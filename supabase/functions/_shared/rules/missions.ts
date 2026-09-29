// Server copy of scripts/rules/mission_tracker.gd.
import type { Catalog, Dict } from "./catalog.ts";
import { isFloorObject } from "./grid.ts";
import { idiv, key, SimpleRng } from "./util.ts";

const SECONDS_PER_DAY = 86400;

export class MissionTracker {
  catalog: Catalog;
  /** Titles of new-player-track missions (see mission_tracker.gd). */
  private newPlayerTitles = new Set<string>();

  constructor(catalog: Catalog) {
    this.catalog = catalog;
    for (const m of catalog.missions.values()) {
      if (m.category === "tutorial" && !m.hidden) this.newPlayerTitles.add(m.title);
    }
  }

  private skipped(m: Dict): boolean {
    if (m.hidden) return true;
    return m.category === "standard" && this.newPlayerTitles.has(m.title);
  }

  stepAchievable(step: Dict, dealerIds: Set<number>): boolean {
    const events: string[] = this.catalog.tune("missions.v1_events", []);
    const event: string = step.event;
    if (!events.includes(event)) return false;
    const params: number[] = step.params;
    switch (event) {
      case "WENT_TO_LOCATION": {
        const locs: number[] = this.catalog.tune("town.v1_locations", []);
        for (const p of params) if (!locs.includes(p)) return false;
        break;
      }
      case "BOUGHT_CAR_ID":
        for (const p of params) if (!dealerIds.has(p)) return false;
        break;
      case "BOUGHT_ITEM_ID":
        for (const p of params) if (!isFloorObject(this.catalog.item(p))) return false;
        break;
      case "BOUGHT_ITEM_CATEGORY":
        if (params.length === 0) return false;
        break;
    }
    return true;
  }

  missionSupported(mid: number, dealerIds: Set<number>): boolean {
    const steps = this.catalog.stepsByMission.get(mid) ?? [];
    if (steps.length === 0) return false;
    return steps.every((s) => this.stepAchievable(s, dealerIds));
  }

  available(save: Dict, _now: number, dealerIds: Set<number>): number[] {
    const result: number[] = [];
    const completed: number[] = save.missions.completed;
    const level: number = save.player.level;
    for (const [mid, m] of this.catalog.missions) {
      if (m.category === "daily" || completed.includes(mid) || this.skipped(m)) continue;
      if (level < m.min_level || level > m.max_level) continue;
      if (!this.prereqsMet(m, completed)) continue;
      if (!this.missionSupported(mid, dealerIds)) continue;
      result.push(mid);
    }
    result.sort((a, b) => this.catalog.missions.get(a)!.index - this.catalog.missions.get(b)!.index);
    return result;
  }

  private prereqsMet(m: Dict, completed: number[]): boolean {
    for (const req of m.requires_missions) if (!completed.includes(req)) return false;
    for (const hide of m.hidden_after_missions) if (completed.includes(hide)) return false;
    return true;
  }

  refreshDaily(save: Dict, now: number, dealerIds: Set<number>): void {
    const day = idiv(now, SECONDS_PER_DAY);
    const daily: Dict = save.missions.daily;
    if ((daily.day ?? -1) === day) return;
    const pool: number[] = [];
    for (const [mid, m] of this.catalog.missions) {
      if (m.category === "daily" && !m.hidden && this.missionSupported(mid, dealerIds) && save.player.level >= m.min_level) {
        pool.push(mid);
      }
    }
    pool.sort((a, b) => a - b);
    const picked: number[] = [];
    const count = Math.min(this.catalog.tune("missions.daily_count", 3), pool.length);
    let state = day;
    while (picked.length < count) {
      state = SimpleRng.next(state);
      const mid = pool[(state >> 8) % pool.length];
      if (!picked.includes(mid)) picked.push(mid);
    }
    for (const old of daily.ids ?? []) delete save.missions.progress[key(old)];
    save.missions.daily = { day, ids: picked, done: [] };
  }

  activeIds(save: Dict, now: number, dealerIds: Set<number>): number[] {
    const ids = this.available(save, now, dealerIds);
    const daily: Dict = save.missions.daily;
    for (const mid of daily.ids ?? []) {
      if (!(daily.done ?? []).includes(mid)) ids.push(mid);
    }
    return ids;
  }

  record(save: Dict, event: string, param: number, now: number, dealerIds: Set<number>): number[] {
    const done: number[] = [];
    const progress: Dict = save.missions.progress;
    for (const mid of this.activeIds(save, now, dealerIds)) {
      let changed = false;
      for (const step of this.catalog.stepsByMission.get(mid) ?? []) {
        if (step.event !== event) continue;
        const params: number[] = step.params;
        if (params.length > 0 && !params.includes(param)) continue;
        const mk = key(mid);
        if (!(mk in progress)) progress[mk] = {};
        const sk = key(step.id);
        const count: number = progress[mk][sk] ?? 0;
        if (count < step.count) {
          progress[mk][sk] = count + 1;
          changed = true;
        }
      }
      if (changed && this.isComplete(save, mid)) done.push(mid);
    }
    return done;
  }

  isComplete(save: Dict, mid: number): boolean {
    const progress: Dict = save.missions.progress[key(mid)] ?? {};
    for (const step of this.catalog.stepsByMission.get(mid) ?? []) {
      if ((progress[key(step.id)] ?? 0) < step.count) return false;
    }
    return true;
  }

  stepProgress(save: Dict, mid: number, stepId: number): number {
    return save.missions.progress[key(mid)]?.[key(stepId)] ?? 0;
  }

  markDone(save: Dict, mid: number): void {
    const m = this.catalog.missions.get(mid)!;
    delete save.missions.progress[key(mid)];
    if (m.category === "daily") save.missions.daily.done.push(mid);
    else if (!save.missions.completed.includes(mid)) save.missions.completed.push(mid);
  }
}
