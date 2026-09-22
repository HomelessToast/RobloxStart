# VIP — Roblox tactical escort (slice 0)

5v5 round-based tactical shooter. Four bodyguards escort a pistol-only President to a
safe house and hold a 30-second capture; terrorists win by killing him or running out
the 300-second clock.

This repo is the Luau / Rojo source of truth. Sync into Roblox Studio with Rojo; Studio
stays the place for playtesting and publishing.

## What's playable in slice 0

One complete round loop on a **metric-correct** urban greybox (Motorcade / Market /
Consulate / Precinct):

| Feature | Status |
| --- | --- |
| `LIVE` ↔ `CAPTURE` + `ROUND_END`, 300s clock never pauses | Yes |
| Capture: 30s unbroken hold, resets to 0 on leave, entry only before t=270 | Yes |
| Win reasons: President death, President disconnect, terrorist wipe, timer expiry (incl. mid-capture), capture complete | Yes |
| Friendly fire off; server-authoritative hits; no weapon pickups | Yes |
| HUD: round timer, objective banner, capture bar, last-entry warning | Yes |
| Metric greybox from `MapMetrics` + `MapService` (git-tracked Parts builder) | Yes |
| Best of 7, side swap, economy / buy, roll ability, full arsenal | Deferred (slices 1–3) |

Rounds loop forever after a short lobby. With 2 players: lowest `UserId` is President
(Good), the other is Terrorist. Extra players fill bodyguards then terrorists.

## Repo layout

```
.
├── default.project.json
├── rokit.toml
├── src/
│   ├── client/     # HudController, InputController
│   ├── server/     # Round / Capture / Objective / Combat / Map / MapValidator …
│   └── shared/     # GameConfig, MapMetrics, Enums, Net, Types
└── .github/workflows/ci.yml
```

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

Art is colored Parts only — modular dress is deferred until these metrics pass
playtest.

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
   **server** on start (`Bootstrap` → `MapService.build`). Edit mode only has the
   baseplate + spawn pad until Play runs.
5. You should land at the Motorcade (south) and see urban massing, yellow path
   ribbons, Consulate (blue/west) and Precinct (orange/east). Output must show
   `[MapService] Metric VIP greybox built` and `[MapValidator] PASS`.

Solo Play is enough to **see** the map. A round still needs **2 players**.

Or build a place file and open it (still press Play):

```bash
mkdir -p build
rojo build default.project.json --output build/game.rbxl
```

### 3. Playtest checklist (Matthew)

1. Follow §2 (serve → Connect → Play) so `Workspace.VIPMap` exists.
2. Start **two** Studio clients (local server + 1 player, or Team Test) for a round.
3. Wait for the 5s lobby countdown → round goes `LIVE`.
4. Confirm roles on the HUD (Good · President vs Terrorist).
5. Confirm Output shows `[MapValidator] PASS` and the path report.
6. Walk the yellow path ribbons: A↔B should feel ~45s sprint; houses are Consulate
   (blue, west) and Precinct (orange, east).
7. **Capture win:** President stands inside a green capture volume / yellow boundary
   for 30s without leaving.
8. **Capture break:** leave the volume mid-hold → progress resets; banner says broken.
9. **Kill win:** Terrorist shoots the President (LMB) → Terrorists win immediately.
10. **Wipe win:** President eliminates the only terrorist → Good wins.
11. **Disconnect:** stop the President client mid-round → Terrorists win.
12. **Deadline:** after the timer drops below 0:30, entering a house shows `TOO LATE`
    and does not start capture; banner switches to `ELIMINATE`.
13. Spot-check: no lethal falls on stair/rooftop approaches; chokes have neon bypass
    markers; arcade near Motorcade provides overhead cover.

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
