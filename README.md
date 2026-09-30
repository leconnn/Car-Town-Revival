# Car Town Revival

An unofficial fan remake of **Car Town**, the 2010 Facebook game by Cie Games, as a standalone desktop game. It's free and will never be monetized.

> Car Town belongs to Electronic Arts (via Glu Mobile / Cie Games). This project isn't affiliated with or endorsed by them. The game uses the original art, sounds and data, but **none of that is in this repository**. You need your own copy of the original files to build it.

## Status

Early development, Windows first. See [docs/ROADMAP.md](docs/ROADMAP.md) for the plan and [docs/systems-inventory.md](docs/systems-inventory.md) for everything the original game had.

Playable so far, with the original UI rebuilt screen by screen:
- Your garage: decorate it in Edit Garage, expand it, change floors and walls
- Buy Cars with the original cars, colours and parts
- Customize: any paint colour, wheels, tires, body kits, wings, hoods, neon, tint, the four performance upgrades, ride height and plates
- Work bay jobs from the Service Menu, customers who drive up to your garage, car tasks, real-time timers, mastery and levels
- Missions and daily missions, and Roxy's tutorial
- The GPS and four places in town: Lou's Diner, the Coffee Place, Tony's Pizza and the Drive-In
- LAN play: host a world or join one on your network, and visit other players' garages from the friend list

Releases go on itch.io, free: see [docs/release.md](docs/release.md).

## Building

1. Get [Godot 4.7.2](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) (standard version, not .NET).
2. Put a copy of the original revival files in `alt/` at the repo root.
3. Follow [docs/extraction.md](docs/extraction.md) to generate the game data and art into `assets/ea/`.
4. Open the folder in Godot and press Play.

Tests use [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4): run `tools/run_tests.sh`.

## Project layout

| Folder | What's in it |
|---|---|
| `scripts/rules/` | The game rules (`GameLogic`): prices, jobs, missions, levels. No UI or files. |
| `scripts/backend/`, `scripts/autoload/backend.gd` | The single interface every game action goes through, with single-player, LAN and (later) online implementations |
| `scripts/view/` | Garage, car and item rendering |
| `scripts/ui/` | The HUD, popups and screens, rebuilt from the original's UI symbols (`scripts/ui/flash/`) |
| `data/tuning.json` | Our balance changes on top of the original numbers |
| `tools/` | Scripts that convert the original files |
| `tests/` | Unit tests with a small invented catalog |
| `assets/ea/` | Generated from the original files. **Gitignored, never committed.** |

## Credits

See [CREDITS.md](CREDITS.md).
