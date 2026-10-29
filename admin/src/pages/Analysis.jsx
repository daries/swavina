import { useState } from "react";
import { api, downloadCsv } from "../api";
import { Card, Empty, ErrorBox, Loading, useAsync, useToast } from "../components/ui";
import { fmtNum } from "../constants";

const EXPORTS = [
  { path: "/admin/export/dataset.csv", name: "dataset.csv", title: "Dataset analisis", desc: "1 baris per responden: kelompok (1/0), karakteristik, kepatuhan, nilai pre, post, dan Δ tiap outcome. Siap untuk SPSS / SmartPLS." },
  { path: "/admin/export/measurements.csv", name: "pengukuran.csv", title: "Semua pengukuran", desc: "Format panjang, termasuk tekanan Doppler untuk ABI." },
  { path: "/admin/export/sessions.csv", name: "sesi_terapi.csv", title: "Log sesi terapi", desc: "Tanggal, durasi, status selesai/dihentikan, suhu & getar setting dan aktual." },
  { path: "/admin/export/adverse-events.csv", name: "keamanan.csv", title: "Formulir keamanan", desc: "Kejadian tidak diinginkan, tindakan, dan keputusan." },
];

export default function Analysis() {
  const toast = useToast();
  const [busy, setBusy] = useState(null);
  const { data, loading, error } = useAsync(() => api("/admin/analysis"));

  const exportCsv = async (e) => {
    setBusy(e.path);
    try {
      await downloadCsv(e.path, e.name);
      toast(`${e.title} diunduh`);
    } catch (err) {
      toast(err.message);
    } finally {
      setBusy(null);
    }
  };

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Analisis & Ekspor</h1>
          <p>Perbandingan pre–post dan intervensi–kontrol (deskriptif). Uji statistik dilakukan dari data ekspor.</p>
        </div>
      </div>

      <Card title="Perbandingan outcome">
        <ErrorBox error={error} />
        {loading && !data ? <Loading /> : (
          <>
            <p className="small muted" style={{ marginTop: 0 }}>
              Responden: intervensi {data.n.intervensi} (pasangan pre–post lengkap {data.complete_pairs.intervensi}) ·
              kontrol {data.n.kontrol} (lengkap {data.complete_pairs.kontrol}). Nilai = rerata ± SD; Δ = post − pre per responden.
            </p>
            {data.complete_pairs.intervensi + data.complete_pairs.kontrol === 0 ? (
              <Empty>Belum ada responden dengan pengukuran pre dan post lengkap.</Empty>
            ) : null}
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th rowSpan={2}>Outcome</th>
                    <th colSpan={3} style={{ color: "var(--interv)" }}>Intervensi</th>
                    <th colSpan={3} style={{ color: "var(--kontrol)" }}>Kontrol</th>
                    <th rowSpan={2} className="right">Selisih Δ<br />(int − kon)</th>
                  </tr>
                  <tr>
                    <th className="right">Pre</th><th className="right">Post</th><th className="right">Δ</th>
                    <th className="right">Pre</th><th className="right">Post</th><th className="right">Δ</th>
                  </tr>
                </thead>
                <tbody>
                  {data.outcomes.map((o) => (
                    <tr key={o.key}>
                      <td>{o.label}</td>
                      {["intervensi", "kontrol"].map((g) => (
                        ["pre", "post", "delta"].map((k) => (
                          <td key={g + k} className="right num">
                            <Stat s={o.groups[g][k]} bold={k === "delta"} />
                          </td>
                        ))
                      ))}
                      <td className="right num"><b>{o.diff_in_delta == null ? "-" : `${o.diff_in_delta > 0 ? "+" : ""}${fmtNum(o.diff_in_delta, 3)}`}</b></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <DeltaChart outcomes={data.outcomes} />
          </>
        )}
      </Card>

      <Card title="Ekspor data untuk analisis statistik">
        <div className="grid grid-2">
          {EXPORTS.map((e) => (
            <div key={e.path} className="card" style={{ boxShadow: "none", margin: 0 }}>
              <h3>{e.title}</h3>
              <p className="small muted">{e.desc}</p>
              <button className="btn secondary" disabled={busy === e.path} onClick={() => exportCsv(e)}>
                {busy === e.path ? "Mengunduh…" : "Unduh CSV"}
              </button>
            </div>
          ))}
        </div>
      </Card>
    </>
  );
}

function Stat({ s, bold }) {
  if (!s || s.n === 0 || s.mean == null) return <span className="muted">-</span>;
  const v = fmtNum(s.mean, 3);
  return (
    <span style={{ fontWeight: bold ? 650 : 400 }}>
      {v}
      {s.sd != null && <span className="muted small"> ±{fmtNum(s.sd, 2)}</span>}
      <div className="muted small">n={s.n}</div>
    </span>
  );
}

/** Grafik batang Δ rerata per kelompok (skala relatif per outcome). */
function DeltaChart({ outcomes }) {
  const rows = outcomes.filter((o) => o.groups.intervensi.delta.mean != null || o.groups.kontrol.delta.mean != null);
  if (!rows.length) return null;
  return (
    <div style={{ marginTop: 20 }}>
      <h3 style={{ marginBottom: 4 }}>Rerata perubahan (Δ) per kelompok</h3>
      <div className="row small muted" style={{ marginBottom: 10 }}>
        <span><span className="badge intervensi">Intervensi</span></span>
        <span><span className="badge kontrol">Kontrol</span></span>
        <span>Batang ke kanan = naik, ke kiri = turun</span>
      </div>
      <div className="grid" style={{ gap: 14 }}>
        {rows.map((o) => {
          const vals = ["intervensi", "kontrol"].map((g) => o.groups[g].delta.mean);
          const max = Math.max(...vals.map((v) => Math.abs(v ?? 0))) || 1;
          return (
            <div key={o.key}>
              <div className="small" style={{ fontWeight: 600, marginBottom: 4 }}>{o.label}</div>
              {["intervensi", "kontrol"].map((g, i) => {
                const v = vals[i];
                const w = v == null ? 0 : (Math.abs(v) / max) * 50;
                return (
                  <div className="bar-compare" key={g}>
                    <span className="muted">{g === "intervensi" ? "Intervensi" : "Kontrol"}</span>
                    <div className="track">
                      <div style={{ position: "absolute", left: "50%", top: 0, bottom: 0, width: 1, background: "var(--border)" }} />
                      {v != null && (
                        <div className="fill" style={{
                          background: g === "intervensi" ? "var(--interv)" : "var(--kontrol)",
                          width: `${w}%`, left: v >= 0 ? "50%" : `${50 - w}%`,
                        }} />
                      )}
                    </div>
                    <span className="num right">{v == null ? "-" : `${v > 0 ? "+" : ""}${fmtNum(v, 3)}`}</span>
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>
    </div>
  );
}
