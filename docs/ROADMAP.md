# Roadmap

Build order: **single-player v1 → LAN → online → feature updates**. Each phase ends with something playable or testable. See [systems-inventory.md](systems-inventory.md) for what each system does in the original.

## Decisions

1. **Town street racing comes after v1.** v1's town is the GPS map with visitable locations, but no racing. Fuel is only spent on races, so fuel also moves to after v1. As a result, about 23 of the 87 missions are playable in v1. Street racing is the first feature update after online, and it unlocks about 16 more missions.
2. **Game data: converter + overrides.** The catalog (prices, cars, jobs, levels) comes from EA's `All/US` file, so it isn't committed. A committed converter script (`tools/`) turns the catalog and string table into JSON in `assets/ea/data/` (gitignored). Only our own tuning overrides go in `data/`, such as the job payout formula and blue-coin rewards. The game loads EA data first, then applies the overrides. For online, the server functions get the same generated JSON at deploy time, not from Git.
3. **Licensed event content is kept for later.** NASCAR, IndyCar, NHRA, Ferrari, Fast & Furious, Ghostbusters, Back to the Future, Top Gear, Prius and similar events are planned as post-v1 updates. They depend on the EA permission reply, and some also need street racing or car builds first. Their cars can appear in the dealer like any other car, subject to the same permission.

## Status (September 2026)

| Phase | State |
|---|---|
| 0 Foundations | Done: Godot 4.7.2 project, `Backend` interface, saves with migrations, data converter, art/audio exporter, gdUnit4 tests |
| 1 Garage | Done: isometric garage, items, edit mode (the original tray, storage, sell, reset floor, hover rotate button), land expansion, floors and walls. *Missing:* wall decorations (posters), extra floors |
| 2 Cars | Done: Buy Cars and Customize screens rebuilt from the original, rendering from original layers, any-colour paint (the original colour picker), parts, the four upgrade tracks (engine, handling, aerodynamics, weight; 5 stages each), ride height, plates, neon, tint. *Missing:* custom graphics (decals), parts storage |
| 3 Jobs | Done: the original Service Menu on an empty lift (the job gets a random factory car, like the original), real-time jobs, mastery, customers, levels, sounds, the floating coins and XP on collect, car tasks (Deliver Pizza and the truck routes, started from your own car). *Missing:* animated worker avatars; cars out on a task stay parked with a callout instead of driving into town |
| 4 Town | Done: the original GPS popup (tabs, location buttons, access-denied popup) and the four hangouts (Lou's Diner, Coffee Place, Tony's Pizza, Drive-In) rebuilt as full scenes with cars parked in their marked spots. Racing and the Junk Yard show as locked until their updates |
| 5 Missions | Done: missions, daily missions, Rusty's tutorial |
| 6 Release | Windows export works; title screen, menu, settings and credits rebuilt in the original style. Publishing on itch.io before EA replies is approved (free, no donations). *Waiting on:* the itch.io page and a butler API key |
| 7 LAN | Done: host/join, auto-discovery, version check, guests saved in the host's world, visiting garages from the friend list (the GPS brings you home) |
| 8 Online | Built and parity-tested, *not deployed*: needs a Supabase project, and the privacy policy needs filling in |

## Phase 0: Foundations

- Pick and pin the Godot 4.x version. Create the project skeleton: `scenes/`, `scripts/`, `data/`, `tests/`, gdUnit4.
- `Backend.gd` autoload interface and `LocalBackend` with 3 save slots.
- Save format v1 with `save_version`, a step-by-step migration runner, and tests.
- **Data pipeline:** Catalog + en_US strings → typed JSON (cars, parts, colours, items, levels, lands, jobs, missions, locations, constants). Add a GDScript loader and tests that check the data loads.
- **Art pipeline:** FFDec export of car views (angle/front/rear layers + `coords.xml`), wheels, garage items, UI and avatar parts to PNG at 2x into `assets/ea/`. Start with ~20 cars and ~50 items to prove it. Document the commands in `docs/extraction.md`.
- **Content filter:** A list of which cars, items and jobs are in v1. Event-only content is hidden until its feature update ships.
- `CREDITS.md`.

**Done when:** The Godot project opens, loads the catalog, shows one car sprite built from its layers, and saves/loads an empty profile.

## Phase 1: Garage

- Isometric tile renderer, camera pan/zoom, and a resizable 16:9 window with fullscreen.
- Starting land (10×10) with default floor and walls.
- Edit garage mode: place, move, rotate and store items with footprint collision.
- Land expansion (buy the next size).
- HUD: coins, blue coins, XP bar, level, garage value. Fuel is added with street racing.

**Done when:** A new profile starts in an empty garage that the player can decorate and expand, and it persists across restarts.

## Phase 2: Cars

- Car rendering from layers in all three views, with wheels and parts at their coordinates.
- Dealer: browse and filter, buy with coins or blue coins, level gating, and park the car in the garage.
- Sell a car.
- Customization screen: paint, wheels, tires, body kits, wings, hoods, lights, neon, tint, plate, and ride height.
- Performance upgrades (5 stages) affecting car score.
- Garage value calculation.

**Done when:** The player can buy a car, customize it, see it in the garage, and sell it. All prices come from data.

## Phase 3: Garage jobs and progression

- Work bays and lifts as placeable items.
- Assign a job to a car on a bay, with a real-time timer that continues while the game is closed. Collect for coins and XP.
- **Define the job payout formula** (the original's was server-side). Put it in `data/`, with tests.
- Job mastery levels, and blue-coin "finish now".
- NPC workers: animated avatars walking to bays, with the level-based worker cap.
- Customer cars: NPC cars drive by and stop for jobs.
- XP, level-ups (bonus coins, higher caps), and the level-up popup.
- Popup queue, and basic music and sound effects.

**Done when:** The core earning loop works (buy car → do jobs → earn → level up → buy more), and the game rules have unit tests.

## Phase 4: Town

- GPS map screen with core locations, level unlocks and "new" badges.
- Location scenes for Lou's Diner, Coffee Place and Tony's Pizza. The player can visit them (this counts for "went to location" mission steps), but there's no racing yet.
- Build the map and location framework so that street racing, the Junk Yard, the Docks and event locations can plug in later.

**Done when:** The player can open the map, travel to the unlocked locations and return to the garage.

## Phase 5: Missions and tutorial

- Mission engine: a game-event bus (bought car, collected job, won race at location, painted car, expanded land, ...), step counters and rewards.
- Enable the ~23 missions that use v1 systems. The engine must skip missions whose features aren't built yet and turn them on automatically when those features ship.
- Mission UI: dock/icons, status popup and complete popup.
- New-player tutorial built on tutorial missions: first car, first job, first decoration, first map visit.

**Done when:** A fresh player is guided through the loop and always has goals to work on.

## Phase 6: v1 release (single-player)

- Balance pass on the economy (blue coins earned through play only).
- Settings: audio, quality and fullscreen. Credits screen.
- Save robustness: autosave, corruption fallback and migration tests.
- Windows export, itch.io page (free, payments off), `butler` upload.

**Done when:** v1.0 is on itch.io.

## Phase 7: LAN

- `LanBackend`: host runs the rules, guests send actions as RPCs (Godot ENet).
- Join by IP and LAN discovery, with the version check message.
- 3 world slots per host, and guest progress stored per guest in the host's world.
- Shared town: visit other players' garages. Racing their parked cars comes with the street racing update.
- Host clock is authoritative for job timers.

## Phase 8: Online

- Supabase project, email login + display name, account deletion, and the privacy policy.
- `OnlineBackend`. One save row per player that the client can only read. All purchases and rewards go through server functions (TypeScript ports of the same data-driven rules).
- Server clock for job timers.
- First online-only features: friends list, visit a friend's garage, leaderboards.

## Feature updates (after online, roughly by value vs. effort)

1. **Street racing and fuel.** This is the drag-race mini-game at Diner, Coffee Place and Tony's Pizza against NPC cars (and players' cars in LAN/online).
   - Mechanics: start lights, shift timing per gear, perfect shifts, nitrous, fouls, and scoring that uses the car's performance rating.
   - Fuel: level-based tank, timed refill (lighter than the original), and 1 fuel per race. Race rewards come with a daily race limit.
   - This unlocks about 16 more missions.
2. Daily rewards, car collections (data-driven, cheap)
3. Road trips (NPC passengers offline, real passengers LAN/online)
4. Glove box: mail, gifting, stats
5. Avatar shop
6. Docks
7. Mystery boxes, stray cars
8. Car restoration (Junk Yard)
9. Car builds
10. Race a friend, pro racing (High Stakes)
11. Car show voting
12. Stickers and wraps (3D projection onto `lopoly.dae`)
13. Trial cars, waiting lists, seasonal events
14. **Licensed events, pending EA permission.** Each one is a separate update. They need street racing and/or car builds first.
    - NASCAR and Social Series, IndyCar, NHRA
    - Fast & Furious, Ghostbusters, Back to the Future time travel
    - Ferrari Experience, Top Gear, Prius, Pirelli World Challenge
    - Smaller promos
