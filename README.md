# Roblox Game Repo — Phase 0 Scaffold

This repo is the source of truth for the Luau code and project structure of a Roblox
experience. [Rojo](https://rojo.space) syncs these files into the Roblox Studio DataModel on your
machine; Studio stays the place for playtesting, world/art editing, and publishing.

Genre is intentionally undecided. What ships here is a working sync skeleton plus one tiny smoke
feature (a welcome message printed on the server and shown as a HUD banner on the client) so you
can confirm the round trip repo → Studio works before any real gameplay lands.

## Repo layout

```
.
├── default.project.json   # Rojo tree: source folders → DataModel services + baseline place
├── rokit.toml             # Pinned CLI tools (rojo, selene, stylua)
├── selene.toml            # Lint config (Roblox standard library)
├── stylua.toml            # Formatter config (tabs, 100 cols)
├── src/
│   ├── client/            # → StarterPlayer.StarterPlayerScripts.Client
│   ├── server/            # → ServerScriptService.Server
│   └── shared/            # → ReplicatedStorage.Shared
└── .github/workflows/ci.yml
```

File-name suffixes decide the instance class: `*.server.luau` → `Script`,
`*.client.luau` → `LocalScript`, plain `*.luau` → `ModuleScript`.

`default.project.json` also declares a minimal baseline place (Workspace with a baseplate and spawn,
Lighting, Players, SoundService, and a `ReplicatedStorage.Remotes` folder holding the
`WelcomeMessage` RemoteEvent) so `rojo build` produces a place you can open and press Play in.

## Local setup

Everything below runs on your own machine. Cloud agents can edit this repo and run lint/build, but
they cannot run Studio or connect the sync session for you.

### 1. Install Rokit

Rokit installs and pins the CLI tools listed in `rokit.toml`, so everyone gets identical versions.

macOS / Linux:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
```

Windows (PowerShell):

```powershell
powershell -c "irm https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | iex"
```

Restart your shell afterwards so `~/.rokit/bin` is on `PATH`.

### 2. Install the pinned tools

```bash
rokit install
```

Rokit asks you to trust each tool the first time. Confirm, then verify:

```bash
rojo --version     # Rojo 7.7.0
selene --version   # selene 0.31.0
stylua --version   # stylua 2.5.2
```

### 3. Install the Rojo Studio plugin

```bash
rojo plugin install
```

That drops the plugin into Studio's local plugins folder (Windows and macOS only — it exits with
"Your platform is not currently supported" on Linux, where Studio does not run). Restart Studio if it
was already open. Alternative: install "Rojo" from the Creator Store — just keep the plugin's major
version matching the CLI's, i.e. Rojo 7.

### 4. Start a sync session

```bash
rojo serve
```

This serves `default.project.json` on `http://localhost:34872` by default.

### 5. Connect from Studio

1. Open the place you want to sync into. For a first run, use a place built from this project
   (see below) or a fresh baseplate.
2. In Studio, open the **Plugins** tab → **Rojo** → **Connect**.
3. Accept the default address/port and connect.

You should now see `ReplicatedStorage.Shared`, `ServerScriptService.Server`, and
`StarterPlayer.StarterPlayerScripts.Client` populated from `src/`.

### 6. Confirm the round trip

Press **Play** in Studio. The Output window prints two `[WelcomeService]` / `[WelcomeHud]` lines, and
a banner appears at the top of the screen naming you. Now edit the `Welcome.GameName` string in
`src/shared/Welcome.luau`, save, and watch Studio update the script without reconnecting. That edit
landing in Studio is the Phase 0 exit criterion.

## Building a place file

`rojo serve` syncs into an already-open place. `rojo build` instead writes a standalone place from
the project tree:

```bash
mkdir -p build
rojo build default.project.json --output build/game.rbxl     # binary, open this in Studio
rojo build default.project.json --output build/game.rbxlx    # XML, useful for diffing
```

Open `build/game.rbxl` in Studio for a clean starting place. Built places are gitignored — the repo,
not the `.rbxl`, is the source of truth for scripts.

## Lint and format

```bash
stylua src/            # format in place
stylua --check src/    # CI-style check, no writes
selene src/            # lint against the Roblox standard library
```

Selene downloads and caches the Roblox API standard library on first run, so the initial invocation
needs network access. The generated `roblox.toml` / `roblox.yml` is gitignored.

CI (`.github/workflows/ci.yml`) runs those three commands plus a `rojo build` smoke test on every
push to `main` and every pull request, and uploads the built place as an artifact. Nothing publishes
to Roblox from CI.

## Not included yet (on purpose)

- **Wally packages** — add `wally.toml` when a real dependency shows up, not before.
- **Publishing / Open Cloud** — Phase 0 publishing is manual from Studio. No API keys needed.
- **Roblox Studio MCP** — optional local add-on you can enable later to let an agent drive Studio
  directly. It is not required for this workflow.
- **Script Sync** — deliberately unused; Rojo owns the filesystem → Studio direction.
