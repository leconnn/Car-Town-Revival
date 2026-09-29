import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export const JSON_HEADERS = { "Content-Type": "application/json" };

export function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

/** The signed-in user's id, or null. */
export async function userId(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const { data, error } = await client.auth.getUser();
  return error || !data.user ? null : data.user.id;
}

/** Service-role client: bypasses row level security. Server use only. */
export function admin(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
}
