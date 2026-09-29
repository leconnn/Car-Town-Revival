// Replays the transcripts made by the GDScript rules (tests/golden_scenarios.gd)
// and checks the server rules give exactly the same results and saves.
// Run with:  node --test supabase/functions/_shared/rules/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Catalog, REQUIRED_FILES } from "./catalog.ts";
import { GameLogic } from "./logic.ts";
import { runOn } from "./actions.ts";

const ROOT = join(import.meta.dirname, "..", "..", "..", "..");
const FIXTURES = join(ROOT, "tests", "fixtures");

function fixtureCatalog(withMissions = true): Catalog {
  const raw: Record<string, unknown> = {};
  for (const f of REQUIRED_FILES) raw[f] = JSON.parse(readFileSync(join(FIXTURES, "catalog", f + ".json"), "utf8"));
  const tuning = JSON.parse(readFileSync(join(FIXTURES, "tuning.json"), "utf8"));
  const cat = Catalog.fromData(raw, tuning);
  if (!withMissions) {
    cat.missions.clear();
    cat.stepsByMission.clear();
  }
  return cat;
}

const goldenDir = join(FIXTURES, "golden");
for (const file of readdirSync(goldenDir).filter((f) => f.endsWith(".json"))) {
  test(`golden transcript ${file}`, () => {
    const transcript = JSON.parse(readFileSync(join(goldenDir, file), "utf8"));
    const cat = fixtureCatalog();
    const save = GameLogic.newSave(cat, "Tester", 1_000_000);
    assert.deepEqual(save, transcript.start, "new game differs");
    const logic = new GameLogic(cat, save);
    for (const [i, step] of transcript.steps.entries()) {
      const result = runOn(logic, step.action, step.args, step.now);
      const where = `step ${i} (${step.action} ${JSON.stringify(step.args)})`;
      assert.deepEqual(result.toDict(), step.result, `${where}: result differs`);
      assert.deepEqual(logic.save, step.save, `${where}: save differs`);
    }
  });
}

test("rejects bad actions", () => {
  const cat = fixtureCatalog(false);
  const logic = new GameLogic(cat, GameLogic.newSave(cat, "T", 1_000_000));
  assert.equal(runOn(logic, "give_me_money", [], 0).ok, false);
  assert.equal(runOn(logic, "buy_car", ["1", 2, false], 0).ok, false);
  assert.equal(runOn(logic, "buy_car", [1.5, 2, false], 0).ok, false);
});
