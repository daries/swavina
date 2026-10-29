import { useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../api";
import { Badge, Card, Empty, ErrorBox, Loading, useAsync, useToast } from "./ui";
import { fmtDate, today } from "../constants";

/** Kontrol setujui / tolak untuk satu registrasi. */
export function ApproveControls({ p, onDone, compact = false }) {
  const toast = useToast();
  // Aturan: pasien yang sudah melakukan terapi SWAVINA → kelompok intervensi.
  const sessions = p.sessions ?? p.compliance?.sessions ?? 0;
  const [group, setGroup] = useState("intervensi");
  const [start, setStart] = useState(p.study_start || today());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const run = async (action) => {
    if (action === "reject" && !confirm(`Tolak ${p.name} sebagai responden? Pasien tetap bisa memakai aplikasi.`)) return;
    setBusy(true);
    setError(null);
    try {
      const res = await api(`/admin/participants/${p.id}/${action}`, {
        method: "POST",
        body: action === "approve" ? { group_type: group, study_start: start || null } : {},
      });
      toast(action === "approve" ? `${p.name} disetujui sebagai ${res.code}` : `${p.name} ditolak`);
      onDone?.(action, res);
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  };

  return (
    <div className="grid" style={{ gap: 8 }}>
      <div className="row">
        <select value={group} onChange={(e) => setGroup(e.target.value)} style={{ width: compact ? 150 : 180 }} aria-label="Kelompok"
          disabled={sessions > 0} title={sessions > 0 ? "Sudah melakukan terapi → kelompok intervensi" : undefined}>
          <option value="intervensi">Intervensi</option>
          <option value="kontrol">Kontrol</option>
        </select>
        <input type="date" value={start} onChange={(e) => setStart(e.target.value)} style={{ width: 160 }}
          aria-label="Mulai penelitian" title="Mulai penelitian" />
        <button className="btn sm" disabled={busy} onClick={() => run("approve")}>Setujui</button>
        {p.status === "menunggu" && (
          <button className="btn danger sm" disabled={busy} onClick={() => run("reject")}>Tolak</button>
        )}
      </div>
      {sessions > 0 && (
        <div className="small muted">Sudah {sessions} sesi terapi → otomatis kelompok intervensi.</div>
      )}
      <ErrorBox error={error} />
    </div>
  );
}

/** Kartu antrean registrasi aplikasi yang menunggu persetujuan peneliti/perawat. */
export function PendingApprovals({ onChanged }) {
  const [showRejected, setShowRejected] = useState(false);
  const pending = useAsync(() => api("/admin/approvals"));
  const rejected = useAsync(() => (showRejected ? api("/admin/approvals?status=ditolak") : Promise.resolve([])), [showRejected]);

  const done = () => {
    pending.reload();
    if (showRejected) rejected.reload();
    onChanged?.();
  };

  if (pending.loading && !pending.data) return null;
  const list = pending.data || [];
  if (!list.length && !showRejected) {
    return (
      <div className="row small muted" style={{ marginBottom: 12 }}>
        <span>Tidak ada registrasi yang menunggu persetujuan.</span>
        <button className="btn ghost sm" onClick={() => setShowRejected(true)}>Lihat yang ditolak</button>
      </div>
    );
  }

  return (
    <Card
      title={
        <div className="row">
          <h2>Menunggu persetujuan</h2>
          {list.length > 0 && <Badge tone="warning">{list.length}</Badge>}
        </div>
      }
      actions={
        <button className="btn ghost sm" onClick={() => setShowRejected((v) => !v)}>
          {showRejected ? "Sembunyikan yang ditolak" : "Lihat yang ditolak"}
        </button>
      }
      style={{ marginBottom: 16, borderColor: list.length ? "var(--warning)" : undefined }}
    >
      <p className="small muted" style={{ marginTop: 0 }}>
        Pasien yang registrasi lewat aplikasi. Setelah disetujui, pasien dihitung sebagai responden dan mendapat kode resmi.
        Pasien tetap bisa memakai aplikasi selama menunggu.
      </p>
      <ErrorBox error={pending.error} />
      {list.length === 0 ? <Empty>Tidak ada registrasi baru.</Empty> : list.map((p) => <ApprovalItem key={p.id} p={p} onDone={done} />)}

      {showRejected && (
        <div style={{ marginTop: 12 }}>
          <h3 style={{ marginBottom: 6 }}>Ditolak</h3>
          {rejected.loading && !rejected.data ? <Loading /> : (rejected.data || []).length === 0 ? (
            <div className="small muted">Tidak ada.</div>
          ) : (
            rejected.data.map((p) => <ApprovalItem key={p.id} p={p} onDone={done} />)
          )}
        </div>
      )}
    </Card>
  );
}

function ApprovalItem({ p, onDone }) {
  return (
    <div className="alert-item" style={{ flexWrap: "wrap", alignItems: "center" }}>
      <div style={{ flex: "1 1 220px", minWidth: 0 }}>
        <div className="row">
          <b><Link to={`/pasien/${p.id}`}>{p.name}</Link></b>
          {p.status === "ditolak" && <Badge tone="danger">Ditolak</Badge>}
        </div>
        <div className="small muted">
          {p.email || "-"} · registrasi {fmtDate(p.registered_at)} · {p.sessions} sesi terapi
        </div>
      </div>
      <ApproveControls p={p} onDone={onDone} compact />
    </div>
  );
}
