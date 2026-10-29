import { useState } from "react";
import { api } from "../api";
import { ErrorBox, Field, Modal, SeverityBadge, useToast } from "./ui";
import { ALERT_TYPE_LABEL, fmtDate } from "../constants";

/** Lihat detail alert → tindak lanjut / hubungi pasien → tandai ditangani / selesai. */
export default function AlertFollowUp({ alert, onClose, onDone }) {
  const toast = useToast();
  const [note, setNote] = useState(alert.follow_up_note || "");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const wa = alert.phone ? `https://wa.me/${alert.phone.replace(/\D/g, "").replace(/^0/, "62")}` : null;

  const save = async (status) => {
    if (status === "resolved" && !note.trim()) {
      setError("Isi catatan tindak lanjut sebelum menandai selesai.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api(`/admin/alerts/${alert.id}`, { method: "PATCH", body: { status, follow_up_note: note.trim() || null } });
      toast(status === "resolved" ? "Alert diselesaikan" : "Alert ditandai sedang ditangani");
      onDone();
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  };

  return (
    <Modal
      title="Detail alert"
      onClose={onClose}
      footer={
        <>
          <button className="btn secondary" onClick={() => save("acknowledged")} disabled={busy}>Sedang ditangani</button>
          <button className="btn" onClick={() => save("resolved")} disabled={busy}>Tandai selesai</button>
        </>
      }
    >
      <div className="row">
        <h3>{ALERT_TYPE_LABEL[alert.type] || alert.type}</h3>
        <SeverityBadge severity={alert.severity} />
      </div>
      <p>{alert.message}</p>
      <dl className="kv">
        <dt>Responden</dt><dd>{alert.code} · {alert.name}</dd>
        <dt>Dibuat</dt><dd>{fmtDate(alert.created_at)}</dd>
        <dt>Kontak</dt>
        <dd>
          {alert.phone ? (
            <span className="row">
              <a href={`tel:${alert.phone}`}>{alert.phone}</a>
              {wa && <a className="btn secondary sm" href={wa} target="_blank" rel="noreferrer">WhatsApp</a>}
            </span>
          ) : "Belum ada nomor HP"}
        </dd>
      </dl>
      <div style={{ marginTop: 16 }}>
        <Field label="Catatan tindak lanjut" hint="Mis. pasien dihubungi, terapi dihentikan sementara, dijadwalkan kontrol.">
          <textarea value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
      </div>
      <div style={{ marginTop: 10 }}><ErrorBox error={error} /></div>
    </Modal>
  );
}
