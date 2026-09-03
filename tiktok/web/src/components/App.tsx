import React, { useState, useCallback, useEffect } from "react";
import "./App.css";
import { useNuiEvent } from "../hooks/useNuiEvent";
import { debugData } from "../utils/debugData";
import { fetchNui } from "../utils/fetchNui";

// ─── Browser dev seed ────────────────────────────────────────────────────────
debugData<unknown>([
  { action: "setVisible", data: true },
  // Uncomment one block at a time to preview each mode in browser dev.

  // ── Arena mode seed ───────────────────────────────────────────────────────
  // {
  //   action: "updateDefenders",
  //   data: [
  //     { label: "Guard Alpha", pct: 0.85, alive: true },
  //     { label: "Guard Beta",  pct: 0.5,  alive: true },
  //     { label: "Sniper",      pct: 0.1,  alive: true },
  //   ],
  // },
  // {
  //   action: "updateCrews",
  //   data: [
  //     { owner: "Viewer123", color: [255, 80, 80], alive: 2, total: 3,
  //       peds: [
  //         { tierName: "Grunt",   pct: 0.9,  alive: true  },
  //         { tierName: "Grunt",   pct: 0.45, alive: true  },
  //         { tierName: "Soldier", pct: 0.0,  alive: false },
  //       ] },
  //   ],
  // },

  // ── Convoy mode seed ──────────────────────────────────────────────────────
  {
    action: "updateConvoy",
    data: {
      active: true,
      mode: "aggressive",
      progress: 0.42,
      convoy: [
        {
          role: "vip", label: "VIP Transport", vehPct: 0.72, alive: true,
          colorR: 255, colorG: 215, colorB: 50,
          peds: [{ tierName: "Driver", pct: 0.88, alive: true }],
        },
        {
          role: "escort", label: "Escort 1", vehPct: 0.55, alive: true,
          colorR: 80, colorG: 160, colorB: 255,
          peds: [{ tierName: "Driver", pct: 0.6, alive: true }],
        },
        {
          role: "escort", label: "Escort 2", vehPct: 0.0, alive: false,
          colorR: 80, colorG: 160, colorB: 255,
          peds: [{ tierName: "Driver", pct: 0.0, alive: false }],
        },
      ],
      attackers: [
        {
          owner: "StreamSniper",
          color: [255, 80, 80],
          vehicles: [
            {
              label: "StreamSniper · Veteran", vehPct: 0.45, alive: true,
              peds: [
                { tierName: "Veteran", pct: 0.7,  alive: true  },
                { tierName: "Veteran", pct: 0.35, alive: true  },
              ],
            },
          ],
        },
        {
          owner: "TikTokFan99",
          color: [80, 150, 255],
          vehicles: [
            {
              label: "TikTokFan99 · Grunt", vehPct: 0.9, alive: true,
              peds: [
                { tierName: "Grunt", pct: 0.9, alive: true },
              ],
            },
          ],
        },
      ],
    },
  },
]);

// ─── Types ────────────────────────────────────────────────────────────────────
interface DefenderInfo {
  label: string;
  pct: number;
  alive: boolean;
}

interface PedInfo {
  tierName: string;
  pct: number;
  alive: boolean;
}

interface OwnerCrew {
  owner: string;
  color: [number, number, number];
  alive: number;
  total: number;
  peds: PedInfo[];
}

interface CrewEnded {
  owner: string;
  damageDealt: number;
  kills: number;
  outcome: "victory" | "defeat";
  colorIndex: number;
}

// ─── Convoy types ─────────────────────────────────────────────────────────────
interface ConvoyPedInfo {
  tierName: string;
  pct: number;
  alive: boolean;
}

interface ConvoyVehicleInfo {
  role: "vip" | "escort";
  label: string;
  vehPct: number;
  alive: boolean;
  colorR: number;
  colorG: number;
  colorB: number;
  peds: ConvoyPedInfo[];
}

interface ConvoyAttackerVehicle {
  label: string;
  vehPct: number;
  alive: boolean;
  peds: ConvoyPedInfo[];
}

interface ConvoyAttackerGroup {
  owner: string;
  color: [number, number, number];
  vehicles: ConvoyAttackerVehicle[];
}

interface ConvoyData {
  active: boolean;
  mode?: "passive" | "aggressive";
  progress?: number;
  convoy?: ConvoyVehicleInfo[];
  attackers?: ConvoyAttackerGroup[];
}

interface ConvoyResult {
  result: "success" | "failure";
  reason: string;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
function hpColor(pct: number): string {
  if (pct > 0.6) return "#4ade80";
  if (pct > 0.3) return "#facc15";
  return "#f87171";
}

function rgbStr(color: [number, number, number]): string {
  return `rgb(${color[0]}, ${color[1]}, ${color[2]})`;
}

function rgbaStr(color: [number, number, number], alpha: number): string {
  return `rgba(${color[0]}, ${color[1]}, ${color[2]}, ${alpha})`;
}

// ─── Defender panel ───────────────────────────────────────────────────────────
const DefenderRow: React.FC<{ info: DefenderInfo }> = ({ info }) => (
  <div className={`def-row ${!info.alive ? "dead" : ""}`}>
    <span className="def-label">{info.label}</span>
    <div className="bar-track">
      <div
        className="bar-fill"
        style={{
          width: `${Math.max(0, info.pct * 100).toFixed(1)}%`,
          background: hpColor(info.pct),
        }}
      />
    </div>
    <span className="def-pct">
      {info.alive ? `${Math.round(info.pct * 100)}%` : "☠"}
    </span>
  </div>
);

// ─── Single crew card ─────────────────────────────────────────────────────────
const CrewCard: React.FC<{ crew: OwnerCrew }> = ({ crew }) => {
  const borderColor = rgbStr(crew.color);
  const glowColor   = rgbaStr(crew.color, 0.15);

  return (
    <div
      className="crew-card"
      style={{
        borderLeftColor: borderColor,
        boxShadow: `inset 0 0 24px ${glowColor}`,
      }}
    >
      {/* Header */}
      <div className="crew-header">
        <span className="crew-dot" style={{ background: borderColor }} />
        <span className="crew-owner">{crew.owner}</span>
        <span className="crew-count">
          {crew.alive}/{crew.total}
        </span>
      </div>

      {/* Per-ped bars */}
      <div className="crew-peds">
        {crew.peds.map((p, i) => (
          <div key={i} className={`crew-ped-row ${!p.alive ? "dead" : ""}`}>
            <span className="crew-tier">{p.tierName}</span>
            <div className="bar-track small">
              <div
                className="bar-fill"
                style={{
                  width: `${Math.max(0, p.pct * 100).toFixed(1)}%`,
                  background: p.alive ? hpColor(p.pct) : "#374151",
                }}
              />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

// ─── Brief result toast (replaces old summary modal) ─────────────────────────
interface ToastEntry {
  id: number;
  data: CrewEnded;
}

let _toastId = 0;

const ResultToast: React.FC<{ entry: ToastEntry; onDone: (id: number) => void }> = ({
  entry,
  onDone,
}) => {
  const { data } = entry;
  const isVictory = data.outcome === "victory";
  React.useEffect(() => {
    const t = setTimeout(() => onDone(entry.id), 5000);
    return () => clearTimeout(t);
  }, [entry.id, onDone]);

  return (
    <div className={`result-toast ${isVictory ? "victory" : "defeat"}`}>
      <span className="toast-icon">{isVictory ? "⚔" : "☠"}</span>
      <span className="toast-owner">{data.owner}</span>
      <span className="toast-detail">
        {isVictory ? "VICTORY" : "DEFEAT"} · {data.damageDealt} dmg · {data.kills}K
      </span>
    </div>
  );
};

// ─── Convoy vehicle card ──────────────────────────────────────────────────────
const ConvoyVehicleCard: React.FC<{ vehicle: ConvoyVehicleInfo }> = ({ vehicle }) => {
  const isVip       = vehicle.role === "vip";
  const borderColor = `rgb(${vehicle.colorR}, ${vehicle.colorG}, ${vehicle.colorB})`;
  const glowColor   = `rgba(${vehicle.colorR}, ${vehicle.colorG}, ${vehicle.colorB}, 0.18)`;

  return (
    <div
      className={`convoy-veh-card ${isVip ? "vip" : ""} ${!vehicle.alive ? "dead" : ""}`}
      style={{ borderLeftColor: borderColor, boxShadow: `inset 0 0 20px ${glowColor}` }}
    >
      <div className="convoy-veh-header">
        <span className="convoy-veh-label">{vehicle.label}</span>
        <span className={`convoy-veh-role-badge ${isVip ? "vip" : "escort"}`}>
          {isVip ? "VIP" : "ESCORT"}
        </span>
      </div>
      <div className="convoy-hp-row">
        <span className="convoy-hp-tag">VEH</span>
        <div className="bar-track">
          <div
            className="bar-fill"
            style={{
              width: `${Math.max(0, vehicle.vehPct * 100).toFixed(1)}%`,
              background: hpColor(vehicle.vehPct),
            }}
          />
        </div>
        <span className="def-pct">{vehicle.alive ? `${Math.round(vehicle.vehPct * 100)}%` : "☠"}</span>
      </div>
      {vehicle.peds.map((p, i) => (
        <div key={i} className={`crew-ped-row ${!p.alive ? "dead" : ""}`}>
          <span className="crew-tier">{p.tierName}</span>
          <div className="bar-track small">
            <div
              className="bar-fill"
              style={{
                width: `${Math.max(0, p.pct * 100).toFixed(1)}%`,
                background: p.alive ? hpColor(p.pct) : "#374151",
              }}
            />
          </div>
        </div>
      ))}
    </div>
  );
};

// ─── Convoy attacker card ─────────────────────────────────────────────────────
const ConvoyAttackerCard: React.FC<{ group: ConvoyAttackerGroup }> = ({ group }) => {
  const borderColor = rgbStr(group.color);
  const glowColor   = rgbaStr(group.color, 0.15);
  const aliveVehs   = group.vehicles.filter((v) => v.alive).length;

  return (
    <div
      className="crew-card"
      style={{ borderLeftColor: borderColor, boxShadow: `inset 0 0 24px ${glowColor}` }}
    >
      <div className="crew-header">
        <span className="crew-dot" style={{ background: borderColor }} />
        <span className="crew-owner">{group.owner}</span>
        <span className="crew-count">{aliveVehs}/{group.vehicles.length}</span>
      </div>
      {group.vehicles.map((v, i) => (
        <div key={i} className={`convoy-atk-veh ${!v.alive ? "dead" : ""}`}>
          <div className="convoy-hp-row">
            <span className="convoy-hp-tag" style={{ maxWidth: 90, overflow: "hidden", textOverflow: "ellipsis" }}>
              {v.label.split(" · ")[1] ?? v.label}
            </span>
            <div className="bar-track small">
              <div
                className="bar-fill"
                style={{
                  width: `${Math.max(0, v.vehPct * 100).toFixed(1)}%`,
                  background: v.alive ? hpColor(v.vehPct) : "#374151",
                }}
              />
            </div>
          </div>
          {v.peds.map((p, j) => (
            <div key={j} className={`crew-ped-row ${!p.alive ? "dead" : ""}`}>
              <span className="crew-tier">{p.tierName}</span>
              <div className="bar-track small">
                <div
                  className="bar-fill"
                  style={{
                    width: `${Math.max(0, p.pct * 100).toFixed(1)}%`,
                    background: p.alive ? hpColor(p.pct) : "#374151",
                  }}
                />
              </div>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
};

// ─── Convoy result toast ──────────────────────────────────────────────────────
const ConvoyResultToast: React.FC<{ result: ConvoyResult; onDone: () => void }> = ({
  result,
  onDone,
}) => {
  const isSuccess = result.result === "success";
  React.useEffect(() => {
    const t = setTimeout(onDone, 6000);
    return () => clearTimeout(t);
  }, [onDone]);

  return (
    <div className={`result-toast ${isSuccess ? "victory" : "defeat"} convoy-result`}>
      <span className="toast-icon">{isSuccess ? "🏁" : "💥"}</span>
      <div>
        <span className="toast-owner">CONVOY {isSuccess ? "SUCCESS" : "FAILED"}</span>
        <span className="toast-detail" style={{ display: "block" }}>{result.reason}</span>
      </div>
    </div>
  );
};

// ─── Root ─────────────────────────────────────────────────────────────────────
const App: React.FC = () => {
  const [visible,       setVisible]       = useState(false);
  const [defenders,     setDefenders]     = useState<DefenderInfo[]>([]);
  const [crews,         setCrews]         = useState<OwnerCrew[]>([]);
  const [toasts,        setToasts]        = useState<ToastEntry[]>([]);
  const [convoy,        setConvoy]        = useState<ConvoyData>({ active: false });
  const [convoyResult,  setConvoyResult]  = useState<ConvoyResult | null>(null);

  useNuiEvent<boolean>("setVisible", setVisible);

  useNuiEvent<DefenderInfo[]>("updateDefenders", useCallback((data) => {
    setDefenders(data ?? []);
  }, []));

  useNuiEvent<OwnerCrew[]>("updateCrews", useCallback((data) => {
    setCrews((data ?? []).filter(c => c.peds.some(p => p.alive)));
  }, []));

  useNuiEvent<CrewEnded>("crewEnded", useCallback((data) => {
    setToasts((prev) => [...prev, { id: ++_toastId, data }]);
  }, []));

  useNuiEvent("resetUI", useCallback(() => {
    setDefenders([]);
    setCrews([]);
    setToasts([]);
  }, []));

  useNuiEvent<ConvoyData>("updateConvoy", useCallback((data) => {
    if (data?.attackers) {
      data.attackers = data.attackers.filter(g => g.vehicles.some(v => v.alive));
    }
    setConvoy(data ?? { active: false });
  }, []));

  useNuiEvent<string>("convoyMode", useCallback((mode) => {
    setConvoy((prev) => ({ ...prev, mode: mode as "passive" | "aggressive" }));
  }, []));

  useNuiEvent("convoyUpdate", useCallback((data: ConvoyData) => {
    setConvoy(data ?? { active: false });
  }, []));

  useNuiEvent<ConvoyResult>("convoyResult", useCallback((data) => {
    setConvoyResult(data);
  }, []));

  const removeToast = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const clearConvoyResult = useCallback(() => {
    setConvoyResult(null);
  }, []);

  useEffect(() => {
    fetchNui("nuiReady");
  }, []);

  if (!visible) return null;

  const showArena = !convoy.active;

  return (
    <div className="hud-root">

      {/* ── ARENA MODE ─────────────────────────────────────────────────────── */}
      {showArena && defenders.length > 0 && (
        <div className="panel defender-panel">
          <div className="panel-title">
            DEFENDERS
            <span className="def-count">
              {defenders.filter(d => d.alive).length}/{defenders.length}
            </span>
          </div>
          {defenders.map((d, i) => (
            <DefenderRow key={i} info={d} />
          ))}
        </div>
      )}

      {showArena && crews.length > 0 && (
        <div className="crews-panel">
          <div className="panel-title crews-title">ACTIVE CREWS</div>
          {crews.map((c) => (
            <CrewCard key={c.owner} crew={c} />
          ))}
        </div>
      )}

      {/* ── CONVOY MODE ────────────────────────────────────────────────────── */}
      {convoy.active && (
        <>
          {/* Left panel — VIP + Escorts */}
          <div className="panel convoy-panel">
            <div className="panel-title">
              CONVOY
              <span className={`convoy-mode-badge ${convoy.mode === "aggressive" ? "aggro" : "passive"}`}>
                {convoy.mode === "aggressive" ? "AGGRESSIVE" : "PASSIVE"}
              </span>
            </div>
            {/* Progress bar */}
            <div className="convoy-progress-row">
              <div className="bar-track">
                <div
                  className="bar-fill convoy-progress-fill"
                  style={{ width: `${((convoy.progress ?? 0) * 100).toFixed(1)}%` }}
                />
              </div>
              <span className="def-pct">{Math.round((convoy.progress ?? 0) * 100)}%</span>
            </div>
            {(convoy.convoy ?? []).map((v, i) => (
              <ConvoyVehicleCard key={i} vehicle={v} />
            ))}
          </div>

          {/* Right panel — Attacker vehicles */}
          {(convoy.attackers ?? []).length > 0 && (
            <div className="crews-panel">
              <div className="panel-title crews-title">ATTACKERS</div>
              {(convoy.attackers ?? []).map((g) => (
                <ConvoyAttackerCard key={g.owner} group={g} />
              ))}
            </div>
          )}
        </>
      )}

      {/* ── TOASTS ─────────────────────────────────────────────────────────── */}
      <div className="toasts-container">
        {toasts.map((t) => (
          <ResultToast key={t.id} entry={t} onDone={removeToast} />
        ))}
        {convoyResult && (
          <ConvoyResultToast result={convoyResult} onDone={clearConvoyResult} />
        )}
      </div>

    </div>
  );
};

export default App;
