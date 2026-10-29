import { useState } from "react";
import { ErrorBox, Field, Modal } from "./ui";
import { AE_TYPES, today } from "../constants";

/** Formulir keamanan: kejadian tidak diinginkan, tindakan, dan keputusan lanjut/hentikan. */
export default function AdverseEventForm({ onSave, onClose }) {
  const [f, setF] = useState({ occurred_at: today(), types: [], severity: "ringan", decision: "lanjut" });
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const set = (k) => (e) => setF((s) => ({ ...s, [k]: e.target.value }));
  const toggle = (key) =>
    setF((s) => ({ ...s, types: s.types.includes(key) ? s.types.filter((t) => t !== key) : [...s.types, key] }));

  const submit = async () => {
    if (!f.types.length && !f.description) {
      setError("Pilih minimal satu jenis kejadian atau isi deskripsi.");
      return;
    }
    if (f.decision === "hentikan" && !confirm("Menghentikan intervensi akan mengubah status responden menjadi drop out. Lanjutkan?")) return;
    setBusy(true);
    setError(null);
    try {
      await onSave(f);
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <Modal
      title="Catat kejadian tidak diinginkan"
      onClose={onClose}
      footer={
        <>
          <button className="btn secondary" onClick={onClose}>Batal</button>
          <button className="btn" onClick={submit} disabled={busy}>{busy ? "Menyimpan…" : "Simpan"}</button>
        </>
      }
    >
      <div className="form-grid">
        <Field label="Tanggal kejadian"><input type="date" value={f.occurred_at} onChange={set("occurred_at")} /></Field>
        <Field label="Keparahan">
          <select value={f.severity} onChange={set("severity")}>
            <option value="ringan">Ringan</option>
            <option value="sedang">Sedang</option>
            <option value="berat">Berat</option>
          </select>
        </Field>
        <Field label="Keputusan">
          <select value={f.decision} onChange={set("decision")}>
            <option value="lanjut">Lanjutkan intervensi</option>
            <option value="hentikan">Hentikan intervensi</option>
          </select>
        </Field>
      </div>
      <fieldset style={{ marginTop: 16 }}>
        <legend>Jenis kejadian</legend>
        <div className="form-grid">
          {AE_TYPES.map((t) => (
            <label key={t.key} className="check">
              <input type="checkbox" checked={f.types.includes(t.key)} onChange={() => toggle(t.key)} />
              {t.label}
            </label>
          ))}
        </div>
      </fieldset>
      <div className="grid" style={{ marginTop: 14 }}>
        <Field label="Deskripsi"><textarea value={f.description || ""} onChange={set("description")} /></Field>
        <Field label="Tindakan yang diberikan"><textarea value={f.action_taken || ""} onChange={set("action_taken")} /></Field>
        <ErrorBox error={error} />
      </div>
    </Modal>
  );
}
