import { useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../api";
import { Badge, Card, Empty, ErrorBox, GroupBadge, Loading, Segmented, SeverityBadge, useAsync } from "../components/ui";
import AlertFollowUp from "../components/AlertFollowUp";
import { ALERT_STATUS_LABEL, ALERT_TYPE_LABEL, fmtDate } from "../constants";

export default function Alerts() {
  const [status, setStatus] = useState("open");
  const [active, setActive] = useState(null);
  const { data, loading, error, reload } = useAsync(
    () => api(`/admin/alerts${status === "all" ? "" : `?status=${status}`}`),
    [status]
  );

  return (
    <>
      <div className="page-head">
        <div>
          <h1>Alert Klinis</h1>
          <p>Lihat detail alert, hubungi pasien, lalu catat tindak lanjutnya.</p>
        </div>
      </div>
      <Card
        title={
          <Segmented
            value={status}
            onChange={setStatus}
            options={[
              { value: "open", label: "Perlu tindakan" },
              { value: "resolved", label: "Selesai" },
              { value: "all", label: "Semua" },
            ]}
          />
        }
      >
        <ErrorBox error={error} />
        {loading && !data ? <Loading /> : data.length === 0 ? (
          <Empty>{status === "open" ? "Tidak ada alert yang perlu ditindaklanjuti." : "Tidak ada alert."}</Empty>
        ) : (
          data.map((a) => (
            <div className="alert-item" key={a.id}>
              <span className={`alert-dot ${a.severity}`} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="row">
                  <b>{ALERT_TYPE_LABEL[a.type] || a.type}</b>
                  <SeverityBadge severity={a.severity} />
                  <Badge tone={a.status === "resolved" ? "success" : a.status === "acknowledged" ? "info" : "danger"}>
                    {ALERT_STATUS_LABEL[a.status]}
                  </Badge>
                </div>
                <div>{a.message}</div>
                <div className="small muted row" style={{ gap: 6 }}>
                  <Link to={`/pasien/${a.participant_id}?tab=alert`}>{a.code} · {a.name}</Link>
                  <GroupBadge group={a.group_type} />
                  <span>{fmtDate(a.created_at)}</span>
                </div>
                {a.follow_up_note && (
                  <div className="small" style={{ marginTop: 4 }}>
                    Tindak lanjut: {a.follow_up_note}{" "}
                    <span className="muted">— {a.handled_by_name || ""} {fmtDate(a.handled_at)}</span>
                  </div>
                )}
              </div>
              {a.status !== "resolved" && (
                <button className="btn secondary sm" onClick={() => setActive(a)}>Tindak lanjut</button>
              )}
            </div>
          ))
        )}
      </Card>
      {active && <AlertFollowUp alert={active} onClose={() => setActive(null)} onDone={() => { setActive(null); reload(); }} />}
    </>
  );
}
