import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { api } from "../api";
import { Badge, Card, Empty, ErrorBox, Loading, Progress, Segmented, useAsync, useToast } from "../components/ui";
import ParticipantForm from "../components/ParticipantForm";
import { PendingApprovals } from "../components/Approval";
import { GROUP_LABEL, STATUS_LABEL, STATUS_TONE, fmtDate, fmtNum } from "../constants";

export default function Participants() {
  const [params, setParams] = useSearchParams();
  const group = params.get("kelompok") || "intervensi";
  const [q, setQ] = useState("");
  const [adding, setAdding] = useState(false);
  const navigate = useNavigate();
  const toast = useToast();

  const { data, loading, error, reload } = useAsync(
    () => api(`/admin/participants?group=${group}`),
    [group]
  );

  const list = (data || []).filter(
    (p) => !q || `${p.code} ${p.name}`.toLowerCase().includes(q.toLowerCase())
  );

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Daftar Pasien</h1>
          <p>Pilih kelompok, lalu pilih pasien untuk mengatur jadwal, melihat kepatuhan, dan menginput pengukuran.</p>
        </div>
        <button className="btn" onClick={() => setAdding(true)}>+ Tambah responden</button>
      </div>

      <PendingApprovals onChanged={reload} />

      <Card
        title={
          <Segmented
            value={group}
            onChange={(v) => setParams({ kelompok: v })}
            options={[
              { value: "intervensi", label: "Kelompok Intervensi" },
              { value: "kontrol", label: "Kelompok Kontrol" },
            ]}
          />
        }
        actions={
          <input type="search" placeholder="Cari kode / nama…" value={q} onChange={(e) => setQ(e.target.value)} style={{ width: 220 }} />
        }
      >
        <ErrorBox error={error} />
        {loading && !data ? (
          <Loading />
        ) : list.length === 0 ? (
          <Empty>Belum ada responden kelompok {GROUP_LABEL[group].toLowerCase()}.</Empty>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Responden</th>
                  <th>Status</th>
                  {group === "intervensi" && <th style={{ minWidth: 160 }}>Kepatuhan</th>}
                  {group === "intervensi" && <th>Sesi terakhir</th>}
                  <th>Pre / Post</th>
                  <th className="right">Alert</th>
                </tr>
              </thead>
              <tbody>
                {list.map((p) => (
                  <tr key={p.id} className="clickable" onClick={() => navigate(`/pasien/${p.id}`)}>
                    <td>
                      <b>{p.code}</b>
                      <div className="small muted">{p.name}</div>
                    </td>
                    <td>
                      <Badge tone={STATUS_TONE[p.status]}>
                        {STATUS_LABEL[p.status] || p.status}
                      </Badge>
                    </td>
                    {group === "intervensi" && (
                      <td>
                        {p.user_id ? (
                          <>
                            <div className="row small num" style={{ justifyContent: "space-between" }}>
                              <span>{p.compliance.completed}/{p.compliance.planned} sesi</span>
                              <b>{fmtNum(p.compliance.percent, 1)}%</b>
                            </div>
                            <Progress percent={p.compliance.percent} />
                          </>
                        ) : (
                          <span className="small muted">Belum terhubung ke aplikasi</span>
                        )}
                      </td>
                    )}
                    {group === "intervensi" && <td className="small">{p.compliance.last_session ? fmtDate(p.compliance.last_session) : "-"}</td>}
                    <td className="row">
                      <Badge tone={p.pre_at ? "success" : ""}>Pre {p.pre_at ? "✓" : "–"}</Badge>
                      <Badge tone={p.post_at ? "success" : ""}>Post {p.post_at ? "✓" : "–"}</Badge>
                    </td>
                    <td className="right">
                      {p.open_alerts > 0 ? <Badge tone="danger">{p.open_alerts}</Badge> : <span className="muted">–</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {adding && (
        <ParticipantForm
          initial={{ group_type: group, planned_sessions: 28, status: "aktif" }}
          onClose={() => setAdding(false)}
          onSave={async (body) => {
            const p = await api("/admin/participants", { method: "POST", body });
            toast(`Responden ${p.code} ditambahkan`);
            setAdding(false);
            if (p.group_type !== group) setParams({ kelompok: p.group_type });
            else reload();
          }}
        />
      )}
    </>
  );
}
