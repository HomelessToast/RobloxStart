# VIP — Roblox tactical escort (slice 0)

5v5 round-based tactical shooter. Four bodyguards escort a pistol-only President to a
safe house and hold a 30-second capture; terrorists win by killing him or running out
the 300-second clock.

This repo is the Luau / Rojo source of truth. Sync into Roblox Studio with Rojo; Studio
stays the place for playtesting and publishing.

## What's playable in slice 0

One complete round loop on an urban greybox (Motorcade / Market / Consulate / Precinct):

| Feature | Status |
| --- | --- |
| `LIVE` ↔ `CAPTURE` + `ROUND_END`, 300s clock never pauses | Yes |
| Capture: 30s unbroken hold, resets to 0 on leave, entry only before t=270 | Yes |
| Win reasons: President death, President disconnect, terrorist wipe, timer expiry (incl. mid-capture), capture complete | Yes |
| Friendly fire off; server-authoritative hits; no weapon pickups | Yes |
| HUD: round timer, objective banner, capture bar, last-entry warning | Yes |
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
│   ├── server/     # Round / Capture / Objective / Combat / Map …
│   └── shared/     # GameConfig, Enums, Net, Types
└── .github/workflows/ci.yml
```

## Local setup

### 1. Install Rokit and tools

```bash
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
# Windows: irm https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | iex
rokit install
rojo plugin install   # Studio plugin (Windows / macOS)
```

### 2. Sync into Studio

```bash
rojo serve
```

In Studio: **Plugins → Rojo → Connect** (default `localhost:34872`).

Or build a place file and open it:

```bash
mkdir -p build
rojo build default.project.json --output build/game.rbxl
```

### 3. Playtest checklist (Matthew)

1. Start **two** Studio clients (local server + 1 player, or Team Test).
2. Wait for the 5s lobby countdown → round goes `LIVE`.
3. Confirm roles on the HUD (Good · President vs Terrorist).
4. **Capture win:** President reaches Consulate (A, blue) or Precinct (B, orange), stands
   on the yellow boundary for 30s without leaving.
5. **Capture break:** leave the volume mid-hold → progress resets; banner says broken.
6. **Kill win:** Terrorist shoots the President (LMB) → Terrorists win immediately.
7. **Wipe win:** President eliminates the only terrorist → Good wins.
8. **Disconnect:** stop the President client mid-round → Terrorists win.
9. **Deadline:** after the timer drops below 0:30, entering a house shows `TOO LATE` and
   does not start capture; banner switches to `ELIMINATE`.

Greybox map is spawned at runtime by `MapService` (safe houses ~800 studs apart,
Motorcade south, Market midfield, rooftops on the approach).

## Lint / build

```bash
stylua src/
selene src/
rojo build default.project.json --output build/game.rbxl
```

CI runs StyLua check, Selene, and a Rojo build smoke test on every PR.

## Design source

Authoritative rules: Project HQ `docs/vip-game-design.md` (§11 = slice 0 plan).
