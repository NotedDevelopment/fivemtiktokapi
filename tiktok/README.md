# tiktok — Arena (Attack & Defend) + Convoy

Two TikTok-driven NPC game modes sharing one resource:

- **Arena** — viewers spend points to send waves of attackers at a fortified defender line at
  the Sandy Shores airfield. Wipe the defenders and your crew *becomes* the defenders for the
  next challenger.
- **Convoy** — a VIP vehicle with police escorts drives across the map; viewers spend points
  to spawn carloads of hostile NPCs to intercept it.

> ### Status: incomplete
>
> Neither mode is finished. Arena is the further along of the two and is playable
> end-to-end via commands, but **neither is connected to TikTok** — the `arena:processLike`
> and `arena:processGift` handlers are stubs that nothing calls from
> [`tiktokapi`](../tiktokapi/README.md). Convoy in particular has significant unfinished
> behaviour. See [Known gaps](#known-gaps) for the full list before building on this.
>
> For a finished, TikTok-wired example of the same general idea, see
> [`lms`](../lms/README.md).

---

## Install

```cfg
ensure ox_lib
ensure oxmysql
ensure actioncam     # optional
ensure tiktok
```

**Dependencies**

| Resource | Required? | Used for |
|---|---|---|
| `ox_lib` | **Yes** | Notifications and the `/testmenu` context menus. Declared in `fxmanifest.lua`. |
| `oxmysql` | **Yes** | Points, stats and wave history persistence. |
| [`actioncam`](../actioncam/README.md) | Optional | Cinematic camera. All calls are `pcall`-wrapped. |
| [`tiktokapi`](../tiktokapi/README.md) | Not wired | Would supply live likes/gifts — see [Known gaps](#known-gaps). |

**Database.** Run [`arena.sql`](arena.sql) once against your server database before first
start. It creates three tables:

| Table | Holds |
|---|---|
| `arena_viewers` | Per-viewer points, total damage, total kills, waves sent, team membership |
| `arena_teams` | Named teams with wins/losses — schema and `DB` helpers exist, but no gameplay uses teams yet |
| `arena_wave_history` | One row per wave: composition JSON, cost, damage dealt, kills, outcome |

The NUI is pre-built in `web/build/`. To rebuild:

```sh
cd tiktok/web
npm install
npm run build          # or: npm run start:game
```

---

## Arena mode

### The loop

1. Admin runs `spawndefenders` — 8 configured defenders (SWAT, marines, snipers, a heavy)
   take fixed positions and begin an idle wander/return behaviour around their posts.
2. A viewer accumulates points, then runs `/sendwave`. `Waves.calculateComposition` spends
   their **entire** balance greedily — highest affordable tier first, capped at
   `Config.MaxPedsPerWave` (8).
3. The crew spawns at that viewer's permanently-assigned zone (one of six approach routes)
   and pushes toward the defender line.
4. Damage dealt to defenders is attributed to the nearest living attacker; kills are counted.
5. When the crew's last ped dies, the client reports `victory` (all defenders also dead) or
   `defeat`, and the server finalises the wave row and updates the viewer's stats.
6. **On victory the winner becomes the defender.** Their surviving peds are converted to the
   defender relationship group, and the next `/sendwave` from anyone else attacks *them*.
   If the current defender sends another wave, it spawns as a `[REINFORCEMENT]` on the
   defending side instead.
7. If nobody sends a wave for `Config.AutoBotInterval` (45 s), a CPU wave spawns so the
   stream never sits idle.

### Points economy

| Source | Points | Config key |
|---|---|---|
| Like | 2 | `Config.Points.perLike` |
| Gift | 100 × coins | `Config.Points.perGift` |
| Kill | 30 | `Config.Points.perKill` |
| Damage dealt | 0.05 per point | `Config.Points.perDamageDealt` |

`perKill` and `perDamageDealt` only pay out when `Config.GrowthMode == 'performance'`. The
default is `'gifts'`, under which crews earn nothing back from fighting.

### Wave tiers

| Tier | Name | Cost | HP / Armor | Accuracy | Weapons |
|---|---|---|---|---|---|
| 1 | Grunt | 50 | 50 / 0 | 25 | Pistols |
| 2 | Soldier | 150 | 100 / 25 | 45 | SMGs, assault shotgun |
| 3 | Veteran | 400 | 175 / 50 | 65 | Assault/carbine rifles |
| 4 | Sniper | 1200 | 250 / 100 | 90 | Sniper rifles |

Each tier carries both legacy singular fields (`name`, `model`, `weapon`, used by
`waves.lua` for summary text) and plural arrays (`names`, `models`, `weapons`) that are
sampled per-ped at spawn so a wave isn't eight identical peds.

### Commands

**Viewer**

| Command | Effect |
|---|---|
| `/sendwave` | Spend all points on a wave. Blocked while your crew is still alive. |
| `/mystats [username]` | Points, damage, kills, waves sent, assigned zone. |

**Admin** — console (`source == 0`) or `tiktok.admin` ace. **Note that
`Config.TestMode = true` makes `isAdmin` return true for everyone.**

| Command | Effect |
|---|---|
| `spawndefenders` | Place the defender line and mark the game running. |
| `resetgame` | Clear all peds and reset server state. |
| `cleardefenders` / `clearattackers` | Targeted clears. |
| `addpoints <user> <amount>` | Grant points. |
| `simlike <user> [count]` | Simulate likes. |
| `simgift <user> [count]` | Simulate gifts. |
| `forcewave <tier 1-4> [user]` | Spawn 3 peds of a tier, free. |
| `arenastate` | Print running state, current defender, active crews. |
| `arenaview [x y z]` / `arenaviewstop` | Start/stop `actioncam` with `Config.ArenaCameras`. |

**`/testmenu`** — an `ox_lib` context menu wrapping most of the above (game management,
simulate interactions, point grants, force waves, my stats, stop action cam). Gated on
`Config.TestMode`. It has **no convoy entries**, despite the convoy admin net events
existing.

---

## Convoy mode

A VIP vehicle plus two escorts spawn at the north-east of the map and drive to
`Config.Convoy.End` — roughly a 2.4 km cross-map route. Viewers spend points to spawn
carloads of attackers ahead of the VIP.

The convoy switches between two postures: **passive** (drive at `PassiveSpeed`, 14 m/s) and
**aggressive** (`AggressiveSpeed`, 24 m/s, passengers shoot) when an attacker vehicle comes
within `AggroRadius` (90 m). It returns to passive after `PassiveCooldown` (12 s) with
nothing nearby. Drivers stay locked on their drive task; passengers are given explicit
6-second shoot tasks re-issued every 4 s so the animation state machine isn't reset
constantly.

The run ends when the VIP gets within 20 m of the end point (`convoy:vipArrived`) or its
engine is destroyed (`convoy:vipDestroyed`).

### Commands

| Command | Effect |
|---|---|
| `/attackconvoy` | Viewer — spend 100 pts (tier 1 cost × 2) to send an attacker vehicle. |
| `convoystart` / `convoystop` | Admin — start/stop the run. |
| `convoyattack <tier 1-4> [user]` | Admin — force-spawn a 4-ped attacker vehicle. |
| `convoystate` | Admin — running state and active attackers. |

---

## Configuration

[`config.lua`](config.lua). Highlights:

| Key | Default | Notes |
|---|---|---|
| `GameMode` | `'arena'` | **Not read anywhere.** Both modes are always loaded; which one runs depends on which commands you use. |
| `TestMode` | `true` | Makes `isAdmin` return `true` for **every player**. Set `false` before any public use. |
| `GrowthMode` | `'gifts'` | `'performance'` additionally pays out kill and damage bonuses on crew completion. |
| `WaveCapEnabled` / `MaxPedsPerWave` | `true` / `8` | Ceiling on wave size regardless of points. |
| `MaxTierPerWave` | `nil` | Set to 1–4 to cap tier. |
| `ArenaCenter` | `vector3(1690.48, 3278.50, 41.16)` | Sandy Shores airfield. |
| `Defenders` | 8 entries | Fixed posts with model, weapon, HP, armor, accuracy, label. |
| `DefenderRespawnEnabled` / `DefenderRespawnDelay` | `true` / `20` | |
| `SpawnZones` | 6 entries | Each has `spawn`, `scatter`, an `approach` waypoint, and a `label`. Viewers are assigned round-robin and keep their zone. |
| `SpawnZoneSubRadius` | `22.0` | A viewer's exact spawn point is randomised once within this disc, then reused until their crew is wiped. |
| `AutoBot*` | on / 45 s / tier 2 / 4 peds / `'CPU'` | Idle filler waves. |
| `PedsDisappearOnDeath` / `PedDeathFadeDelay` | `true` / `3000` | Smoke poof, then the body is deleted. |
| `DisableBlood` | `false` | |
| `LabelDrawDistance` / `LabelZOffset` | `85.0` / `1.15` | Floating name tags. |
| `Convoy` | table | Vehicle spawns with per-vehicle model/driver/colour/position, route end, attacker vehicle models, aggro radius, speeds. |
| `ArenaCameras` | 7 cams | Venue cameras for `actioncam`. Place new ones with `/acamconfig`. |

---

## Architecture

```
server/database.lua      DB.* — oxmysql wrappers for viewers, teams, wave history, leaderboards
server/waves.lua         Waves.calculateComposition (greedy point spend) + describeWave
server/server.lua        Arena state, viewer/admin commands, auto-bot, crew outcomes
server/convoy.lua        Convoy state, commands, outcome events
        │  arena:spawnWave / arena:convertCrewToDefenders / convoy:spawnAttackers
        ▼
client/peds.lua          Arena peds: defenders, attacker waves, reinforcements, relationship
                         groups, damage attribution, defender idle behaviour
client/convoy.lua        Convoy vehicles, drivers/passengers, driving tasks, posture switching
client/labels.lua        Per-frame 3D name tags (ArenaLabels)
client/menu.lua          /testmenu — ox_lib context menus
client/client.lua        NUI push loop and net-event routing
        ▼
web/src/components/App.tsx   React HUD — defender bars, crew cards, convoy panels, toasts
```

As in `lms`, **all entity work is client-side** — the server only sends spawn payloads and
receives outcome reports. This is built for a single streaming client.

---

## Known gaps

Roughly in order of how much they matter.

### Not wired to TikTok
`arena:processLike` and `arena:processGift` exist and correctly award points, but **nothing
calls them from `tiktokapi`**. They're only reachable from `/testmenu` and the `sim*`
commands. Making this live means adding `tiktokapi:like` / `tiktokapi:gift` handlers in
`server/server.lua` — see [`lms/server/server.lua`](../lms/server/server.lua) for the
working pattern.

### Security
- **`Config.TestMode = true` disables all permission checks.** `isAdmin` returns `true`
  unconditionally, so any connected player can run `resetgame`, `addpoints`, `forcewave`, and
  every convoy admin command.
- **`arena:processLike` / `arena:processGift` are unguarded net events.** Any client can
  trigger them in a loop to mint unlimited points. `/testmenu` calls them 10–50 times per
  click, which is why they're unguarded — they need a server-side rate limit or to become
  local events driven only by `tiktokapi`.

### Convoy is materially unfinished
- **A viewer can only attack once per convoy.** `ConvoyServerState.activeCrews[username]` is
  set when they spend points and is only cleared on `convoystart` / `convoystop` /
  VIP arrival / VIP destruction. The client never reports attacker crew death back, so
  `/attackconvoy` stays blocked for the rest of the run.
- **Dead attacker wrecks are never cleaned up.** `updateHP` marks entries `alive = false` but
  never removes them from `ConvoyState.attackerVehicles` or deletes the vehicles. They
  accumulate in the world until `StopConvoy`.
- **No rewards.** `/attackconvoy` costs 100 points and pays nothing back — no damage
  tracking, no kill counting, no DB write, no wave-history row. Convoy touches `DB` only to
  read and deduct points.
- **Convoy is invisible to the test menu**, even though `convoy:admin:start`,
  `convoy:admin:stop` and `convoy:admin:forceAttack` net events are implemented and waiting.
- **`Config.GameMode` is dead.** It's declared but never read, so both modes load together
  and nothing prevents starting a convoy in the middle of an arena round.

### Arena rough edges
- **Teams are schema-only.** `arena_teams`, `DB.createTeam`, `DB.joinTeam`,
  `DB.getTeamLeaderboard` and the `team_id` column all exist, but no command or gameplay path
  creates or uses a team.
- **Leaderboards are unread.** `DB.getLeaderboard` and `DB.getTeamLeaderboard` are
  implemented and never called — the NUI has no leaderboard panel.
- **Damage attribution is proximity-based.** When a defender loses health, the delta is
  credited to the nearest living attacker. Cheap and approximate, like `lms`.
- **`Config.MaxTierPerWave` defaults to `nil`**, which `waves.lua` resolves to `#Config.Tiers`
  — fine, but it means the config key reads as "no cap" rather than showing the effective
  value.
- **Menu label mismatch.** `/testmenu` → Wave Testing → tier 4 is described as "Commander";
  `Config.Tiers[4].name` is `Sniper`.

### Housekeeping
- This README replaced the upstream **fivem-react-boilerplate-lua** README that shipped with
  the NUI scaffold. The `SendReactMessage`, `debugPrint`, `useNuiEvent`, `fetchNui` and
  `debugData` utilities in `client/utils.lua` and `web/src/utils/` come from that boilerplate
  and still work as documented there.
- `.github/workflows/` still contains the boilerplate's CI and release workflows, which
  reference the upstream project rather than this one.
