import { Link, useNavigate } from "react-router-dom";
import { api } from "../api";
import { useAuth } from "../App";
import { Badge, Card, Empty, ErrorBox, GroupBadge, Loading, SeverityBadge, useAsync } from "../components/ui";
import { ALERT_TYPE_LABEL, GROUP_LABEL, fmtDate, fmtNum } from "../constants";

export default function Dashboard() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const { data, loading, error } = useAsync(() => api("/admin/summary"));

  if (loading && !data) return <Loading />;
  if (error) return <ErrorBox error={error} />;

  const g = (name) => data.groups.find((x) => x.group === name) || {};

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Halo, {user.name.split(" ")[0]}</h1>
          <p>Ringkasan penelitian SWAVINA — Puskesmas Gambirsari</p>
        </div>
        <Link className="btn" to="/pasien">Pilih kelompok &amp; pasien</Link>
      </div>

      {data.pending_approvals > 0 && (
        <Link to="/pasien" className="card" style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 16, borderColor: "var(--warning)", color: "var(--text)", textDecoration: "none" }}>
          <Badge tone="warning">{data.pending_approvals}</Badge>
          <span><b>Registrasi aplikasi menunggu persetujuan</b> — setujui sebagai responden & pilih kelompoknya.</span>
          <span className="spacer" />
          <span style={{ color: "var(--accent)", fontWeight: 650 }}>Tinjau →</span>
        </Link>
      )}

      <div className="grid grid-4">
        {["intervensi", "kontrol"].map((name) => (
          <Card key={name}>
            <div className="stat">
              <span className="label">Kelompok {GROUP_LABEL[name]}</span>
              <span className="value">{g(name).total ?? 0}</span>
              <span className="sub">
                {g(name).active} aktif · pre {g(name).pre_done} · post {g(name).post_done}
              </span>
            </div>
          </Card>
        ))}
        <Card>
          <div className="stat">
            <span className="label">Rata-rata kepatuhan intervensi</span>
            <span className="value">{data.avg_compliance == null ? "–" : `${fmtNum(data.avg_compliance, 1)}%`}</span>
            <span className="sub">sesi selesai ÷ sesi direncanakan</span>
          </div>
        </Card>
        <Card>
          <div className="stat">
            <span className="label">Alert klinis terbuka</span>
            <span className="value" style={{ color: data.open_alerts ? "var(--danger)" : undefined }}>{data.open_alerts}</span>
            <span className="sub">{data.critical_alerts} kritis</span>
          </div>
        </Card>
      </div>

      <div className="grid grid-2" style={{ marginTop: 16 }}>
        <Card title="Alert klinis terbaru" actions={<Link to="/alert" className="btn ghost sm">Lihat semua</Link>}>
          {data.recent_alerts.length === 0 ? (
            <Empty>Tidak ada alert terbuka.</Empty>
          ) : (
            data.recent_alerts.map((a) => (
              <div className="alert-item" key={a.id}>
                <span className={`alert-dot ${a.severity}`} />
                <div style={{ flex: 1 }}>
                  <div className="row">
                    <b>{ALERT_TYPE_LABEL[a.type] || a.type}</b>
                    <SeverityBadge severity={a.severity} />
                  </div>
                  <div className="small">{a.message}</div>
                  <div className="small muted">
                    <Link to={`/pasien/${a.participant_id}`}>{a.code} · {a.name}</Link> · {fmtDate(a.created_at)}
                  </div>
                </div>
              </div>
            ))
          )}
        </Card>

        <Card title="Jadwal kunjungan pengukuran">
          {data.visits.length === 0 ? (
            <Empty>Tidak ada kunjungan pengukuran dalam 7 hari ke depan.</Empty>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr><th>Responden</th><th>Kelompok</th><th>Pengukuran</th><th>Jatuh tempo</th></tr>
                </thead>
                <tbody>
                  {data.visits.map((v) => (
                    <tr key={`${v.id}-${v.visit}`} className="clickable" onClick={() => navigate(`/pasien/${v.id}?tab=pengukuran`)}>
                      <td><b>{v.code}</b><div className="small muted">{v.name}</div></td>
                      <td><GroupBadge group={v.group_type} /></td>
                      <td>{v.visit === "pre" ? "Pre-test" : "Post-test"}</td>
                      <td>
                        {v.due ? fmtDate(v.due) : "Belum dijadwalkan"}{" "}
                        {v.overdue && <Badge tone="danger">Terlewat</Badge>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
