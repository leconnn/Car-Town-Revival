# Online mode (Supabase)

Online play keeps each player's garage on a Supabase server. The rules run on the server, and the game only displays what the server returns.

## How it works

- **Accounts:** email and password (Supabase Auth). Players also pick a display name. Nothing else about them is stored.
- **Data:** `profiles` (display name) and `saves` (one row per player holding the whole save as JSON, in the same format as single-player). See `supabase/migrations/`.
- **Security:** Row level security lets a player *read* only their own rows. Nobody can write from the game. Every change goes through the `act` server function, which runs the same rules as the game and saves the result. The `revision` column stops two requests from overwriting each other.
- **Rules exist twice:** `scripts/rules/` (GDScript) and `supabase/functions/_shared/rules/` (TypeScript). The golden transcripts in `tests/fixtures/golden/` keep them identical:
  - `tools/run_tests.sh` checks the GDScript rules still produce the stored transcripts.
  - `node --test supabase/functions/_shared/rules/golden.test.ts` checks the TypeScript rules produce them too.
  - After an intended rule change, update both copies and regenerate the transcripts with `godot --headless --path . res://scenes/dev/make_golden.tscn`.
- **Game data on the server:** `tools/build_server_data.py` bundles the converted original data and `data/tuning.json` into `supabase/functions/_shared/catalog/data.ts` at deploy time. That file is gitignored, like all original game data.
- **Account deletion:** the in-game menu's "Delete my account" calls the `account` function. It deletes the auth user, and the database removes the profile and save automatically (`on delete cascade`).

## Setting up the project (one time)

1. Create a free project at https://supabase.com (no card needed). Free projects pause after a week without use; restore them from the dashboard.
2. In **Authentication → Providers**, keep Email on. Email confirmation is recommended.
3. Install the CLI through npx (already works with Node) and link the project:
   ```sh
   npx supabase login
   npx supabase link --project-ref <your project ref>
   ```
4. Deploy:
   ```sh
   tools/deploy_online.sh
   ```
5. Copy the project URL and the **anon** public key (Project Settings → API) into `data/online.json`. Never put the `service_role` key in the game or in Git. The server functions get it automatically from Supabase.

## Before launching online

- Publish the privacy policy (draft in `docs/PRIVACY.md`) and link it from the sign-in screen.
- Test on the real project: create account, confirm email, play, sign out/in, delete account.
