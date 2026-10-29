import { useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { api } from "../api";
import { Badge, Card, Empty, ErrorBox, Field, GroupBadge, Loading, Progress, SeverityBadge, Tabs, useAsync, useToast } from "../components/ui";
import ParticipantForm from "../components/ParticipantForm";
import MeasurementForm from "../components/MeasurementForm";
import AdverseEventForm from "../components/AdverseEventForm";
import AlertFollowUp from "../components/AlertFollowUp";
import { ApproveControls } from "../components/Approval";
import {
  AE_TYPES, ALERT_STATUS_LABEL, ALERT_TYPE_LABEL, STATUS_LABEL, STATUS_TONE, TIMEPOINT_LABEL,
  abiCategory, age, fmtDate, fmtNum, nrsCategory, today,
} from "../constants";

export default function ParticipantDetail() {
  const { id } = useParams();
  const [params, setParams] = useSearchParams();
  const navigate = useNavigate();
  const toast = useToast();
  const [editing, setEditing] = useState(false);
  const { data: p, loading, error, reload, setData } = useAsync(() => api(`/admin/participants/${id}`), [id]);

  if (loading && !p) return <Loading />;
  if (error) return <ErrorBox error={error} />;

  const interv = p.group_type === "intervensi";
  const tabs = [
    { value: "ringkasan", label: "Ringkasan" },
    ...(interv
      ? [
          { value: "jadwal", label: "Jadwal Terapi" },
          { value: "terapi", label: "Kepatuhan & Riwayat" },
        ]
      : []),
    { value: "pengukuran", label: "Pengukuran" },
    { value: "keamanan", label: "Keamanan" },
    { value: "alert", label: `Alert${p.open_alerts ? ` (${p.open_alerts})` : ""}` },
  ];
  const tab = tabs.some((t) => t.value === params.get("tab")) ? params.get("tab") : "ringkasan";

  return (
    <>
      <div className="page-head">
        <div>
          <div className="small"><Link to={`/pasien?kelompok=${p.group_type}`}>← Daftar pasien{["menunggu", "ditolak"].includes(p.status) ? "" : ` ${p.group_type}`}</Link></div>
          <h1 style={{ marginTop: 6 }}>{p.code} · {p.name}</h1>
          <div className="row" style={{ marginTop: 8 }}>
            <GroupBadge group={p.group_type} />
            <Badge tone={STATUS_TONE[p.status]}>{STATUS_LABEL[p.status]}</Badge>
            {p.phone && (
              <a className="badge info" href={`https://wa.me/${p.phone.replace(/\D/g, "").replace(/^0/, "62")}`} target="_blank" rel="noreferrer">
                WhatsApp {p.phone}
              </a>
            )}
            {p.open_alerts > 0 && <Badge tone="danger">{p.open_alerts} alert terbuka</Badge>}
          </div>
        </div>
        <button className="btn secondary" onClick={() => setEditing(true)}>Ubah data</button>
      </div>

      {["menunggu", "ditolak"].includes(p.status) && (
        <div className="card" style={{ marginBottom: 16, borderColor: "var(--warning)" }}>
          <h3 style={{ marginBottom: 4 }}>
            {p.status === "menunggu" ? "Registrasi aplikasi menunggu persetujuan" : "Registrasi ini ditolak"}
          </h3>
          <p className="small muted" style={{ marginTop: 0 }}>
            Pilih kelompok dan tanggal mulai penelitian. Setelah disetujui, pasien mendapat kode responden resmi dan
            masuk perhitungan kepatuhan, analisis, serta ekspor.
          </p>
          <ApproveControls p={p} onDone={(action) => (action === "approve" ? reload() : navigate("/pasien"))} />
        </div>
      )}

      <Tabs value={tab} onChange={(v) => setParams({ tab: v }, { replace: true })} tabs={tabs} />

      {tab === "ringkasan" && <Summary p={p} onChanged={setData} />}
      {tab === "jadwal" && <Schedules p={p} />}
      {tab === "terapi" && <Sessions p={p} />}
      {tab === "pengukuran" && <Measurements p={p} onChanged={reload} />}
      {tab === "keamanan" && <AdverseEvents p={p} onChanged={reload} />}
      {tab === "alert" && <ParticipantAlerts p={p} onChanged={reload} />}

      {editing && (
        <ParticipantForm
          initial={p}
          onClose={() => setEditing(false)}
          onSave={async (body) => {
            const updated = await api(`/admin/participants/${p.id}`, { method: "PUT", body });
            setData(updated);
            setEditing(false);
            toast("Data responden disimpan");
          }}
        />
      )}
      <div style={{ marginTop: 32 }}>
        <button
          className="btn danger sm"
          onClick={async () => {
            if (!confirm(`Hapus responden ${p.code} beserta seluruh pengukuran & alert-nya?`)) return;
            await api(`/admin/participants/${p.id}`, { method: "DELETE" });
            toast(`Responden ${p.code} dihapus`);
            navigate(`/pasien?kelompok=${p.group_type}`);
          }}
        >
          Hapus responden
        </button>
      </div>
    </>
  );
}

/* ===== RINGKASAN ===== */
function Summary({ p, onChanged }) {
  const toast = useToast();
  const bmi = p.height && p.weight ? p.weight / (p.height / 100) ** 2 : null;
  const [email, setEmail] = useState("");
  const [linkError, setLinkError] = useState(null);
  const users = useAsync(() => (p.group_type === "intervensi" && !p.user_id ? api("/admin/app-users") : Promise.resolve([])), [p.user_id]);

  const link = async (value) => {
    setLinkError(null);
    try {
      const updated = await api(`/admin/participants/${p.id}/link`, { method: "POST", body: { email: value } });
      onChanged(updated);
      toast(value ? "Akun aplikasi terhubung" : "Akun aplikasi dilepas");
    } catch (e) {
      setLinkError(e.message);
    }
  };

  const items = [
    ["Usia", age(p.birth_date) != null ? `${age(p.birth_date)} tahun` : "-"],
    ["Jenis kelamin", { L: "Laki-laki", P: "Perempuan" }[p.sex] || "-"],
    ["Lama DM", p.dm_duration_years != null ? `${fmtNum(p.dm_duration_years, 1)} tahun` : "-"],
    ["HbA1c", p.hba1c != null ? `${fmtNum(p.hba1c, 1)}%` : "-"],
    ["Gula darah", p.blood_glucose != null ? `${p.blood_glucose} mg/dL` : "-"],
    ["Tekanan darah", p.systolic ? `${p.systolic}/${p.diastolic ?? "-"} mmHg` : "-"],
    ["IMT", bmi ? `${fmtNum(bmi, 1)} kg/m²` : "-"],
    ["Merokok", p.smoking || "-"],
    ["Aktivitas fisik", p.physical_activity || "-"],
    ["Penyakit penyerta", p.comorbidities || "-"],
    ["Terapi antidiabetes", p.antidiabetic || "-"],
    ["Analgesik", p.analgesic || "-"],
    ["Obat neuropati", p.neuropathy_drug || "-"],
  ];

  return (
    <div className="grid grid-2">
      <Card title="Karakteristik responden">
        <dl className="kv">
          {items.map(([k, v]) => (
            <FragmentKV key={k} k={k} v={v} />
          ))}
        </dl>
        {p.notes && <p className="small muted" style={{ marginBottom: 0 }}>{p.notes}</p>}
      </Card>

      <div>
        <Card title="Penelitian">
          <dl className="kv">
            <FragmentKV k="Mulai penelitian" v={fmtDate(p.study_start)} />
            <FragmentKV k="Post-test (4 minggu)" v={fmtDate(p.post_due)} />
            <FragmentKV k="Pre-test" v={p.pre_at ? fmtDate(p.pre_at) : "Belum"} />
            <FragmentKV k="Post-test" v={p.post_at ? fmtDate(p.post_at) : "Belum"} />
            {p.group_type === "intervensi" && <FragmentKV k="Sesi direncanakan" v={p.planned_sessions} />}
          </dl>
          {p.group_type === "intervensi" && p.user_id && (
            <div style={{ marginTop: 14 }}>
              <div className="row small" style={{ justifyContent: "space-between" }}>
                <span>Kepatuhan: {p.compliance.completed} dari {p.compliance.planned} sesi selesai</span>
                <b className="num">{fmtNum(p.compliance.percent, 1)}%</b>
              </div>
              <Progress percent={p.compliance.percent} />
            </div>
          )}
        </Card>

        {p.group_type === "intervensi" && (
          <Card title="Akun aplikasi pasien">
            {p.user_id ? (
              <div className="row">
                <span>Terhubung ke <b>{p.email}</b></span>
                <span className="spacer" />
                <button className="btn ghost sm" onClick={() => confirm("Lepas akun aplikasi dari responden ini?") && link("")}>Lepas</button>
              </div>
            ) : (
              <>
                <p className="small muted" style={{ marginTop: 0 }}>
                  Hubungkan dengan akun yang didaftarkan pasien di aplikasi SWAVINA agar jadwal dan riwayat terapi tersinkron.
                </p>
                <div className="row">
                  <select value={email} onChange={(e) => setEmail(e.target.value)} style={{ flex: 1, minWidth: 200 }}>
                    <option value="">Pilih akun pasien…</option>
                    {(users.data || []).map((u) => (
                      <option key={u.id} value={u.email}>{u.name ? `${u.name} — ` : ""}{u.email}{u.auto_code ? ` (otomatis ${u.auto_code}, akan digabung)` : ""}</option>
                    ))}
                  </select>
                  <button className="btn" disabled={!email} onClick={() => link(email)}>Hubungkan</button>
                </div>
                <div style={{ marginTop: 8 }}><ErrorBox error={linkError} /></div>
              </>
            )}
          </Card>
        )}
      </div>
    </div>
  );
}

const FragmentKV = ({ k, v }) => (
  <>
    <dt>{k}</dt>
    <dd>{v}</dd>
  </>
);

/* ===== JADWAL TERAPI ===== */
function Schedules({ p }) {
  const toast = useToast();
  const [form, setForm] = useState({ date: today(), time: "08:00", duration: 30, temperature: 38, vibration: 45, repeat_days: 28 });
  const [error, setError] = useState(null);
  const { data, loading, error: loadError, reload } = useAsync(
    () => (p.user_id ? api(`/admin/participants/${p.id}/schedules`) : Promise.resolve([])),
    [p.id, p.user_id]
  );
  if (!p.user_id) {
    return <Card><Empty>Hubungkan responden dengan akun aplikasi (tab Ringkasan) sebelum mengatur jadwal.</Empty></Card>;
  }
  const set = (k) => (e) => setForm((s) => ({ ...s, [k]: e.target.value }));

  const submit = async (e) => {
    e.preventDefault();
    setError(null);
    try {
      const r = await api(`/admin/participants/${p.id}/schedules`, { method: "POST", body: form });
      toast(`${r.created} jadwal dibuat`);
      reload();
    } catch (err) {
      setError(err.message);
    }
  };

  const upcoming = (data || []).filter((s) => s.date >= today());
  const past = (data || []).filter((s) => s.date < today());

  return (
    <div className="grid grid-2">
      <Card title="Atur jadwal terapi">
        <form onSubmit={submit} className="grid">
          <div className="form-grid">
            <Field label="Mulai tanggal"><input type="date" value={form.date} onChange={set("date")} required /></Field>
            <Field label="Jam"><input type="time" value={form.time} onChange={set("time")} required /></Field>
            <Field label="Ulangi (hari berturut-turut)" hint="28 = 4 minggu"><input type="number" min="1" max="60" value={form.repeat_days} onChange={set("repeat_days")} /></Field>
            <Field label="Durasi (menit)"><input type="number" min="1" max="60" value={form.duration} onChange={set("duration")} required /></Field>
            <Field label="Suhu (°C)" hint="34–40°C, maks. 40°C"><input type="number" min="30" max="40" value={form.temperature} onChange={set("temperature")} /></Field>
            <Field label="Vibrasi (Hz)" hint="35–50 Hz"><input type="number" min="30" max="60" value={form.vibration} onChange={set("vibration")} /></Field>
          </div>
          <ErrorBox error={error} />
          <div><button className="btn">Simpan jadwal</button></div>
          <p className="small muted" style={{ margin: 0 }}>Jadwal langsung muncul di menu Schedule aplikasi pasien.</p>
        </form>
      </Card>

      <Card title={`Jadwal mendatang (${upcoming.length})`}>
        <ErrorBox error={loadError} />
        {loading && !data ? <Loading /> : upcoming.length === 0 ? <Empty>Belum ada jadwal mendatang.</Empty> : (
          <div className="table-wrap" style={{ maxHeight: 420, overflowY: "auto" }}>
            <table>
              <thead><tr><th>Tanggal</th><th>Jam</th><th>Parameter</th><th /></tr></thead>
              <tbody>
                {upcoming.map((s) => (
                  <tr key={s.id}>
                    <td>{fmtDate(s.date)}</td>
                    <td className="num">{String(s.time).slice(0, 5)}</td>
                    <td className="small">{s.duration} mnt · {s.temperature}°C · {s.vibration} Hz</td>
                    <td className="right">
                      <button className="btn ghost sm" onClick={async () => {
                        await api(`/admin/participants/${p.id}/schedules/${s.id}`, { method: "DELETE" });
                        reload();
                      }}>Hapus</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {past.length > 0 && <p className="small muted" style={{ marginBottom: 0 }}>{past.length} jadwal sudah lewat.</p>}
      </Card>
    </div>
  );
}

/* ===== KEPATUHAN & RIWAYAT TERAPI ===== */
function Sessions({ p }) {
  const { data, loading, error } = useAsync(() => api(`/admin/participants/${p.id}/sessions`), [p.id]);
  const c = p.compliance;
  return (
    <>
      <div className="grid grid-4">
        <Card><div className="stat"><span className="label">Kepatuhan</span><span className="value">{c.percent == null ? "–" : `${fmtNum(c.percent, 1)}%`}</span><Progress percent={c.percent} /></div></Card>
        <Card><div className="stat"><span className="label">Sesi selesai</span><span className="value">{c.completed}</span><span className="sub">dari {c.planned} direncanakan</span></div></Card>
        <Card><div className="stat"><span className="label">Dihentikan</span><span className="value">{c.stopped}</span><span className="sub">sebelum durasi target</span></div></Card>
        <Card><div className="stat"><span className="label">Sesi terakhir</span><span className="value" style={{ fontSize: 18 }}>{c.last_session ? fmtDate(c.last_session) : "–"}</span></div></Card>
      </div>
      <Card title="Riwayat sesi terapi" style={{ marginTop: 16 }}>
        <ErrorBox error={error} />
        {!p.user_id ? <Empty>Belum terhubung ke akun aplikasi.</Empty> : loading && !data ? <Loading /> : data.length === 0 ? <Empty>Belum ada sesi terapi.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Tanggal</th><th>Durasi</th><th>Status</th><th>Setting</th><th>Suhu aktual</th><th>Koneksi</th></tr>
              </thead>
              <tbody>
                {data.map((s) => (
                  <tr key={s.id}>
                    <td>{fmtDate(s.date)} <span className="muted num">{String(s.start_time || "").slice(0, 5)}</span></td>
                    <td className="num">{s.duration}{s.target_duration ? ` / ${s.target_duration}` : ""} mnt</td>
                    <td>
                      {s.status === "stopped"
                        ? <Badge tone="warning">Dihentikan</Badge>
                        : <Badge tone="success">Selesai</Badge>}
                      {s.stop_reason && <div className="small muted">{s.stop_reason}</div>}
                    </td>
                    <td className="small">{s.temperature}°C · {s.vibration} Hz</td>
                    <td className="small num">
                      {s.max_temp != null ? (
                        <span style={{ color: s.max_temp > 40 ? "var(--danger)" : undefined, fontWeight: s.max_temp > 40 ? 700 : 400 }}>
                          maks {fmtNum(s.max_temp, 1)}°C
                        </span>
                      ) : "-"}
                      {s.avg_vib != null && <div className="muted">getar {fmtNum(s.avg_vib, 1)} Hz</div>}
                    </td>
                    <td className="small">{s.transport || "-"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}

/* ===== PENGUKURAN KLINIS ===== */
function Measurements({ p, onChanged }) {
  const toast = useToast();
  const [form, setForm] = useState(null);
  const { data, loading, error, reload } = useAsync(() => api(`/admin/participants/${p.id}/measurements`), [p.id]);
  const list = data || [];
  const latest = (tp) => [...list].reverse().find((m) => m.timepoint === tp);
  const pre = latest("pre");
  const post = latest("post");

  const rows = [
    { key: "abi_left", label: "ABI kiri", d: 2, better: "up" },
    { key: "abi_right", label: "ABI kanan", d: 2, better: "up" },
    { key: "ntss6_total", label: "NTSS-6", d: 2, better: "down" },
    { key: "dn4_total", label: "DN4", d: 0, better: "down" },
    { key: "nrs", label: "NRS", d: 0, better: "down" },
    { key: "skin_temp_left", label: "Suhu kulit kiri (°C)", d: 1 },
    { key: "skin_temp_right", label: "Suhu kulit kanan (°C)", d: 1 },
    { key: "lactate", label: "Laktat (mmol/L)", d: 2, better: "down" },
  ];

  const save = async (body) => {
    if (form.id) await api(`/admin/measurements/${form.id}`, { method: "PUT", body });
    else await api(`/admin/participants/${p.id}/measurements`, { method: "POST", body });
    toast("Pengukuran disimpan");
    setForm(null);
    reload();
    onChanged();
  };

  return (
    <>
      <Card
        title="Perbandingan pre-test vs post-test"
        actions={
          <>
            <button className="btn secondary" onClick={() => setForm({ timepoint: "pre", measured_at: today() })}>+ Pre-test</button>
            <button className="btn" onClick={() => setForm({ timepoint: "post", measured_at: today() })}>+ Post-test</button>
          </>
        }
      >
        <ErrorBox error={error} />
        {loading && !data ? <Loading /> : !pre && !post ? <Empty>Belum ada pengukuran. Input pre-test pada kunjungan awal.</Empty> : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Outcome</th><th className="right">Pre {pre ? `(${fmtDate(pre.measured_at)})` : ""}</th><th className="right">Post {post ? `(${fmtDate(post.measured_at)})` : ""}</th><th className="right">Δ</th></tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const a = pre?.[r.key];
                  const b = post?.[r.key];
                  const delta = a != null && b != null ? b - a : null;
                  const good = delta == null || !r.better || delta === 0 ? null : (r.better === "up") === delta > 0;
                  return (
                    <tr key={r.key}>
                      <td>{r.label}</td>
                      <td className="right num">{fmtNum(a, r.d)}</td>
                      <td className="right num">{fmtNum(b, r.d)}</td>
                      <td className="right num" style={{ color: good == null ? undefined : good ? "var(--success)" : "var(--danger)", fontWeight: 650 }}>
                        {delta == null ? "-" : `${delta > 0 ? "+" : ""}${fmtNum(delta, r.d)}`}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card title={`Semua kunjungan pengukuran (${list.length})`}>
        {list.length === 0 ? <Empty>-</Empty> : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr><th>Tanggal</th><th>Waktu</th><th>ABI kiri / kanan</th><th>NTSS-6</th><th>DN4</th><th>NRS</th><th>Suhu kulit K / Ka</th><th>Laktat</th><th /></tr>
              </thead>
              <tbody>
                {[...list].reverse().map((m) => {
                  const al = abiCategory(m.abi_left);
                  const ar = abiCategory(m.abi_right);
                  const asym = m.skin_temp_left != null && m.skin_temp_right != null && Math.abs(m.skin_temp_left - m.skin_temp_right) >= 2.2;
                  return (
                    <tr key={m.id}>
                      <td>{fmtDate(m.measured_at)}</td>
                      <td><Badge tone={m.timepoint === "post" ? "info" : ""}>{TIMEPOINT_LABEL[m.timepoint]}</Badge></td>
                      <td className="num">
                        {fmtNum(m.abi_left)} {al && <Badge tone={al.tone}>{al.label}</Badge>}<br />
                        {fmtNum(m.abi_right)} {ar && <Badge tone={ar.tone}>{ar.label}</Badge>}
                      </td>
                      <td className="num">{fmtNum(m.ntss6_total)}</td>
                      <td className="num">{m.dn4_total ?? "-"}{m.dn4_total >= 4 && <div><Badge tone="warning">Neuropatik</Badge></div>}</td>
                      <td className="num">{m.nrs ?? "-"}<div className="small muted">{nrsCategory(m.nrs)}</div></td>
                      <td className="num">
                        {fmtNum(m.skin_temp_left, 1)} / {fmtNum(m.skin_temp_right, 1)}
                        {asym && <div><Badge tone="warning">Asimetris</Badge></div>}
                      </td>
                      <td className="num">{fmtNum(m.lactate)}</td>
                      <td className="right" style={{ whiteSpace: "nowrap" }}>
                        <button className="btn ghost sm" onClick={() => setForm(m)}>Ubah</button>
                        <button className="btn ghost sm" style={{ color: "var(--danger)" }} onClick={async () => {
                          if (!confirm("Hapus pengukuran ini?")) return;
                          await api(`/admin/measurements/${m.id}`, { method: "DELETE" });
                          reload();
                          onChanged();
                        }}>Hapus</button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {form && <MeasurementForm initial={form} participant={p} onClose={() => setForm(null)} onSave={save} />}
    </>
  );
}

/* ===== FORMULIR KEAMANAN ===== */
function AdverseEvents({ p, onChanged }) {
  const toast = useToast();
  const [adding, setAdding] = useState(false);
  const { data, loading, error, reload } = useAsync(() => api(`/admin/participants/${p.id}/adverse-events`), [p.id]);
  const label = (k) => AE_TYPES.find((t) => t.key === k)?.label || k;
  return (
    <Card title="Formulir keamanan / kejadian tidak diinginkan" actions={<button className="btn" onClick={() => setAdding(true)}>+ Catat kejadian</button>}>
      <ErrorBox error={error} />
      {loading && !data ? <Loading /> : data.length === 0 ? <Empty>Tidak ada kejadian tidak diinginkan tercatat.</Empty> : (
        <div className="table-wrap">
          <table>
            <thead><tr><th>Tanggal</th><th>Kejadian</th><th>Keparahan</th><th>Tindakan</th><th>Keputusan</th><th /></tr></thead>
            <tbody>
              {data.map((e) => (
                <tr key={e.id}>
                  <td>{fmtDate(e.occurred_at)}</td>
                  <td>{e.types.map(label).join(", ") || "-"}{e.description && <div className="small muted">{e.description}</div>}</td>
                  <td><Badge tone={{ ringan: "", sedang: "warning", berat: "danger" }[e.severity]}>{e.severity}</Badge></td>
                  <td className="small">{e.action_taken || "-"}</td>
                  <td><Badge tone={e.decision === "hentikan" ? "danger" : "success"}>{e.decision === "hentikan" ? "Hentikan intervensi" : "Lanjutkan"}</Badge></td>
                  <td className="right">
                    <button className="btn ghost sm" style={{ color: "var(--danger)" }} onClick={async () => {
                      if (!confirm("Hapus catatan ini?")) return;
                      await api(`/admin/adverse-events/${e.id}`, { method: "DELETE" });
                      reload();
                    }}>Hapus</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {adding && (
        <AdverseEventForm
          onClose={() => setAdding(false)}
          onSave={async (body) => {
            await api(`/admin/participants/${p.id}/adverse-events`, { method: "POST", body });
            toast("Kejadian dicatat");
            setAdding(false);
            reload();
            onChanged();
          }}
        />
      )}
    </Card>
  );
}

/* ===== ALERT PASIEN ===== */
function ParticipantAlerts({ p, onChanged }) {
  const [active, setActive] = useState(null);
  const { data, loading, error, reload } = useAsync(() => api(`/admin/alerts?participant_id=${p.id}`), [p.id]);
  return (
    <Card title="Alert klinis">
      <ErrorBox error={error} />
      {loading && !data ? <Loading /> : data.length === 0 ? <Empty>Tidak ada alert untuk responden ini.</Empty> : data.map((a) => (
        <div className="alert-item" key={a.id}>
          <span className={`alert-dot ${a.severity}`} />
          <div style={{ flex: 1 }}>
            <div className="row">
              <b>{ALERT_TYPE_LABEL[a.type] || a.type}</b>
              <SeverityBadge severity={a.severity} />
              <Badge tone={a.status === "resolved" ? "success" : a.status === "acknowledged" ? "info" : "danger"}>{ALERT_STATUS_LABEL[a.status]}</Badge>
            </div>
            <div className="small">{a.message}</div>
            <div className="small muted">{fmtDate(a.created_at)}</div>
            {a.follow_up_note && <div className="small" style={{ marginTop: 4 }}>Tindak lanjut: {a.follow_up_note} <span className="muted">— {a.handled_by_name || ""} {fmtDate(a.handled_at)}</span></div>}
          </div>
          {a.status !== "resolved" && <button className="btn secondary sm" onClick={() => setActive(a)}>Tindak lanjut</button>}
        </div>
      ))}
      {active && <AlertFollowUp alert={active} onClose={() => setActive(null)} onDone={() => { setActive(null); reload(); onChanged(); }} />}
    </Card>
  );
}
