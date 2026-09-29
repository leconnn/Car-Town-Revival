# Car Town systems inventory

What the original game contains, based on the decompiled client (`CarTownMain.swf`), the static data catalog (`All/US`) and the revival's server (`Flash.php`). See [extraction.md](extraction.md) to regenerate the source material.

Each system is tagged with a target:

- **v1**: part of the first playable release (single-player core loop)
- **Later**: planned for a post-v1 update
- **Drop**: tied to Facebook, payments or ads; not rebuilt

## How the original was built

- **Client:** Flash/AS3 on the Robotlegs MVC framework. Every user action is a *command*, UI pieces are *views* with *mediators*, and state lives in *models*. That maps cleanly onto Godot: commands become `Backend.gd` calls, mediators become scene scripts, and events become signals.
- **Server protocol:** The client sends one named call per action (`login`, `buycar`, `paintcar`, `workerassign`, `workercollect`, `missionstepincrement`, ...) with positional parameters. The client defines about 230 distinct calls. `Flash.php` implements about 120 of them, which covers the core game plus docks, racing and mystery boxes. This list is a good checklist for `Backend.gd`.
- **Static catalog:** One big XML file with every price, reward and unlock level. The client reads it at startup. Text is stored separately in a per-language string table, referenced by ID.
- **Save:** One XML document per player, returned by `login`. It holds the player record (coins, blue coins, XP, level, garage value, fuel), owned cars with installed parts, placed items and floor grids, worker tasks, missions progress, and many per-feature blocks. The revival adds JSON sidecar files for state it couldn't fit into the XML.
- **Server-side logic we don't have:** The original server calculated job payouts, race results validation, docks odds and similar rules. The client only displays the results. `Flash.php` approximates these. **We need to define these formulas ourselves** (in the shared data files).
- **Third-party libraries in the client:** Away3D (only used to project wraps and graphics onto a low-poly car model in the paint editor), Box2D (only in one game-show mini-game), GreenSock tweens, a zip reader, and the Facebook/OpenSocial SDKs.

## Catalog at a glance

| Data | Count | Notes |
|---|---|---|
| Cars | 749 | 716 have art folders. Coin price, blue-coin price, min level, class (D, C, B, A, \*), performance score, seats, limited/date availability |
| Car parts | 3,788 | 18 categories: wheels, tires, graphics, body kits, wings, hoods, headlights, taillights, plates, neon, hood accessories, tints, upgrades, paint, ride height, vanity plates, time travel, race fuel |
| Car colours | 1,973 | Per-car paint palettes |
| Garage items | 1,483 | Tile footprint (x × y), category, colour group, price, min level |
| Levels | 500 | XP needed, coin bonus, max workers (2→8), fuel tank size (5→15) |
| Land sizes | 11 | 10×10 up to 40×40 tiles, then extra floors (up to 5) gated by garage value tier |
| Worker tasks | 71 | ~45 are real garage jobs; the rest are placeholders for events |
| Task mastery levels | 4 | Bonus coins/blue coins/XP for doing the same job repeatedly |
| Missions | 87 | 42 standard, 31 tutorial, 14 daily; 139 mission steps |
| Map locations | 46 | About 10 are core town places; the rest are events and sponsors |
| Car classes | 5 | Road trip earnings per passenger |
| Road trips | 7 | Beach, Camping, Snowboarding, Las Vegas, Fishing, ... |
| Car collections | 51 | Own a set of cars → reward |
| Garage value tiers | 10 | Unlocks based on total garage value |
| Avatar items | 160 | Clothing and looks for the player's avatar |
| Daily reward entries | 75 | |

## Core systems

### Player profile and economy — v1
- **Coins** (earned by playing) and **blue coins** (premium in the original, earned-only in the remake).
- **XP and levels:** 500 levels. Each level-up gives a coin bonus and can raise the worker cap and the fuel tank size. Levels gate cars, parts, items, jobs and map locations.
- **Garage value:** Total value of owned cars and items. It is shown to the player and unlocks the top land tiers and some content.
- Constants include resell rate (10% of price), upgrade cost multipliers, vanity plate and ride height prices, and daily race limits. All of these belong in the shared data files.

### Garage (isometric game space) — v1
- The home screen: an isometric tile grid where cars park and items sit.
- **Land expansion:** 10×10 start, bought up to 40×40 with coins or blue coins, then additional floors.
- **Edit garage mode:** Place, move, rotate and store items and cars. Floors and walls are stored as grids in the save.
- **Items:** Decor, floors, walls, work bays and lifts. Work bays and lifts are where jobs happen.
- **Street in front of the garage:** Traffic drives by. Customer cars stop for jobs, and racing cars can be challenged.

### Cars — v1
- **Dealer/showroom:** Browse, filter and buy with coins or blue coins, subject to level. Limited cars have availability windows (for the remake, make them always available or rotate them).
- **Sell** for a fraction of the price.
- **Rendering:** 2D layered sprites in three views (angle, front, rear). Parts are swapped in as layers positioned by each car's `coords.xml`.
- **Waiting lists** for limited cars (deposit plus wait time): Later.

### Car customization — v1
- Paint colour from each car's palette.
- Parts: wheels, tires, body kits, wings, hoods, lights, neon, tint, hood accessories.
- Ride height, license plate and vanity plate.
- **Performance upgrades:** 5 stages. They raise the car's score, which matters for racing and jobs.
- Stickers and wraps (projected onto the 3D model): Later.

### Garage jobs (worker tasks) — v1
- **The main way to earn coins.** Put a car on a work bay and choose a job, such as Oil Change (30 min), Car Wash (5 min), Engine Tune (2 days) or Body Kit Install (3 days). Come back and collect coins and XP.
- About 45 jobs, unlocked by level. Each has a duration, coin and XP reward, and an optional blue-coin "finish now" price.
- **Mastery:** Repeating a job raises its mastery level for bonus rewards.
- **Workers:** Animated avatars who carry out jobs. The level sets the cap (2 to 8). In the original, extra workers were hired Facebook friends. For the remake, use NPC workers.
- **Customer cars** from the street (neighbours' cars in the original) can be worked on for rewards. The remake needs NPC customers.
- Timers run in real time, including while the game is closed. This needs a trusted clock in LAN and online modes.
- The payout formula was calculated server-side. We must define it ourselves.

### Fuel (energy) — Later (with street racing)
- A tank sized by level (5 to 15). One fuel is spent per race. It refills over time, and gallons can be bought.
- The remake's design calls for lighter fuel than the original: faster refills and/or a bigger tank.

### Town map (GPS) and locations — v1 (visiting only; racing comes later)
- The "town" is a GPS map. The player picks a location, and the view switches to that place. There is no free driving.
- Core locations: **Lou's Diner, Coffee Place, Tony's Pizza** (street-race hubs), **Casual Racing**, **High Stakes** (pro racing), Drive-In Movie Theatre, Junk Yard (restoration), Docks, Doc's Garage.
- Locations unlock by level and can show "new" badges.
- The rest (Ferrari, Top Gear, NASCAR Daytona, Indy, Rio, Pirelli, Game Show, BTTF lab...) are event or sponsor locations.

### Town (street) racing — Later (first update after online)
- A drag race mini-game. The start lights come down, then the player shifts through each gear. Timing each shift earns points (a perfect shift scores most). Nitrous gives bonus points, and jumping the start is a foul. Score = sum of gear points, factoring in the car's performance rating.
- At a town location, the player races other cars parked there (other players' cars in the original; NPC cars and `npc` catalog racers for the remake). The race costs 1 fuel and gives coins and XP.
- Missions rely on it heavily (see Missions).

### Missions — v1
- A mission is a set of steps. Each step listens for a game event, such as "bought car X", "collected job Y", "won a town race at location Z", "painted a car", "expanded land" or "decorated garage", and needs a count.
- Rewards: coins, XP, blue coins, and sometimes an item, car or part.
- Categories: **standard**, **tutorial** (the new-player guide), **daily** (repeatable), **sponsored** and **location**.
- Missions have date ranges and prerequisites.
- **Coverage:** 23 of the 87 missions use only v1 systems. Adding street racing raises that to 39 (15 standard, 12 tutorial, 12 daily). The others depend on post-v1 or licensed features, such as road trips, car builds, pink-slip races, NASCAR and Ghostbusters.

### Tutorial (new user flow) — v1
- Six iterations of a scripted beginner tutorial live in the client. It walks through buying a car, doing a job, visiting town and racing, and it is tracked by tutorial missions.
- For the remake, rebuild one short tutorial on top of the mission system.

### Avatar — v1 (basic), Later (shop)
- The player has a customizable character, and workers are also avatars.
- v1: A default avatar and worker animations.
- Later: The avatar clothing shop (160 items).

### HUD, popups, settings, audio — v1
- HUD with coins, blue coins, XP bar, level and garage value. Fuel is added with street racing.
- A popup queue for level-up, XP, mission-complete and errors.
- Music and sound effects with separate settings, plus a quality setting.

## Later (post-v1 features)

| System | What it is | Notes for the remake |
|---|---|---|
| **Road trips** | Send a car on a 24h trip. Earnings scale with car class and the number of passengers. | Passengers were friends. Use NPC or LAN passengers. 13 missions use this. |
| **Daily rewards** | A login streak calendar | Easy win, single-player friendly |
| **Car collections** | Own every car in a set to get a reward | 51 sets. Data only, cheap to add |
| **Glove box** | The social hub: car show, gifting, mail, sponsorship, stats, leaderboards | Mostly online features |
| **Docks** | Search shipping containers for rare cars | Well covered by `Flash.php`. Odds need defining |
| **Mystery boxes** | Spin for a random car, with respins | |
| **Car restoration** | Collect parts from the Junk Yard to restore a car | |
| **Car builds** | Multi-stage builds with a crew and "elbow grease" | Used by NASCAR, Indy, F&F and Ghostbusters builds too |
| **Trial cars / test drive** | Borrow a car for 7 days, and keep it after enough wins | |
| **Race a friend** | Async challenge races against a friend's car | LAN/online |
| **Pro racing (High Stakes)** | Bet-based races against other players | LAN/online. Min level 10, 40 wins |
| **Car show** | Players vote on cars, with prizes for top places | Online |
| **Leaderboards** | Weekly and overall rankings | Online |
| **Friends / neighbours** | Visit a friend's garage, help their cars, message them, gift them, sponsor them, hire them as workers | LAN/online |
| **Stray cars** | A random car appears and can be claimed | |
| **Avatar shop** | Buy clothing for the avatar | |
| **Stickers and wraps** | Decals projected onto the car in the paint editor | Needs the 3D projection step (`lopoly.dae`, importable by Godot) |
| **Waiting lists** | Queue with a deposit for limited cars | |
| **Take photo** | Screenshot of the garage | Could save to disk instead of Facebook |
| **Game show** | A set of mini-games with tokens | |
| **Seasonal events** | Holiday items and events | |

## Licensed events — Later (pending EA permission)

NASCAR (plus the Social Series), IndyCar, NHRA, Fast & Furious, Ghostbusters, Back to the Future time travel, Ferrari Experience, Prius, Top Gear, Car and Driver, Pirelli World Challenge, Sunoco, Ford Canada, Walmart Fast Five, Fandango, Discount Tire, Daytona tickets, Samsung and military promos. These are third-party brands licensed to the original developer, separate from the Car Town IP itself. They are planned as separate post-v1 updates if EA's permission covers them. Most need street racing or car builds first.

## Drop (not rebuilt)

- **Facebook / OpenSocial / Orkut platform code:** Login, friends lists, wall posts, invites, requests. Replaced by our own modes and accounts.
- **Payments and monetization:** Facebook Credits, blue-coin store, targeted offers, strategic discounts, TrialPay, AppSavvy, promo codes, cross-game promos, Ask.com toolbar, impression tracking and analytics logging.
