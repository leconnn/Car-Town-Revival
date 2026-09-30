# Releasing on itch.io

The game is published free on itch.io, with payments and donations turned off. It ships the original art and sounds (generated into `assets/ea/`), so builds are made locally and never committed.

## One-time setup

1. Create the game page on itch.io (see "Page settings" below). Note your user name and the page's URL slug; together they're the butler target, e.g. `yourname/car-town-revival`.
2. Install [butler](https://itch.io/docs/butler/installing.html) and run `butler login` once. Or create an API key under itch.io → Settings → API keys and put it in the `BUTLER_API_KEY` environment variable of your shell. Never write the key into a file in this repo.
3. Make sure the Godot 4.7.2 export templates are installed (Editor → Manage Export Templates).
4. Generate the data and art (`docs/extraction.md`), so `assets/ea/` is complete.

## Each release

1. Bump `config/version` in `project.godot` (LAN players on another version are refused, so every public build needs a new number).
2. Run:

   ```sh
   ITCH_TARGET=yourname/car-town-revival tools/publish_itch.sh
   ```

   It runs the tests, exports `build/windows/` (the exe, the `.pck` and `CREDITS.md`) and pushes it to the `windows` channel with the version number. The export takes 10 to 20 minutes because of the art.
3. Check the build on the itch.io dashboard, then download it through the itch app on a clean machine and play through the tutorial.

## Page settings

- **Kind of project:** Downloadable
- **Pricing:** No payments
- **Donations / "Pay what you want":** off. The project never accepts money.
- **Uploads:** the `windows` channel from butler, marked as Windows
- **Genre:** Simulation. **Tags:** cars, fan-game, garage, remake, singleplayer, local-multiplayer
- **Community:** optional. If comments are on, keep an eye on requests for the original files or accounts.

### Description (draft)

> **Car Town Revival** is an unofficial, free fan remake of Car Town, the Facebook game by Cie Games (2010–2014), rebuilt as a standalone Windows game.
>
> Run your own garage: take on customers' jobs, level up, buy and customize classic and modern cars, decorate and expand your garage, and drive around town to Lou's Diner, the Coffee Place, Tony's Pizza and the Drive-In. Missions and daily missions keep you busy, and Roxy shows you the ropes.
>
> Play on your own (3 save slots), or with friends on the same network: one player hosts a world and the others join it and visit each other's garages.
>
> Not in this version yet: street racing, the Docks, the Glove Box and online play. They're coming in later updates.
>
> This is a non-commercial fan project. It is not affiliated with or endorsed by Electronic Arts, Glu Mobile or Cie Games, who own Car Town and its art, sounds and data. It will never be sold, and it doesn't accept donations.

### Screenshots

Take them from a normal play session (the Picture button saves to `Pictures/Car Town Revival`): the garage, Buy Cars, Customize, the GPS, a town location, the missions popup.
