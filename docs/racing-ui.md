# Street racing: UI plan

The rules are done and tested (`scripts/rules/game_logic.gd`, "Street racing and fuel"; the TypeScript copy matches). This is what's left to build on screen, and how the original did it. Original classes are in `_reference/CarTownMain/scripts/scripts/com/ciegames/cartown/` (decompiled, local only).

## Rules API (already in `Backend`)

| Call | What it does |
|---|---|
| `Backend.query().race_locations()` | Hangouts with racing: 9, 7, 6, 8 (tuning `racing.locations`) |
| `Backend.query().race_opponents(location_id, now)` | The 6 cars waiting there this hour: `{index, car_id, color_id, power, name}` |
| `Backend.query().race_prize(power)` | `{coins, xp}` for beating a car of that power (show it on the car info popup) |
| `Backend.query().fuel(now)`, `fuel_tank()`, `fuel_refill_seconds()`, `save.player.fuel_at` | Fuel for the HUD gauge and "next gallon in m:ss" |
| `Backend.start_race(location_id, index, car_uid)` | Spends a gallon; returns `{opponent, opponent_score}`. Fails with "You're out of fuel." |
| `Backend.finish_race(score, perfect_shifts, redlined)` | Returns `{win, score, opponent_score, coins, xp}`; mission notices come through as usual |
| `Backend.buy_fuel(consumable_id)` | Cans 3, 4, 5 (3, 7, 12 gallons) and 6 (full refill), blue coins |

## Screens, in play order

1. **Parked cars at a hangout are clickable** (`LocationView` already parks cars; switch it to `race_opponents()` so the parked cars *are* the opponents, spot i = opponent i). Hover shows `TownRacingRollOverCarInfo` (name, power, coin prize).
2. **Car info popup** (`views/townracing/location/dialog/TownRacingCarInfoPopup`): the opponent's car, owner name, power (`UIPerformanceIconAsset`), prize coins and XP, the Street Challenge logo (`UIStreetChallengeLogo`), Race / Cancel. Race with no fuel opens **AskForMoreFuelPopup** → **TownRacingBuyMoreFuelPopup** / `BuyFuelStore` (the fuel cans).
3. **Pick your car** (`TownRacingSelectCarPopup` + `carpicker/TownRacingSelectCarPicker`): your cars sorted by performance, prize shown again. Choosing one calls `start_race`.
4. **Race page** (`views/townracing/racing/TownRacingPage`, `TownRaceView`, `TownRacingPageBottomPanel`): both cars side by side on the street, your score and theirs, and the shift control at the bottom. The opponent's car advances using `RacingScoreInterpolator` (it animates the opponent's known score over the race, shift by shift, using `TownRacingHelper.getOpponent*Time`).
5. **Results** (`dialogs/TownRacingYouWinDialog` / `TownRacingYouLoseDialog`, `AbstractTownRacingRaceResultsDialog`): both names, scores (or "Foul"), coins and XP earned, OK. Call `finish_race` when the race ends and show its result here.
6. **HUD fuel gauge**: `UIEnergyFuelGaugeGfx` is already drawn under the level gauge (it currently shows placeholder bars). Fill it from `fuel()` / `fuel_tank()`; clicking it opens the fuel store.

First race: the original showed `TownRacingHowToPlayDemo` and, when nitrous first appears, `TownRacingHowToUseNitrousPopup`. Remember "seen" in `Settings` like `missions_seen`.

## The shift control (client side, from `views/racing/shiftcontrol/AbstractShiftControl` and `AbstractRaceRules`)

Art: `ShiftGauge` (needle, `BtnGo` button with a text field), `Lights` (`LightsYellowBmd` ×3 then `LightsGreenBmd`), `NosControl` (`NosControlAsset`). Sounds: yellow light `LightsYellowSound`, green `LightsGreenSound`, perfect `SuccessSound2`, bonus `SuccessSound1`, normal shift `ApprovalSound`, redline `ActionDeniedSound`, foul `JobExpiredSound`.

- `power` = the car's performance (`car_score`). **Throttle time** = `2000 + 2 * max(0, 1000 - power)` ms: how long the needle takes to sweep 360°.
- Press **Ready** → wait `1500 + random(0..1500)` ms → light 1 (yellow), then lights 2, 3 at +500, +1000 ms and **green at +1500 ms**. The clock starts at light 1.
- **Launch** (first click, "Go"): `t` = ms since light 1.
  - `t < 1500` → **foul**: score `-power`, race over.
  - bonus if `t < 1550`: points = `power * (2 if bonus else 1) * (1 - min(1, (t - 1500) / 1000))`.
- After the launch the needle climbs: `rotation = min(0.95, elapsed / throttle) * 360` degrees.
- **Shifts** (three more clicks, gears 1→2→3→4) at needle angle `a`:
  - `a < 241` → normal: `round(power * a / 244)`
  - `241 ≤ a ≤ 247` → perfect/bonus: `round(2 * power * (244 - |244 - a|) / 244)` ("Perfect!" when it equals `2 * power`; count these as perfect shifts)
  - `a > 247` → **redline**: `-round(power * (a - 247) / (342 - 247))`, and the race counts as redlined
- After each shift the needle drops back to 0 over 200 ms, then climbs again.
- **Nitrous**: clicking the NOS control adds 50 to the next shift (`nitrous_per_shift`).
- The race ends 1350 ms after the last shift. Total = launch + three shifts (+ nitrous). Send it with the number of perfect shifts and whether any shift redlined.
- **Practice** mode is the same without `start_race`/`finish_race`.

## Tests to keep passing

`tools/run_tests.sh`, `node --test supabase/functions/_shared/rules/golden.test.ts`, and a screenshot pass with `-- open=location_9` (add `open=race` for the race page).
