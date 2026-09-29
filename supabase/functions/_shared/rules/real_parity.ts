// Local-only: replays _reference/golden_real.json (made by
// scenes/dev/make_golden_real.tscn on the real catalog) with the server rules.
// Needs tools/build_server_data.py to have run. Not part of the test suite
// because the data isn't in Git.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Catalog } from "./catalog.ts";
import { GameLogic } from "./logic.ts";
import { runOn } from "./actions.ts";
import { ART_CAR_IDS, DATA, TUNING } from "../catalog/data.ts";

const ROOT = join(import.meta.dirname, "..", "..", "..", "..");
const t = JSON.parse(readFileSync(join(ROOT, "_reference", "golden_real.json"), "utf8"));
const cat = Catalog.fromData(DATA, TUNING);
for (const id of ART_CAR_IDS) cat.artCarIds.add(id);
const save = GameLogic.newSave(cat, "Real", 1_760_000_000);
assert.deepEqual(save, t.start, "new game differs");
const logic = new GameLogic(cat, save);
for (const [i, s] of t.steps.entries()) {
  const r = runOn(logic, s.action, s.args, s.now);
  assert.deepEqual(r.toDict(), s.result, `step ${i} ${s.action}: result differs`);
  assert.deepEqual(logic.save, s.save, `step ${i} ${s.action}: save differs`);
}
console.log(`real-catalog parity OK (${t.steps.length} steps)`);
