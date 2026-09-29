#!/usr/bin/env sh
# Deploys the online server: database schema and server functions.
# One-time setup: `npx supabase login` and `npx supabase link --project-ref <ref>`.
# See docs/online.md.
set -e
cd "$(dirname "$0")/.."
python tools/build_server_data.py
node --test supabase/functions/_shared/rules/golden.test.ts
npx supabase db push
npx supabase functions deploy act
npx supabase functions deploy account
echo "Deployed. Put the project URL and anon key in data/online.json."
