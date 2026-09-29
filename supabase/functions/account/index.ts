// Account management for the signed-in player.
// POST {"action": "delete"}  deletes the account and all its data.
import { admin, reply, userId } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "POST only" }, 405);
  const uid = await userId(req);
  if (!uid) return reply({ error: "not_signed_in" }, 401);
  const body = await req.json().catch(() => ({}));
  if (body.action !== "delete") return reply({ error: "unknown action" }, 400);
  // Profiles and saves are removed by "on delete cascade".
  const { error } = await admin().auth.admin.deleteUser(uid);
  if (error) return reply({ error: error.message }, 500);
  return reply({ deleted: true });
});
