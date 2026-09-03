const { WebcastPushConnection } = require('tiktok-live-connector');

let connection = null;
let currentUsername = null;
let isConnected = false;

// ─── helpers ──────────────────────────────────────────────────────────────────

function log(msg)  { console.log(`^2[TikTokAPI]^0 ${msg}`); }
function warn(msg) { console.log(`^3[TikTokAPI]^0 ${msg}`); }
function err(msg)  { console.log(`^1[TikTokAPI]^0 ${msg}`); }

// ─── connection ───────────────────────────────────────────────────────────────

async function connectToLive(username) {
    if (connection) {
        await disconnectFromLive();
    }

    connection = new WebcastPushConnection(username, {
        processInitialData: false,
        enableExtendedGiftInfo: true,
        enableWebsocketUpgrade: true,
        requestPollingIntervalMs: 2000,
    });

    currentUsername = username;

    connection.on('connected', () => {
        isConnected = true;
        log(`Connected to @${username}'s LIVE`);
        emit('tiktokapi:connected', username);
    });

    connection.on('disconnected', () => {
        const who = currentUsername;
        isConnected = false;
        connection = null;
        currentUsername = null;
        warn(`Disconnected from @${who}'s LIVE`);
        emit('tiktokapi:disconnected', who);
    });

    connection.on('error', (e) => {
        err(`${e.message || e}`);
        emit('tiktokapi:error', e.message || String(e));
    });

    // ── chat ──────────────────────────────────────────────────────────────────
    // v2: user fields are flattened to top-level (data.user is deleted by simplifyObject)
    connection.on('chat', (data) => {
        log(`[DEBUG] chat event fired — user=${data.uniqueId} comment=${data.comment}`);
        emit('tiktokapi:chat', JSON.stringify({
            userId:     data.userId,
            uniqueId:   data.uniqueId,
            nickname:   data.nickname,
            comment:    data.comment,
            followRole: data.followRole,
        }));
    });

    // ── gift ──────────────────────────────────────────────────────────────────
    // giftType 1 = repeatable (streaking) — only emit on repeatEnd so you get the final count
    // giftType 2 = one-shot
    // v2: giftDetails is also merged to top-level
    connection.on('gift', (data) => {
        if (data.giftType === 1 && !data.repeatEnd) return;
        emit('tiktokapi:gift', JSON.stringify({
            userId:       data.userId,
            uniqueId:     data.uniqueId,
            nickname:     data.nickname,
            giftId:       data.giftId,
            giftName:     data.giftName,
            giftType:     data.giftType,
            diamondCount: data.diamondCount,
            repeatCount:  data.repeatCount,
        }));
    });

    // ── like ──────────────────────────────────────────────────────────────────
    connection.on('like', (data) => {
        log(`[DEBUG] like event fired — likeCount=${data.likeCount} totalLikeCount=${data.totalLikeCount} user=${data.uniqueId}`);
        emit('tiktokapi:like', JSON.stringify({
            userId:         data.userId,
            uniqueId:       data.uniqueId,
            nickname:       data.nickname,
            likeCount:      data.likeCount,
            totalLikeCount: data.totalLikeCount,
        }));
    });

    // ── follow / share / subscribe ────────────────────────────────────────────
    const simpleEvents = ['follow', 'share', 'subscribe'];
    for (const ev of simpleEvents) {
        connection.on(ev, (data) => {
            emit(`tiktokapi:${ev}`, JSON.stringify({
                userId:   data.userId,
                uniqueId: data.uniqueId,
                nickname: data.nickname,
            }));
        });
    }

    // ── member ────────────────────────────────────────────────────────────────
    connection.on('member', (data) => {
        log(`[DEBUG] member event fired — user=${data.uniqueId} action=${data.action}`);
        emit('tiktokapi:member', JSON.stringify({
            userId:   data.userId,
            uniqueId: data.uniqueId,
            nickname: data.nickname,
            action:   data.action,
        }));
    });

    connection.on('streamEnd', (data) => {
        emit('tiktokapi:streamEnd', data?.action ?? data);
    });

    // ── raw message logger (debug) ────────────────────────────────────────────
    connection.on('decodedData', (type, decodedData) => {
        log(`[RAW] type=${type}`);
    });

    // ── connect ───────────────────────────────────────────────────────────────
    try {
        await connection.connect();
    } catch (e) {
        err(`Failed to connect to @${username}: ${e.message}`);
        connection = null;
        currentUsername = null;
        isConnected = false;
        emit('tiktokapi:connectFailed', username, e.message || String(e));
    }
}

async function disconnectFromLive() {
    if (connection) {
        try { connection.disconnect(); } catch (_) {}
        connection = null;
    }
    isConnected = false;
    currentUsername = null;
}

// ─── FiveM event listeners (commands from Lua) ────────────────────────────────

on('tiktokapi:cmd:connect', (username) => {
    connectToLive(username);
});

on('tiktokapi:cmd:disconnect', () => {
    disconnectFromLive();
});

// ─── exports ──────────────────────────────────────────────────────────────────

exports('IsConnected', () => isConnected);
exports('GetUsername', () => currentUsername);

log('Node.js runtime loaded — waiting for connect command.');

// Cross-runtime emit test: fires 2s after startup so Lua has time to register its handler
setTimeout(() => {
    log('[DEBUG] firing cross-runtime test event...');
    emit('tiktokapi:test', 'hello from nodejs');
}, 2000);
