# tiktokapi

TikTok LIVE → FiveM event bridge. Connects to a live TikTok stream and re-emits every chat
message, gift, like, follow, share, join and subscribe as a **server-side FiveM event** that
any other resource can listen to.

This is the foundation the rest of the `tiktokStuff` bundle is built on — `lms` consumes it
directly, and `tiktok` is meant to. Nothing else in the bundle talks to TikTok itself.

---

## How it works

The resource runs **two runtimes inside one resource**:

```
TikTok LIVE (WebSocket)
        │
        ▼
server/dist/tiktok.js      ← Node.js runtime. Owns the connection,
  (esbuild bundle of          decodes protobuf, emits tiktokapi:* events
   server/tiktok.js)
        │  emit()  — cross-runtime, same resource
        ▼
server/main.lua            ← Lua runtime. Exports, console commands,
                             connection-state tracking
        │
        ▼
your resource's server script   AddEventHandler('tiktokapi:gift', ...)
```

The Node side never talks to clients. The Lua side never talks to TikTok. They communicate
through plain `emit` / `AddEventHandler` on the shared resource event bus.

`client/main.lua` only registers net-event names so *your* resource can relay events to
specific players — this resource never triggers them itself.

### Files

| File | Runtime | Purpose |
|---|---|---|
| `server/tiktok.js` | Node | Source. Connection lifecycle + event mapping. **Edit this one.** |
| `server/dist/tiktok.js` | Node | Committed esbuild bundle — what actually loads. Regenerate after editing the source. |
| `server/main.lua` | Lua | `Connect` / `Disconnect` / `IsConnected` / `GetUsername` exports, `tiktok*` console commands |
| `client/main.lua` | Lua | Net-event registrations for server→client relaying |

---

## Setup

The bundle in `server/dist/` is **self-contained** — it inlines `tiktok-live-connector` and
only requires Node builtins. You do not need `node_modules` present to run the resource.

```cfg
ensure tiktokapi
```

You only need `npm install` if you intend to **modify** `server/tiktok.js`:

```sh
cd resources/[standalone]/tiktokapi
npm install
npm run build      # or: npm run watch
```

`npm run build` runs esbuild and overwrites `server/dist/tiktok.js`. **Editing
`server/tiktok.js` alone changes nothing at runtime** — the manifest loads the bundle.

> Requires the `node_version '22'` runtime declared in `fxmanifest.lua`. On an older FXServer
> that doesn't support Node 22, the resource will fail to start.

---

## Connecting

The TikTok account must be **live right now**. Connecting to an offline account fails.

### From the server console

```
tiktok <username>     connect to @username's LIVE (the @ is optional)
tiktokstop            disconnect
tiktokstatus          print connection state
```

These are console-only — they return early when `source ~= 0`, so they cannot be run in-game.

### From another resource's server Lua

```lua
exports['tiktokapi']:Connect('someusername')  -- true, or false + reason if empty
exports['tiktokapi']:Disconnect()
exports['tiktokapi']:IsConnected()            -- boolean
exports['tiktokapi']:GetUsername()            -- string or nil
```

`Connect` is **fire-and-forget**. It returns `true` as soon as the request is handed to the
Node runtime — before the connection is established. To know whether it actually worked,
listen for `tiktokapi:connected` / `tiktokapi:connectFailed`.

---

## Server events

Register with `AddEventHandler` on the **server**. These are local resource events, not net
events — clients cannot receive them directly.

Payloads come in two shapes. Read the table carefully.

### JSON-string payloads — one argument, `json.decode` it

| Event | Decoded fields |
|---|---|
| `tiktokapi:chat` | `userId`, `uniqueId`, `nickname`, `comment`, `followRole` |
| `tiktokapi:gift` | `userId`, `uniqueId`, `nickname`, `giftId`, `giftName`, `giftType`, `diamondCount`, `repeatCount` |
| `tiktokapi:like` | `userId`, `uniqueId`, `nickname`, `likeCount`, `totalLikeCount` |
| `tiktokapi:follow` | `userId`, `uniqueId`, `nickname` |
| `tiktokapi:share` | `userId`, `uniqueId`, `nickname` |
| `tiktokapi:subscribe` | `userId`, `uniqueId`, `nickname` |
| `tiktokapi:member` | `userId`, `uniqueId`, `nickname`, `action` |

### Plain-argument payloads — **do not** `json.decode` these

| Event | Arguments |
|---|---|
| `tiktokapi:connected` | `username` (string) |
| `tiktokapi:disconnected` | `username` (string) |
| `tiktokapi:connectFailed` | `username` (string), `reason` (string) — **two** arguments |
| `tiktokapi:error` | `message` (string) |
| `tiktokapi:streamEnd` | the raw `action` value (not JSON) |

### Field notes

**`uniqueId`** is the stable TikTok handle (the `@name`) — use it as the identity key.
`nickname` is the display name and can change at any time. `userId` is a numeric id the
connector converts to a **string**.

**`followRole`**

| Value | Meaning |
|---|---|
| 0 | Not following |
| 1 | Follower |
| 2 | Mutual friend |

**`member.action`**

| Value | Meaning |
|---|---|
| 1 | Viewer joined |
| 2 | Viewer requested to join battle |

**Gifts and streaks.** TikTok sends repeated events while a viewer holds a streakable gift.
`server/tiktok.js` suppresses those: for `giftType == 1` it only emits when `repeatEnd` is
set, so you receive **one** event per streak carrying the final `repeatCount`.
`giftType == 2` is one-shot and always emits. Total diamond value is
`diamondCount * repeatCount`.

**Likes.** `likeCount` is the batch size for that single event (TikTok batches rapid taps);
`totalLikeCount` is the running stream total. Accumulate `likeCount` — don't diff the total.

---

## Example — reward a player for a gift

```lua
-- your_resource/server/main.lua

AddEventHandler('tiktokapi:gift', function(jsonData)
    local data = json.decode(jsonData)
    if not data then return end

    local target = GetPlayerFromTikTokId(data.uniqueId)   -- your own mapping
    if not target then return end

    local diamonds = (data.diamondCount or 0) * (data.repeatCount or 1)
    TriggerClientEvent('myresource:giftNotification', target, data.nickname, data.giftName, diamonds)

    exports['Renewed-Banking']:addAccountMoney(target, 'cash', math.floor(diamonds * 0.5))
end)
```

A real, working consumer lives in [`../lms/server/server.lua`](../lms/server/server.lua) — it
accumulates `likeCount` per `uniqueId` and spawns an NPC every N likes.

---

## Relaying to clients

`client/main.lua` pre-registers these net events so your resource can push TikTok data to a
specific player without declaring them itself:

```
tiktokapi:client:chat   :gift    :like       :follow
tiktokapi:client:share  :member  :subscribe  :streamEnd
```

```lua
-- server
TriggerClientEvent('tiktokapi:client:gift', playerId, jsonData)

-- client, in your own resource
AddEventHandler('tiktokapi:client:gift', function(jsonData)
    local data = json.decode(jsonData)
end)
```

Nothing in this resource fires them — that relay is yours to write.

---

## Known issues / cleanup before production

The resource is functional but still carries development scaffolding. All of these are safe
to remove and should be:

- **Debug spam.** `server/tiktok.js` logs a line for every `chat`, `like` and `member` event,
  plus a `[RAW] type=...` line for *every* decoded protobuf message. On a busy stream that
  floods the console and costs real performance. Delete the `log('[DEBUG] ...')` calls and
  the `decodedData` handler.
- **Startup test event.** `server/tiktok.js` fires `tiktokapi:test` 2 s after load to verify
  the cross-runtime bridge; `server/main.lua` prints it. Both can go.
- **Example handlers left live.** `server/main.lua` has `AddEventHandler` blocks for
  `member`, `chat` and `like` that print to console (the `like` one dumps the whole payload
  as indented JSON). These are examples, not features — delete them.
- **Broken client handler.** `client/main.lua` registers `tiktokapi:client:like` with the
  signature `function(playerId, jsonData)`. A `TriggerClientEvent` target is *not* passed as
  an argument, so `playerId` receives the JSON string and `jsonData` is `nil`. It should be
  `RegisterNetEvent('tiktokapi:client:like', true)` like its neighbours.
- **Duplicate exports.** `IsConnected` and `GetUsername` are registered **twice** — once in
  `server/tiktok.js` and once in `server/main.lua`. Which one answers depends on load order.
  Keep the Lua pair (it tracks state from the connection events) and drop the JS pair.
- **Deprecated connector class.** `server/tiktok.js` uses `WebcastPushConnection`, which in
  `tiktok-live-connector` v2 is a back-compat shim marked `@deprecated` over
  `TikTokLiveConnection`. It still works — the shim runs `simplifyObject`, which is exactly
  what flattens `data.user` into the top-level `uniqueId` / `nickname` fields this code reads
  — but it should be migrated before a future major version drops it.
- **No reconnect.** If TikTok drops the socket, `tiktokapi:disconnected` fires and the
  connection is gone. Nothing retries. For resilience, listen for `disconnected` and call
  `Connect` again on a backoff.
- **Single connection.** Global state (`connection`, `currentUsername`) means one stream at a
  time. Calling `Connect` again disconnects the current stream first.

If TikTok changes their protocol and connections start failing outright, check for a
`tiktok-live-connector` update, bump it in `package.json`, and re-run `npm run build`.
