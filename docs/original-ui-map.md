# How the original game is put together

This page maps how the original client's screens, menus and UI connect. It was worked out by reading the decompiled `CarTownMain.swf` and the SWF's own layout data, and it's what the remake follows so it looks and behaves like the original. Class names are the original ones, so they can be found in `_reference/` (see [extraction.md](extraction.md)).

## Stage and layers

- The game is a fixed **760 × 700** stage. The playfield is scaled and panned inside it; the UI isn't.
- The top-level layers, bottom to top:
  1. **GameBase** holds the playfield (`GameSpace`: the town backdrop, garage floor, items, cars and street), the job progress callouts, the race manager and the town transition screen.
  2. **BottomNav** sits 165 px from the bottom. It's the bottom bar: the chrome, the location tabs, the GPS button, the location label and the friends list.
  3. **CarTownControls** (y = 12) holds the top-right buttons (Picture, sound, music, quality, fullscreen, zoom in and out), the mission dock (x 40, y 220) and the indicator tray (x 40, y 104).
  4. **Hud** (y = 12) holds the level gauge (`XPGauge` with an XP odometer), the coin and blue-coin balance, the fuel gauge (x ≈ 662), the garage value meter and the Collections button.
  5. The **legacy popup container**, then the **PopupContainer** (the queued popup system) on top.
- **Zoom** has four fixed steps: 0.26, 0.4, ⅔ and 1.

## The playfield (GameSpace)

- **Isometric floor:** 50-unit squares rotated 45° and tilted 60°, so each tile is about 70.7 × 35.4 px. Tile (h, v) has its top corner at `((h − v) · 35.36, (h + v) · 17.68)`.
- **Floor objects** (items and cars) are anchored at their first tile's centre plus (−35, −17.5). Cars take 4 × 3 tiles. Rotations 0–3 use the front view (mirrored, then not) and then the rear view (mirrored, then not).
- **Town backdrop:** a green fill plus `swcassets.img.defaultBG` (a 3000 × 1910 image of the crossroads, sidewalks, parking lots and hedges). Everything hangs off an anchor at y = −1854 + 35 · max(land width, land depth), so the crossroads always meets the garage's front corner. The showroom lot (`ShowroomGround`, +2008, +1559), the showroom building (`Showroom` at ⅔ scale, +2484, +1381) and the leaderboard signpost are placed from the same anchor.
- **Default floor:** `swcassets.img.activeAreaBG`, a soft cream gradient stretched over the whole lot. Bought floor tiles use 500 × 500 textures covering 10 × 10 tiles.
- **Walls** aren't automatic. They're placeable wall-segment items.
- **Street:** traffic cars drive by. Up to **2** customer cars queue on the street along the front-left road, 170 × 85 px apart.
- **Workers** are animated avatars that walk to the work bay. A progress callout floats over each busy lift.

## Popups

- Every window is a popup in a queue, with priorities and "contexts" (whether it may show in the garage, in town, during the tutorial, and so on).
- A popup's content is wrapped in "decorators":
  - a **frame**: `UIBgFrame`, a 9-slice panel sized to the content
  - a **close button**: `IconButton.CLOSE_BUTTON` at the top-right
  - **frame buttons** centred along the bottom edge
  - **centring** on the stage, over a dimming cover
- Most screens build their content by placing named library symbols at exact coordinates and filling their text fields:
  - **Customer popup** (`CustomerCarInfo`): `CarOptionsMasthead` at (50, 20), `UITanStrokedRoundedBg` at (20, 135), the car in the angle view at (176, 327), a speech bubble (`TextBubble`), `UICustomerTaskInfo` (XP and coins) and `UICustomerTaskCost`. Start and Close are red and gray `TextButton`s.
  - **Work in Progress** (`FinishTaskNowPopup`): `FinishJobNowPopupContent`, `UICustomerTaskTitle` at (15, 81), a large progress bar at (56, 250), a gray "Stop Job" button at (355, 270), and an "Instant Finish" button with the blue-coin price.
  - **Your car** (`CarOptions`, 718 x 399 frame): masthead, the car in the angle view at 0.55 scale, Customize, Picture and Sell buttons (`BtnEdit`, `BtnPhoto`, `BtnTradeIn`), and a scroller of the car's **car tasks** (147 px apart). Each is a `UITaskSpriteGfxNew` tile: icon, title, "Done in", XP, coins, cost and a Start button; while the car is out, a progress bar and Stop. Which cars can do which task comes from the catalog's `<ctas>` table (car categories and car ids).
  - **GPS** (`GPSMain`): tabs for What's New, Hot Spots, Racing, Car Shopping and Friends, over a street-map background with location icons.
- **Customize** (`EditCar` + `EditCarPanel`) is a full screen like Buy Cars: `EditBG` with the halo, the car at (200, 390), make and model at (456, 101) and (451, 132), class and performance, and the tray with Shop / Storage tabs, a `SubTabbedStack` (708 x 144 at (26, 58)) of part categories (paint, wheels, tires, body, performance, suspension, tint, lights), a part scroller, and a green Done button at x 695. Clicking a part previews it on the car and opens `BuyConfirm` (a white 404 x 93 box at (328, -65): "Buy <name> for <cost> coins?" with OK and close). Paint opens the colour picker (`ColorPickerPanel`, a 68 x 20 grid of 5 px hue/saturation swatches and a brightness slider) in place of the sub-tabs. Performance lists the four upgrade tracks, 5 stages each; stage 5 costs blue coins.
- **Town locations** (`views/townracing/location/*TownLocation`): the environment SWF (`static/townracing/environment_*.swf`) holds `bg` (lot and ground, 3000 px), `fg` (buildings and trees drawn over cars), named parking markers (`row1Start` / `row1End` ...; each marker class sets the parked cars' rotation), and at the Drive-In a `movie` screen over a 40% night shade. Each location lists its marker rows, spot counts, point of interest and car count; cars fill the spots nearest the point of interest (`ParkCloseToPOISolver`).
- **GPS** (`GPSMain`, 720 x 550 frame): `BigGPSIconGfx`, five `GPSTab`s (What's New, Hot Spots, Racing, Car Shopping, Friends List) at x 80 + 113 n, the `NewBlueBg` map panel, location buttons five to a page (corners and centre), locked ones greyed with a big padlock, and the "My Garage" button on the panel's bottom edge when you're away. The location icon SWFs (`static/gps/locationicons/<id>.swf`) have `fldTitle` fields the game filled in.
- **Buy Cars** (`BuyCar`) isn't a popup. It replaces the playfield with the showroom: `BuyCarBG` and `BuyCarGroundHalo`, the make and model in large text at (436, 61) and (431, 92), the class badge and performance card, and `BuyCarPanel` (a car carousel with sort and search) at the bottom. Buy-with-coins and buy-with-blue buttons sit on the panel edge, with a red Back button.

## Shared widgets

- **TextButton:** a pill button (`UIIconButtonBody{Green, Yellow, Red, Blue, Gray}`, 9-slice) with a white Dom Diagonal Bold label. It grows 20% on hover (quick ease-out) and plays a rollover sound. The red button clicks with sound 2 and the others with sound 1.
- **GameButton:** wraps any symbol and grows 20% on hover.
- **StyledTextButton** (`CarTownButtonFactory.createPanelFrameButton`): the ellipse buttons on panel edges (Buy, Done): an outer ellipse, a smaller one in the main colour towards the top-left, and a stroke, 52 px tall.
- **MainTabbedStack:** the framed bottom tray of Buy Cars, Customize and Edit Garage, with icon tabs (`UITabMainBg` behind the selected one) sticking up 36 px.
- **AbstractItemScroller:** a masked row of items with `BtnScrollArrowLeft` arrows and `UIRadioButton` page dots; pages slide over in 0.5 s.
- **StoreItem:** a shop tile: `StoreItemNewIconBg` (or the locked / red "can't afford" versions), the picture, lock and clock icons, and the price or a red "Level 12" underneath.
- **Text filters:** many text fields get their outline from a glow or zero-distance drop shadow on the placement; `tools/export_ui.py` records them and `FlashText` draws them as outlines.
- **TextBubble:** a speech bubble in Dom Diagonal Bold, colour #767676, size 20, centred and wrapping at 300 px.
- **Text styles** (`locale/styles/en_US.styles.xml`): each style name maps to a font:
  - `casualA01` = Dom Diagonal Bold (all the cartoon headings and buttons)
  - `sansD01` = Swiss 721 Black Rounded (numbers)
  - `sansA01`/`A02` = Arial and Arial Bold
  - `sansB01` = Impact
  - `digitalA01` = LCD (the XP odometer)

## Flows

- **Clicking a car on the street:**
  - a customer car → the Customer popup (Start takes the job)
  - a friend's car with a job → `TaskedCarInfo`
  - any other car → `StreetCarInfo`
- **Clicking your own car** → `CarOptions`; if it's out on a car task, Work in Progress (or collect when it's back).
- **Clicking a busy lift** → Work in Progress, or collect if the job is done.
- **Location tabs** in your garage: Docks, Edit Garage, Car Shopping (Buy Cars) and Glove Box. In a friend's garage they're Race, Gift and Message.
- **The GPS button** (bottom-left) opens the GPS popup. Picking a location starts the town transition screen, then the location scene.
