# VIP — Roblox tactical escort (slice 0)

5v5 round-based tactical shooter. Four bodyguards escort a pistol-only President to a
safe house and hold a 30-second capture; terrorists win by killing him or running out
the 300-second clock.

This repo is the Luau / Rojo source of truth. Sync into Roblox Studio with Rojo; Studio
stays the place for playtesting and publishing.

## What's playable in slice 0

One complete **best-of-7 match** loop on a **metric-correct** urban greybox (Motorcade /
Market / Consulate / Precinct):

| Feature | Status |
| --- | --- |
| `LIVE` ↔ `CAPTURE` + `ROUND_END` / `INTERMISSION` / `MATCH_END`, 300s clock never pauses | Yes |
| Capture: 30s unbroken hold, resets to 0 on leave, entry only before t=270 | Yes |
| Win reasons: President death, President disconnect, terrorist wipe, timer expiry (incl. mid-capture), capture complete | Yes |
| Round over → teleport to Day/Night lobby pad; match over → clear scores → lobby queue | Yes |
| Best of 7 (first to 4), sides alternate every round, HUD score + swap announce | Yes |
| President: solo Good → that player; else rotate by UserId within the Good team | Yes |
| Friendly fire off; server-authoritative hits; no weapon pickups | Yes |
| BUY phase (20s) + buy menu; US/RU arsenals; armor damage pool; cash economy | Yes |
| HUD: round timer, score, cash, armor, objective banner, capture bar | Yes |
| Metric greybox from `MapMetrics` + `MapService` (git-tracked Parts builder) | Yes |
| Roll ability, utility nades | Deferred |

Match start is **not** automatic on join — players spawn on the elevated **VIP briefing
lobby** (south/above the city). Stand in a **Day** or **Night** ready pad with **2–10**
players to arm that mode’s 5s countdown. Roster splits into persistent Team A / Team B;
round 1 seats A=Good / B=Terrorist, then sides swap every round. Between rounds everyone
returns to the armed ready pad for intermission, then auto-continues. After a team reaches
4 wins, match end clears the scoreboard for a fresh queue.

### President assignment

- If only **one** player is on the Good/VIP side, they are President.
- Otherwise the Good side rotates the role by stable `UserId` order (per-team cursor in
  `MatchService`), so each team shares President duty across the bo7.

## Repo layout

```
.
├── default.project.json
├── rokit.toml
├── src/
│   ├── client/     # HudController, InputController, BuyMenuController
│   ├── server/     # Round / Match / Lobby / Buy / Economy / Combat / Weapon / Map …
│   └── shared/     # GameConfig, WeaponDefs, Ballistics, MapMetrics, Enums, Net
└── .github/workflows/ci.yml
```

Economy & roster decisions: Project HQ `docs/vip-economy-weapons.md`.

## Map metrics (measured path ribbons)

Anchors and path lengths live in `src/shared/MapMetrics.luau`. `MapValidator` prints
this report at server start (also stored on `Workspace.VIPMap.MapMetricsReport`).

| Ribbon | Target | Band | Measured |
| --- | ---: | --- | ---: |
| Consulate ↔ Precinct (`A_to_B`) | 1000 | 950–1100 | **1018** |
| Motorcade → Consulate (`Good_to_A`) | 650 | 585–715 | **631** |
| Motorcade → Precinct (`Good_to_B`) | 650 | 585–715 | **631** |
| Market → Consulate (`Terror_to_A`) | 500 | 450–550 | **512** |
| Market → Precinct (`Terror_to_B`) | 500 | 450–550 | **512** |
| Motorcade → Market (`Good_to_Terror`) | 450 | 400–520 | **450** |

Straight-line Consulate↔Precinct = **770** studs (urban massing forces the longer
southern arterial). Contest radius **R = 22 × 30 = 660**. Yellow neon
`CaptureBoundary` marks each volume; `MapAnchor` tags name Motorcade / Market /
Consulate / Precinct.

### Layout philosophy (city-first greybox)

Metric distances above are unchanged. Massing follows a **real city grid** hierarchy
(roads → blocks → alleys), then perimeter + discrete snipes:

1. **Road grid first** — orthogonal N–S / E–W asphalt **per block face** (**32-stud**
   primary width) on ~**100-stud** centerlines (`VIPMap.UrbanMassing.RoadNetwork`).
   Asphalt + curb lips stop at parcel/junction edges; dashed center marks only on
   open street faces — no neon/curb ribbons piercing towers. Metric path corridors
   stay reserved for contest timing without diagonal road stamps through buildings.
2. **Blocks between roads** — varied skyline heights fill parcels **inset** from
   road edges (~68-stud footprints): low mid-rise **28–44**, mid **48–72**, tall
   **76–96**, tower **100–116**, plus one **SW corner landmark** at **140** studs
   (`LandmarkCornerSW` near (−350, −450)) with a climbable sniper perch.
3. **Alleys** — narrower (**12-stud**) secondary cuts as costly bypasses.
4. **Spawns on roads** — Motorcade / Market sit on X=0 intersections. Exactly **one**
   greybox mass (`TerrorSpawnLOSBlocker` at `(0, -145)`) sits south of Market so there
   is no direct round-start LOS to Motorcade; flanks use adjacent streets.
5. **Perimeter walls** — ~148-stud city facade / skyline walls seal the arena
   (`VIPMap.Perimeter`).
6. **Discrete ladder snipes** — TrussPart climbs on **elevated parcel outliers**
   (taller than local neighbors by ≥16 studs, capped), four approach vantages, and
   the SW landmark perch. Isolated rooftop decks only — no continuous rooftop
   rotate (§7.5).

Art is still colored Parts only — modular dress is deferred until these metrics
pass playtest. Weapons + economy are live (`WeaponDefs` / `GameConfig.Economy`);
match flow (bo7 + side swap) lives in `MatchService` / `RoundService`.

## Local setup

### 1. Install Rokit and tools

```bash
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
# Windows: irm https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | iex
rokit install
rojo plugin install   # Studio plugin (Windows / macOS)
```

### 2. Sync into Studio (required — the map is not in a published place by default)

From the repo root on the machine that has Studio:

```bash
git checkout cursor/vip-slice-0-33b0
git pull
rojo serve
```

Then in Roblox Studio:

1. Open **any** empty Baseplate (or File → New).
2. **Plugins → Rojo → Connect** → `localhost:34872` (project name **VIP**).
3. Confirm Explorer shows `ServerScriptService.Server.Bootstrap` and a large asphalt
   `Workspace.Baseplate` (~1000×800). If those are missing, you are not synced.
4. Press **Play** (F5) — not just open the place. The greybox is built by the
   **server** on start (`Bootstrap` → `MapService.build` → `LobbyService.build`).
   Edit mode only has the baseplate + spawn pad until Play runs.
5. You should **spawn on the elevated VIP lobby** (south of the city, high above),
   see the greybox **below and north in the distance**, with **Night** (blue, west)
   and **Day** (gold, east) ready pads. Output must show
   `[MapService] Metric VIP greybox built`, `[MapValidator] PASS`, and
   `[LobbyService] VIP briefing deck…`.

Solo Play is enough to **see** the map from the lobby. A round still needs **2 players**
standing together in the same ready pad.

### Lobby → match (quick test)

1. Start **two** Studio clients (local server + players, or Team Test).
2. Both join → land on the briefing deck (not Motorcade).
3. Walk into the same ready pad (**Night** = evening streetlights, **Day** = bright sun).
4. When **2+** are in that pad (max **10** teleported), a 5s countdown arms that mode.
5. On go: those players teleport to Motorcade / Market; Day matches flip `Lighting` to
   daytime; Night keeps the existing evening mood. After round end, everyone returns
   to the lobby and evening lighting is restored.

Or build a place file and open it (still press Play):

```bash
mkdir -p build
rojo build default.project.json --output build/game.rbxl
```

### 3. Playtest checklist (Matthew)

1. Follow §2 (serve → Connect → Play) so `Workspace.VIPMap` **and** `Workspace.VIPLobby` exist.
2. Start **two** Studio clients (local server + 1 player, or Team Test) for a round.
3. Confirm both spawn on the elevated lobby (city visible below/north), not Motorcade.
4. Both stand in **Night** ready pad → 5s countdown → `LIVE` with evening streetlights.
5. (Optional) After round end, return to lobby; both stand in **Day** pad → `LIVE` with
   bright daytime Lighting; after round end, lobby evening mood restores.
6. Confirm roles on the HUD (Good · President vs Terrorist).
7. Confirm Output shows `[MapValidator] PASS` and the path report (city metrics unchanged).
8. Walk the yellow path ribbons: A↔B should feel ~45s sprint; houses are Consulate
   (blue, west) and Precinct (orange, east).
9. **Capture win:** President stands inside a green capture volume / yellow boundary
   for 30s without leaving.
10. **Capture break:** leave the volume mid-hold → progress resets; banner says broken.
11. **Kill win:** Terrorist shoots the President (LMB) → Terrorists win immediately.
12. **Wipe win:** President eliminates the only terrorist → Good wins.
13. **Disconnect:** stop the President client mid-round → Terrorists win.
14. **Deadline:** after the timer drops below 0:30, entering a house shows `TOO LATE`
    and does not start capture; banner switches to `ELIMINATE`.
15. Spot-check: no lethal falls on stair/rooftop approaches; alleys act as
    costly bypasses vs primary roads; Market mid-avenue has one LOS island only
    (no floating choke slabs / arcade / MidCover barriers in the street).

## Lint / build

```bash
stylua src/
selene src/
rojo build default.project.json --output build/game.rbxl
```

CI runs StyLua check, Selene, and a Rojo build smoke test on every PR.

## Design source

Authoritative rules: Project HQ `docs/vip-game-design.md` (§7 map math, §11 = slice 0
plan). World-gen path: `docs/vip-world-generation-strategy.md` (approved — agent-driven
hybrid).
