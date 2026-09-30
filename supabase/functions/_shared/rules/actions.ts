// Server copy of BackendImpl.ACTIONS / validate / run_on
// (scripts/backend/backend_impl.gd).
import type { Dict } from "./catalog.ts";
import { GameLogic, GameResult } from "./logic.ts";

type ArgType = "int" | "bool" | "string";

export const ACTIONS: Record<string, { args: ArgType[]; now: boolean }> = {
  buy_car: { args: ["int", "int", "bool"], now: true },
  sell_car: { args: ["int"], now: true },
  paint_car: { args: ["int", "int", "bool"], now: true },
  install_part: { args: ["int", "int", "bool"], now: true },
  remove_part: { args: ["int", "int"], now: false },
  upgrade_car: { args: ["int", "int"], now: true },
  set_ride_height: { args: ["int", "int", "bool"], now: true },
  set_plate: { args: ["int", "string", "bool"], now: true },
  move_car: { args: ["int", "int", "int", "int"], now: false },
  store_car: { args: ["int"], now: false },
  buy_item: { args: ["int", "int", "int", "int", "bool"], now: true },
  move_item: { args: ["int", "int", "int", "int"], now: false },
  store_item: { args: ["int"], now: false },
  place_stored_item: { args: ["int", "int", "int", "int"], now: false },
  sell_item: { args: ["int"], now: false },
  sell_stored_item: { args: ["int"], now: false },
  expand_land: { args: ["bool"], now: true },
  put_car_on_bay: { args: ["int", "int"], now: false },
  take_car_off_bay: { args: ["int"], now: false },
  start_job: { args: ["int", "int"], now: true },
  collect_job: { args: ["int"], now: true },
  finish_job_now: { args: ["int"], now: true },
  stop_job: { args: ["int"], now: false },
  start_car_task: { args: ["int", "int"], now: true },
  collect_car_task: { args: ["int"], now: true },
  finish_car_task_now: { args: ["int"], now: true },
  stop_car_task: { args: ["int"], now: false },
  start_race: { args: ["int", "int", "int"], now: true },
  finish_race: { args: ["int", "int", "bool"], now: true },
  buy_fuel: { args: ["int"], now: true },
  clear_floor: { args: ["bool", "bool", "bool", "bool", "bool"], now: false },
  accept_customer: { args: ["int", "int"], now: false },
  dismiss_customer: { args: ["int"], now: false },
  tick: { args: [], now: true },
  open_gps: { args: [], now: true },
  visit_location: { args: ["int"], now: true },
  set_tutorial: { args: ["int", "bool"], now: false },
  rename: { args: ["string"], now: false },
};

export function validate(action: string, args: unknown[]): unknown[] | null {
  const spec = ACTIONS[action];
  if (!spec || !Array.isArray(args) || args.length !== spec.args.length) return null;
  for (let i = 0; i < args.length; i++) {
    const v = args[i];
    switch (spec.args[i]) {
      case "int":
        if (typeof v !== "number" || !Number.isInteger(v)) return null;
        break;
      case "bool":
        if (typeof v !== "boolean") return null;
        break;
      case "string":
        if (typeof v !== "string" || v.length > 64) return null;
        break;
    }
  }
  return [...args];
}

export function runOn(logic: GameLogic, action: string, args: unknown[], now: number): GameResult {
  const clean = validate(action, args);
  if (clean === null) return GameResult.fail("Invalid action.");
  if (ACTIONS[action].now) clean.push(now);
  // deno-lint-ignore no-explicit-any
  const fn = (logic as any)[action];
  if (typeof fn !== "function") return GameResult.fail("Action failed.");
  const result: GameResult = fn.apply(logic, clean);
  if (result.ok) (logic.save as Dict).updated_at = now;
  return result;
}
