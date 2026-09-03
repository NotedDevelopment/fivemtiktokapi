# lms — Last Man Standing

**Bolingbroke Prison Brawl.** A TikTok LIVE battle royale where the viewers are the players.
Every like spawns an NPC that fights on that viewer's behalf in the prison yard. Crews fight
each other, waves of fodder, and periodic guard attackers. Last crew standing wins; a
persistent leaderboard tracks points across the session.

This is the **flagship program** of the `tiktokStuff` bundle and the most complete one — it
is fully wired to [`tiktokapi`](../tiktokapi/README.md), has a finished NUI, and runs
end-to-end without manual intervention once started.

---

## How a round plays out

1. Admin runs `lmsstart`.
2. Viewers on the TikTok LIVE tap like. Likes accumulate per viewer; every
   `Config.LikesPerPed` likes (default **5**) spawns one **Inmate** NPC for that viewer.
3. Each viewer is permanently assigned a **colour** and a **spawn zone** on first appearance,
   so their crew always enters from the same wall and is always the same colour on screen.
4. Every NPC gets a randomly-picked satirical name (gender-matched to its ped model) and a
   floating 3D label: `[TikTokUser] / NpcName / HP bar`.
5. Crews fight **everything that isn't theirs** — other viewers' crews, fodder, and guards.
6. Points are awarded per kill. The NUI shows a Session Top 5 and an Active Top 5.
7. When a crew's last NPC dies, an elimination toast fires with a randomly-chosen message
   from `Config.EliminationMessages`, and the crew's bodies are cleaned up 3.5 s later.
8. `lmsreset` wipes everything, including the session leaderboard.

Donations are supported (`lms:donation`) and spawn a stronger tier of NPC, but the
`tiktokapi:gift` → `lms:donation` bridge **is not wired up** — see [Known gaps](#known-gaps).

---

## Install

```cfg
ensure actioncam     # optional but strongly recommended
ensure tiktokapi     # required for live likes
ensure lms
```

**Dependencies**

| Resource | Required? | What breaks without it |
|---|---|---|
| [`tiktokapi`](../tiktokapi/README.md) | For live play | Likes never arrive. Everything still works via `lmslike`. |
| [`actioncam`](../actioncam/README.md) | Optional | No cinematic camera. All `exports['actioncam']` calls are `pcall`-wrapped, so it degrades cleanly. |

No database. No `ox_lib`. Everything is in-memory and resets with the resource.

The NUI is pre-built into `web/build/`. To rebuild it:

```sh
cd lms/web
npm install
npm run build          # or: npm run start:game   (watch mode, restart resource to see changes)
```

---

## Commands

All are registered with `restricted = true`, so they run from the **server console** or from
a player with the matching ace permission.

| Command | Effect |
|---|---|
| `lmsstart` | Start the game. Spawns the action cam, enables fodder/attacker spawning. |
| `lmsreset` | Stop and wipe everything — NPCs, viewers, session leaderboard, accumulated likes. |
| `lmslike [name]` | Spawn one Inmate for `name` (default `TestViewer`). Bypasses the like threshold. |
| `lmsdonate [name] [coins]` | Spawn a donation-tier NPC. Default `TestViewer`, `10` coins. |

Client-side, for tuning the overlay:

| Command | Effect |
|---|---|
| `/lmsedit` | Enter UI edit mode — drag the leaderboard, crew and toast panels anywhere, then Save. Positions persist in the NUI's `localStorage`. |
| `/lmsuireset` | Restore all panels to their default positions. |

---

## Configuration

Everything lives in [`config.lua`](config.lua).

### Arena and spawning

| Key | Default | Notes |
|---|---|---|
| `ArenaCenter` | `vector3(1695, 3762, 37.5)` | Bolingbroke inner yard. NPCs are leashed to this and walk here to idle. |
| `SpawnZones` | 6 entries | Perimeter spawn points with a `scatter` radius. Viewers are assigned round-robin. |
| `LikesPerPed` | `5` | Likes required to spawn one NPC. |
| `MaxNpcsPerViewer` | `12` | Hard cap on a single crew's living NPCs. |
| `LeashRadius` | `60.0` | Metres from centre before a fighting NPC is nav-tasked back. |

### NPC tiers

| Table | Spawned by | Notes |
|---|---|---|
| `LikeNpc` | Likes | Unarmed prisoner, 150 HP, 5 pts. |
| `DonationTiers` | `lms:donation` | Keyed by coin range. 1–49 → **Brawler** (bat, 200 HP, 15 pts); 50+ → **Armed** (pistol, 250 HP, 25 pts). |
| `FodderNpc` | Timer | Civilians with **10 HP** — free kills that keep the yard busy. 1 pt. |
| `AttackerNpc` | Timer | Cops/security, also 10 HP. Hostile to every viewer crew. 1 pt. |

> Both fodder and attackers are configured at 10 HP, i.e. they die almost instantly. That is
> deliberate — they exist to generate constant visible action and point trickle, not to be a
> threat. Raise `health` if you want them to actually contend.

### Fodder / attacker cadence

| Key | Default | |
|---|---|---|
| `FodderEnabled` / `FodderInterval` / `FodderBatchSize` / `MaxFodder` | on / 45 s / 4 / 20 | First batch spawns 6 s after start. |
| `AttackerEnabled` / `AttackerInterval` / `AttackerBatchSize` / `MaxAttackers` | on / 90 s / 2 / 10 | First batch spawns 15 s after start. |

### Behaviour and presentation

| Key | Default | Notes |
|---|---|---|
| `BehaviorTickMs` | `800` | Centre-attraction / emote / leash loop. |
| `HealthBarRefreshMs` | `500` | Drives both the NUI push and the death-detection loop. |
| `CenterZoneRadius` | `9.0` | Within this radius of centre, idle NPCs play an emote instead of milling around. |
| `EmoteMinMs` / `EmoteMaxMs` | `15000` / `35000` | Emotes are held for this long so NPCs don't twitch between animations. |
| `CenterEmotes` | 12 scenarios | Played by viewer NPCs when idle at centre. |
| `ViewerColors` | 8 RGB triples | Assigned round-robin, permanent per viewer. |
| `EliminationMessages` | 10 templates | `{victim}` and `{killer}` are substituted with `NpcName (TikTokUser)`. |
| `MaxCrewUIPeds` | `4` | Max HP bars per crew card in the NUI (lowest-HP first). |
| `DeathSmokeEnabled` | `true` | Coloured smoke puff in the crew's colour on death. |
| `ActionCamEnabled` / `ArenaCameras` | `true` / 2 cams | Passed to `actioncam` as venue cameras. Place new ones with `/acamconfig`. |

---

## Architecture

```
server/server.lua        Viewer registry, like accumulator, points, leaderboard,
                         elimination broadcast, admin commands
        │  lms:spawnNpc / lms:updateLeaderboard / lms:showElimination
        ▼
client/peds.lua          Everything ped-related: spawning, relationship groups,
                         behaviour loop, kill attribution, crew-wipe detection,
                         fodder/attacker timers
client/labels.lua        Per-frame 3D name + HP bar stack above each NPC
client/client.lua        NUI push loop, net-event routing, actioncam lifecycle,
                         /lmsedit and /lmsuireset
        │  SendNUIMessage
        ▼
web/src/components/App.tsx   React HUD — dual leaderboard, crew cards,
                             fodder/guard panels, elimination toasts, drag-to-move
```

### Things worth knowing

**Everything ped-side is client-side.** The server never sees an entity — it sends spawn
payloads and receives kill reports. In a multi-client session each client simulates its own
copy of the arena, so this is built for a **single streaming client**, not a populated
server.

**Relationship groups.** Each viewer gets their own group (`LMS_V_<SANITIZED_NAME>`) that is
hostile to every other viewer group, to `LMS_FODDER`, and to `LMS_ATTACKER` — but
**neutral to the player**, so the streamer can stand in the yard and film without being
attacked. The player *is* hostile to fodder and attackers, so they can join in.

**Kill attribution is proximity-based, not real.** When an NPC dies, the nearest living
entity (viewer NPC → fodder → attacker) is credited. It's approximate by design — cheap, and
close enough to look right on stream. Only viewer crews score; `Fodder` and `Guard` are
recorded as the killer's name for the toast but earn nothing.

**Two leaderboards, two lifetimes.** `State.viewers` is the active set — an entry is removed
30 s after that crew is wiped. `State.session` is never pruned until `lmsreset`, which is
what backs "Session Top 5". Both are broadcast together in one payload; the NUI derives
"Active Top 5" by intersecting with the crews currently on screen.

**Emotes are protected from retasking.** `refreshCombat`-style retasks are gated on a
5-second cooldown and on `hasLivingEnemies`, specifically so an NPC celebrating with nobody
left to fight doesn't get its scenario interrupted every tick. If you change the behaviour
loop, preserve that.

**UI positions live in the browser, not in Lua.** `/lmsedit` writes to `localStorage` under
the key `lms-ui-positions`; Lua only toggles NUI focus. Clearing CEF cache resets them.

---

## Known gaps

- **Gifts aren't wired.** `lms:donation` and `Config.DonationTiers` are fully implemented,
  but nothing listens for `tiktokapi:gift`. Only likes come in live. Adding it is a handful
  of lines mirroring the existing `tiktokapi:like` handler in
  [`server/server.lua`](server/server.lua) — map `diamondCount * repeatCount` to `coins` and
  call the same path `lms:donation` uses.
- **`refreshCombat` is dead code.** Defined at [`client/peds.lua:181`](client/peds.lua#L181)
  and never called. The per-NPC behaviour loop does the retasking now. Safe to delete.
- **No win condition.** The round never formally ends — crews are eliminated and new ones
  spawn from likes indefinitely. Stopping is a manual `lmsreset`.
- **Single-client assumption.** See above. Running this with several players connected means
  several independent simulations and duplicated kill reports to the server.
- **`likeAccumulator` isn't bounded.** It grows one entry per unique viewer for the life of
  the session. Not a practical problem at stream scale, but it only clears on `lmsreset`.
