// Runs one game action for the signed-in player, with the same rules as the
// game (supabase/functions/_shared/rules). The client never writes its save.
//
// POST {"action": "start", "display_name": "..."}  create the player's save
// POST {"action": "state"}                          current save
// POST {"action": "<game action>", "args": [...]}   see rules/actions.ts
// Reply: {"result": {...}, "state": {...}, "now": unix seconds}
import { admin, reply, userId } from "../_shared/auth.ts";
import { catalog, migrate } from "../_shared/game.ts";
import { GameLogic, GameResult } from "../_shared/rules/logic.ts";
import { runOn } from "../_shared/rules/actions.ts";

const MAX_RETRIES = 3;

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "POST only" }, 405);
  const uid = await userId(req);
  if (!uid) return reply({ error: "not_signed_in" }, 401);
  let body: { action?: string; args?: unknown[]; display_name?: string };
  try {
    body = await req.json();
  } catch {
    return reply({ error: "bad_json" }, 400);
  }
  const db = admin();
  const now = Math.floor(Date.now() / 1000);

  if (body.action === "start") {
    const name = String(body.display_name ?? "").trim();
    if (name.length < 1 || name.length > 20) return reply({ error: "Names are 1 to 20 characters." }, 400);
    const existing = await db.from("saves").select("user_id").eq("user_id", uid).maybeSingle();
    if (existing.data) return reply({ error: "already_started" }, 409);
    const save = GameLogic.newSave(catalog(), name, now);
    const p = await db.from("profiles").insert({ user_id: uid, display_name: name });
    if (p.error) return reply({ error: p.error.message }, 500);
    const s = await db.from("saves").insert({ user_id: uid, save_version: save.save_version, data: save });
    if (s.error) return reply({ error: s.error.message }, 500);
    return reply({ result: GameResult.success().toDict(), state: save, now });
  }

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    const row = await db.from("saves").select("data, revision").eq("user_id", uid).maybeSingle();
    if (row.error) return reply({ error: row.error.message }, 500);
    if (!row.data) return reply({ error: "no_save" }, 404);
    const save = migrate(row.data.data);
    if (!save) return reply({ error: "This save can't be read by this server version." }, 409);
    if (body.action === "state") {
      return reply({ result: GameResult.success().toDict(), state: save, now });
    }
    const logic = new GameLogic(catalog(), save);
    const result = runOn(logic, String(body.action ?? ""), body.args ?? [], now);
    if (!result.ok) return reply({ result: result.toDict(), state: row.data.data, now });
    // Only write if nobody else changed the save since we read it.
    const upd = await db.from("saves")
      .update({
        data: logic.save,
        save_version: logic.save.save_version,
        revision: row.data.revision + 1,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", uid).eq("revision", row.data.revision).select("user_id");
    if (upd.error) return reply({ error: upd.error.message }, 500);
    if (upd.data && upd.data.length === 1) return reply({ result: result.toDict(), state: logic.save, now });
  }
  return reply({ error: "busy, try again" }, 409);
});
