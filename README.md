# tiktokStuff

A bundle of four FiveM resources for running **TikTok LIVE–driven NPC game shows** — stream
modes where the viewers, not the players, drive what happens in-game. Likes and gifts spawn
NPCs, a cinematic auto-director films the fight, and a React overlay shows the leaderboard.

| Resource | What it is | Status |
|---|---|---|
| **[tiktokapi](tiktokapi/README.md)** | TikTok LIVE → FiveM event bridge. The foundation everything else builds on. | Working; carries debug scaffolding |
| **[lms](lms/README.md)** | *Last Man Standing* — prison-yard battle royale. **The flagship.** | Complete and TikTok-wired |
| **[actioncam](actioncam/README.md)** | Cinematic auto-director for NPC combat. Game-agnostic. | Working |
| **[tiktok](tiktok/README.md)** | Arena (Attack & Defend) + Convoy game modes. | **Incomplete** — not TikTok-wired |

---

## How they fit together

```
              TikTok LIVE
                   │
             ┌─────────────┐
             │  tiktokapi  │   Node.js ⇄ Lua bridge
             └─────────────┘   emits tiktokapi:like / :gift / :chat / ...
                   │
         ┌─────────┴─────────┐
         │                   ╎  (not wired yet)
         ▼                   ▼
   ┌───────────┐       ┌───────────┐
   │    lms    │       │  tiktok   │
   └───────────┘       └───────────┘
         │                   │
         └────────┬──────────┘
                  ▼
           ┌─────────────┐
           │  actioncam  │   AddTrackedPed / AddPedHeat
           └─────────────┘
```

`tiktokapi` and `actioncam` are **reusable infrastructure** — neither knows anything about
the other, and both are useful outside this bundle. `lms` and `tiktok` are the game modes
that sit on top.

`actioncam` is optional for both game modes: every `exports['actioncam']` call is
`pcall`-wrapped, so they degrade cleanly if it isn't running.

---

## Start here

**If you want to see it work:** run `lms`. It's the only mode that goes from a real TikTok
like to an NPC on screen with no manual steps.

```cfg
ensure actioncam
ensure tiktokapi
ensure lms
```

```
# server console
tiktok yourtiktokusername     # account must be live right now
lmsstart
```

Viewers tapping like will start spawning crews. No database, no `ox_lib`, no `oxmysql`.

**If you want to build something new:** start from `tiktokapi`'s event table and
`lms/server/server.lua`'s like-accumulator as the reference pattern — it's the shortest
complete path from a TikTok event to gameplay in this codebase.

---

## Dependency matrix

| | tiktokapi | actioncam | ox_lib | oxmysql | Node 22 |
|---|---|---|---|---|---|
| **tiktokapi** | — | | | | **yes** |
| **actioncam** | | — | | | |
| **lms** | live play | optional | | | via tiktokapi |
| **tiktok** | *not wired* | optional | **yes** | **yes** | |

`tiktokapi` declares `node_version '22'`. On an FXServer build that doesn't provide Node 22,
it will fail to start and every downstream mode loses its live event feed.

`tiktok` additionally needs [`tiktok/arena.sql`](tiktok/arena.sql) run once against the
server database before first start.

---

## Where these live on this server

`tiktokStuff/` is a **bundled copy for distribution**. The server actually loads the
resources from the category folders listed in `resources.cfg`:

| Bundle path | Live path |
|---|---|
| `tiktokStuff/tiktokapi` | `resources/[standalone]/tiktokapi` |
| `tiktokStuff/actioncam` | `resources/[standalone]/actioncam` |
| `tiktokStuff/lms` | `resources/[ntest]/lms` |
| `tiktokStuff/tiktok` | `resources/[ntest]/tiktok` |

The two trees are currently byte-identical. **Edits made in one do not propagate to the
other** — if you change a resource here, mirror it into the live path (or vice versa) before
testing, or you'll debug the copy the server isn't running.

---

## Shared design decisions

These hold across `lms` and `tiktok`, and are worth knowing before modifying either.

**Everything ped-side is client-side.** The server sends spawn payloads and receives outcome
reports; it never touches an entity. Each connected client simulates its own copy of the
arena. **This is built for a single streaming client** — with several players connected you
get several independent simulations and duplicated reports to the server.

**Kill and damage attribution is proximity-based.** When something dies, the nearest living
candidate is credited. It's approximate by design: cheap to compute and close enough to read
correctly on a stream.

**Viewers get a stable identity.** Colour and spawn zone are assigned on a viewer's first
appearance and never change for the rest of the session, so a returning viewer's crew always
enters from the same place wearing the same colour.

**Relationship groups are per-viewer.** Each viewer gets their own group, hostile to every
other viewer group and to the NPC factions, but **neutral to the player** — so the streamer
can stand in the middle of the fight and film without being shot.

**The NUI is a focusless HUD.** `SetNuiFocus(false, false)` throughout; it never takes input
except in `lms`'s explicit `/lmsedit` mode. Both overlays are React + Vite built into
`web/build/`, from the `fivem-react-boilerplate-lua` scaffold (`useNuiEvent`, `fetchNui`,
`debugData`, `SendReactMessage`).

---

## Known state of the bundle

Each resource's README has a full list. The headlines:

- **tiktokapi** — works, but ships with per-event debug logging (including a line for every
  raw protobuf message), a startup test event, example handlers that print to console, and a
  broken `tiktokapi:client:like` client handler. Clean these before production. No
  auto-reconnect.
- **lms** — complete. The one real gap is that gift handling is implemented
  (`Config.DonationTiers`, `lms:donation`) but **not connected** to `tiktokapi:gift` — only
  likes come in live.
- **actioncam** — works. `EnableConfigTool` doesn't actually gate the freecam config tool,
  and `/acamconfig` has no permission check, so set it `false` and verify before public use.
  Aerial and overview modes exist but are deliberately never auto-selected.
- **tiktok** — incomplete. Not TikTok-wired. `Config.TestMode = true` disables every
  permission check. `Config.GameMode` is never read, so arena and convoy load together.
  Convoy in particular is unfinished: one attack per viewer per run, wrecks are never cleaned
  up, and attackers earn nothing back. Teams and leaderboards exist in the database schema
  and `DB` helpers but no gameplay uses them.
