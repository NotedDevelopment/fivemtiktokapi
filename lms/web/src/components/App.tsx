import React, { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import './App.css';
import { useNuiEvent } from '../hooks/useNuiEvent';
import { debugData } from '../utils/debugData';
import { fetchNui } from '../utils/fetchNui';

// ── Browser dev seed ──────────────────────────────────────────────────────────
debugData<unknown>([
  { action: 'setVisible', data: true },
  { action: 'updateFodder', data: { alive: 2, total: 4, pcts: [0.85, 0.4] } },
  {
    action: 'setConfig',
    data: {
      eliminationMessages: [
        '{victim} got mogged on by {killer}',
        '{victim} dropped the soap near {killer}',
      ],
    },
  },
  {
    action: 'updateLeaderboard',
    data: [
      { owner: 'Viewer123',  points: 47, colorIndex: 1 },
      { owner: 'TikTokFan',  points: 30, colorIndex: 2 },
      { owner: 'OldGhost',   points: 25, colorIndex: 4 },
      { owner: 'XRacer99',   points: 12, colorIndex: 5 },
      { owner: 'NightOwlGG', points:  5, colorIndex: 3 },
    ],
  },
  {
    action: 'updateCrews',
    data: [
      {
        owner: 'Viewer123', color: [255, 80, 80], alive: 3, total: 3,
        peds: [
          { tierName: 'Netanyahu', pct: 0.88, alive: true },
          { tierName: 'Stalin',    pct: 0.55, alive: true },
          { tierName: 'El Chapo',  pct: 0.20, alive: true },
        ],
      },
      {
        owner: 'TikTokFan', color: [80, 150, 255], alive: 1, total: 1,
        peds: [{ tierName: 'Hillary', pct: 0.35, alive: true }],
      },
    ],
  },
]);

// ── Types ─────────────────────────────────────────────────────────────────────
interface PedInfo    { tierName: string; pct: number; alive: boolean; }
interface OwnerCrew  { owner: string; color: [number,number,number]; alive: number; total: number; peds: PedInfo[]; }
interface LeaderEntry{ owner: string; points: number; colorIndex: number; }
interface EliminationData {
  owner: string; killer: string | null;
  victimChar?: string | null; killerChar?: string | null;
}
interface FodderData    { alive: number; total: number; pcts: number[]; }
interface AttackerData  { alive: number; total: number; pcts: number[]; }
interface LmsConfig  { eliminationMessages: string[]; fodderName: string; guardName: string; }
interface Position   { x: number; y: number; }
interface Positions  { leader: Position; crews: Position; toasts: Position; }

// ── Helpers ───────────────────────────────────────────────────────────────────
function hpColor(pct: number): string {
  if (pct > 0.6) return '#4ade80';
  if (pct > 0.3) return '#facc15';
  return '#f87171';
}
function rgb(c: [number,number,number])  { return `rgb(${c[0]},${c[1]},${c[2]})`; }
function rgba(c: [number,number,number], a: number) { return `rgba(${c[0]},${c[1]},${c[2]},${a})`; }

const VIEWER_COLORS: [number,number,number][] = [
  [255,80,80],[80,150,255],[80,255,120],[255,200,50],
  [200,80,255],[255,140,50],[50,230,230],[255,130,180],
];

const computeDefaults = (): Positions => ({
  leader: { x: 24, y: 24 },
  crews:  { x: Math.max(0, window.innerWidth  - 24 - 280), y: 24 },
  toasts: { x: Math.max(0, window.innerWidth  / 2 - 160),  y: Math.max(0, window.innerHeight - 100) },
});

function formatElim(templates: string[], victim: string, killer: string | null): string {
  const t = templates[Math.floor(Math.random() * templates.length)] ?? '{victim} was eliminated by {killer}';
  return t.replace('{victim}', victim).replace('{killer}', killer ?? 'nobody');
}

function displayName(charName: string | null | undefined, owner: string): string {
  return charName ? `${charName} (${owner})` : owner;
}

// ── Sub-components ────────────────────────────────────────────────────────────
const CrewCard: React.FC<{ crew: OwnerCrew }> = ({ crew }) => {
  const border = rgb(crew.color);
  const glow   = rgba(crew.color, 0.12);
  return (
    <div className="crew-card" style={{ borderLeftColor: border, boxShadow: `inset 0 0 20px ${glow}` }}>
      <div className="crew-header">
        <span className="crew-dot" style={{ background: border }} />
        <span className="crew-owner">{crew.owner}</span>
        <span className="crew-count">{crew.alive}/{crew.total}</span>
      </div>
      <div className="crew-peds">
        {crew.peds.map((p, i) => (
          <div key={i} className={`crew-ped-row ${!p.alive ? 'dead' : ''}`}>
            <span className="crew-tier">{p.tierName}</span>
            <div className="bar-track small">
              <div className="bar-fill" style={{ width: `${Math.max(0, p.pct * 100).toFixed(1)}%`, background: p.alive ? hpColor(p.pct) : '#374151' }} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

const LeaderRow: React.FC<{ entry: LeaderEntry; rank: number }> = ({ entry, rank }) => {
  const color = VIEWER_COLORS[(entry.colorIndex - 1) % VIEWER_COLORS.length] ?? [200,200,200];
  return (
    <div className="leader-row">
      <span className="leader-rank">#{rank}</span>
      <span className="leader-dot" style={{ background: rgb(color) }} />
      <span className="leader-name">{entry.owner}</span>
      <span className="leader-kills">{entry.points}pt</span>
    </div>
  );
};

const LeaderSection: React.FC<{ title: string; entries: LeaderEntry[] }> = ({ title, entries }) => (
  <div className="leader-section">
    <div className="leader-section-title">{title}</div>
    {entries.length === 0
      ? <div className="leader-empty">—</div>
      : entries.map((e, i) => <LeaderRow key={e.owner} entry={e} rank={i + 1} />)
    }
  </div>
);

const AttackerPanel: React.FC<{ data: AttackerData; name: string }> = ({ data, name }) => (
  <div className="crew-card attacker-card">
    <div className="crew-header">
      <span className="crew-dot" style={{ background: 'rgba(220,80,80,0.7)' }} />
      <span className="crew-owner" style={{ color: 'rgba(255,180,180,0.75)' }}>{name.toUpperCase()}</span>
      <span className="crew-count">{data.alive} alive</span>
    </div>
    <div className="crew-peds">
      {data.pcts.map((pct, i) => (
        <div key={i} className="crew-ped-row">
          <span className="crew-tier" style={{ color: 'rgba(255,160,160,0.5)' }}>G{i + 1}</span>
          <div className="bar-track small">
            <div className="bar-fill" style={{ width: `${(pct * 100).toFixed(1)}%`, background: hpColor(pct) }} />
          </div>
        </div>
      ))}
    </div>
  </div>
);

const FodderPanel: React.FC<{ data: FodderData; name: string }> = ({ data, name }) => (
  <div className="crew-card fodder-card">
    <div className="crew-header">
      <span className="crew-dot" style={{ background: 'rgba(190,190,190,0.55)' }} />
      <span className="crew-owner" style={{ color: 'rgba(255,255,255,0.45)' }}>{name.toUpperCase()}</span>
      <span className="crew-count">{data.alive} alive</span>
    </div>
    <div className="crew-peds">
      {data.pcts.map((pct, i) => (
        <div key={i} className="crew-ped-row">
          <span className="crew-tier" style={{ color: 'rgba(255,255,255,0.3)' }}>F{i + 1}</span>
          <div className="bar-track small">
            <div className="bar-fill" style={{ width: `${(pct * 100).toFixed(1)}%`, background: hpColor(pct) }} />
          </div>
        </div>
      ))}
    </div>
  </div>
);

interface ToastEntry { id: number; data: EliminationData; msg: string; }
let _toastId = 0;

const EliminationToast: React.FC<{ entry: ToastEntry; onDone: (id: number) => void }> = ({ entry, onDone }) => {
  useEffect(() => {
    const t = setTimeout(() => onDone(entry.id), 5000);
    return () => clearTimeout(t);
  }, [entry.id, onDone]);
  return (
    <div className="elim-toast">
      <span className="toast-skull">☠</span>
      <span className="toast-text">{entry.msg}</span>
    </div>
  );
};

// ── Root ──────────────────────────────────────────────────────────────────────
const App: React.FC = () => {
  const [visible,     setVisible]     = useState(false);
  const [crews,       setCrews]       = useState<OwnerCrew[]>([]);
  const [leaderboard, setLeaderboard] = useState<LeaderEntry[]>([]);
  const [toasts,      setToasts]      = useState<ToastEntry[]>([]);
  const [fodder,      setFodder]      = useState<FodderData>({ alive: 0, total: 0, pcts: [] });
  const [attackers,   setAttackers]   = useState<AttackerData>({ alive: 0, total: 0, pcts: [] });
  const [lmsConfig,   setLmsConfig]   = useState<LmsConfig>({ eliminationMessages: ['{victim} was eliminated by {killer}'], fodderName: 'Fodder', guardName: 'Guard' });

  // Edit mode
  const [editMode,    setEditMode]    = useState(false);
  const [positions,   setPositions]   = useState<Positions | null>(null); // null = use CSS defaults
  const [editPos,     setEditPos]     = useState<Positions>(computeDefaults);
  const dragState = useRef<{ id: keyof Positions; ox: number; oy: number } | null>(null);

  // ── NUI events ──────────────────────────────────────────────────────────────
  useNuiEvent<boolean>('setVisible', setVisible);
  useNuiEvent<OwnerCrew[]>('updateCrews', useCallback((d) => setCrews(d ?? []), []));
  useNuiEvent<LeaderEntry[]>('updateLeaderboard', useCallback((d) => setLeaderboard(d ?? []), []));
  useNuiEvent<FodderData>('updateFodder', useCallback((d) => setFodder(d ?? { alive:0, total:0, pcts:[] }), []));
  useNuiEvent<AttackerData>('updateAttackers', useCallback((d) => setAttackers(d ?? { alive:0, total:0, pcts:[] }), []));
  useNuiEvent<LmsConfig>('setConfig', useCallback((d) => { if (d) setLmsConfig(d); }, []));
  // resetUIPositions sent by /lmsuireset command
  useNuiEvent('resetUIPositions', useCallback(() => {
    localStorage.removeItem('lms-ui-positions');
    setPositions(null);
    setEditPos(computeDefaults());
  }, []));
  useNuiEvent<boolean>('setEditMode', useCallback((active) => {
    if (active) setEditPos(positions ?? computeDefaults());
    setEditMode(active);
  }, [positions]));

  useNuiEvent<EliminationData>('showElimination', useCallback((data) => {
    const victim = data.owner === 'fodder' ? 'Fodder' : displayName(data.victimChar, data.owner);
    const killer = data.killer ? displayName(data.killerChar, data.killer) : null;
    const msg = formatElim(lmsConfig.eliminationMessages, victim, killer);
    setToasts((prev) => [...prev, { id: ++_toastId, data, msg }]);
  }, [lmsConfig]));

  useNuiEvent('resetUI', useCallback(() => {
    setCrews([]); setLeaderboard([]); setToasts([]);
    setFodder({ alive: 0, total: 0, pcts: [] });
    setAttackers({ alive: 0, total: 0, pcts: [] });
  }, []));

  const removeToast = useCallback((id: number) => setToasts((p) => p.filter((t) => t.id !== id)), []);

  // ── Drag system ─────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!editMode) return;
    const onMove = (e: MouseEvent) => {
      if (!dragState.current) return;
      const { id, ox, oy } = dragState.current;
      setEditPos((prev) => ({
        ...prev,
        [id]: {
          x: Math.max(0, Math.min(window.innerWidth  - 60, e.clientX - ox)),
          y: Math.max(0, Math.min(window.innerHeight - 40, e.clientY - oy)),
        },
      }));
    };
    const onUp = () => { dragState.current = null; };
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup',  onUp);
    return () => { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp); };
  }, [editMode]);

  const startDrag = useCallback((id: keyof Positions) => (e: React.MouseEvent) => {
    dragState.current = { id, ox: e.clientX - editPos[id].x, oy: e.clientY - editPos[id].y };
    e.preventDefault();
  }, [editPos]);

  const saveEdits = useCallback(() => {
    localStorage.setItem('lms-ui-positions', JSON.stringify(editPos));
    setPositions(editPos);
    fetchNui('savePositions', {});  // just signals Lua to close edit mode
  }, [editPos]);

  const cancelEdits = useCallback(() => { fetchNui('cancelEdit', {}); }, []);

  // ── Position styles ─────────────────────────────────────────────────────────
  const posStyle = (id: keyof Positions): React.CSSProperties | undefined => {
    if (editMode) {
      return { position: 'fixed', left: editPos[id].x, top: editPos[id].y, right: 'auto', bottom: 'auto', transform: 'none', zIndex: 9998 };
    }
    if (!positions) return undefined;
    return { position: 'fixed', left: positions[id].x, top: positions[id].y, right: 'auto', bottom: 'auto', transform: 'none' };
  };

  // ── Derived leaderboard ─────────────────────────────────────────────────────
  const activeOwners = useMemo(() => new Set(crews.map(c => c.owner)), [crews]);
  const sessionTop5  = useMemo(() => leaderboard.slice(0, 5), [leaderboard]);
  const activeTop5   = useMemo(() => leaderboard.filter(e => activeOwners.has(e.owner)).slice(0, 5), [leaderboard, activeOwners]);

  // Load saved positions from localStorage on mount
  useEffect(() => {
    try {
      const raw = localStorage.getItem('lms-ui-positions');
      if (raw) {
        const saved = JSON.parse(raw) as Positions;
        setPositions(saved);
        setEditPos(saved);
      }
    } catch {}
    fetchNui('nuiReady');
  }, []);

  const showPanel = !visible && !editMode;
  if (showPanel) return null;

  const editClass = editMode ? ' edit-panel' : '';

  return (
    <div className="hud-root">

      {/* Top-left — dual leaderboard */}
      {(editMode || leaderboard.length > 0) && (
        <div
          className={`panel leaderboard-panel${editClass}`}
          style={posStyle('leader')}
          onMouseDown={editMode ? startDrag('leader') : undefined}
        >
          {editMode && <div className="edit-handle">⠿ Leaderboard</div>}
          <div className="panel-title">Last Man Standing</div>
          <LeaderSection title="Session Top 5" entries={sessionTop5} />
          <div className="leader-divider" />
          <LeaderSection title="Active Top 5"  entries={activeTop5} />
        </div>
      )}

      {/* Top-right — crews + fodder */}
      {(editMode || crews.length > 0 || fodder.alive > 0 || attackers.alive > 0) && (
        <div
          className={`crews-panel${editClass}`}
          style={posStyle('crews')}
          onMouseDown={editMode ? startDrag('crews') : undefined}
        >
          {editMode && <div className="edit-handle" style={{ marginBottom: 8 }}>⠿ Crew Cards</div>}
          {crews.map((c) => <CrewCard key={c.owner} crew={c} />)}
          {attackers.alive > 0 && <AttackerPanel data={attackers} name={lmsConfig.guardName} />}
          {fodder.alive > 0 && <FodderPanel data={fodder} name={lmsConfig.fodderName} />}
        </div>
      )}

      {/* Bottom-centre — toasts */}
      <div
        className={`toasts-container${editClass}`}
        style={posStyle('toasts')}
        onMouseDown={editMode ? startDrag('toasts') : undefined}
      >
        {editMode && <div className="edit-handle" style={{ marginBottom: 6 }}>⠿ Toasts</div>}
        {toasts.map((t) => <EliminationToast key={t.id} entry={t} onDone={removeToast} />)}
      </div>

      {/* Edit mode toolbar */}
      {editMode && (
        <div className="edit-toolbar">
          <span className="edit-label">Drag panels · ESC to cancel</span>
          <button className="edit-btn save"   onClick={saveEdits}>Save (KSVP)</button>
          <button className="edit-btn cancel" onClick={cancelEdits}>Cancel</button>
        </div>
      )}

    </div>
  );
};

export default App;
