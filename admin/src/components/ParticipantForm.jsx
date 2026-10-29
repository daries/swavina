import { useState } from "react";
import { ErrorBox, Field, Modal } from "./ui";

/** Formulir data responden (identitas + formulir penelitian / faktor perancu). */
export default function ParticipantForm({ initial = {}, onSave, onClose }) {
  const [f, setF] = useState(initial);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const set = (k) => (e) => setF((s) => ({ ...s, [k]: e.target.value }));
  const input = (k, props = {}) => <input value={f[k] ?? ""} onChange={set(k)} {...props} />;

  const submit = async (e) => {
    e?.preventDefault();
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
      title={initial.id ? `Ubah data ${initial.code}` : "Tambah responden"}
      onClose={onClose}
      footer={
        <>
          <button className="btn secondary" onClick={onClose}>Batal</button>
          <button className="btn" onClick={submit} disabled={busy}>{busy ? "Menyimpan…" : "Simpan"}</button>
        </>
      }
    >
      <form onSubmit={submit}>
        <fieldset>
          <legend>Identitas & penelitian</legend>
          <div className="form-grid">
            <Field label="Kode responden" hint={initial.id ? undefined : "Kosongkan untuk kode otomatis"}>{input("code", { placeholder: "otomatis, mis. INT-004" })}</Field>
            <Field label="Nama *">{input("name", { required: true })}</Field>
            <Field label="Kelompok *">
              <select value={f.group_type || "intervensi"} onChange={set("group_type")}>
                <option value="intervensi">Intervensi (SWAVINA + perawatan standar)</option>
                <option value="kontrol" disabled={(initial.compliance?.sessions ?? 0) > 0}>
                  Kontrol (perawatan standar){(initial.compliance?.sessions ?? 0) > 0 ? " — tidak bisa, sudah terapi" : ""}
                </option>
              </select>
            </Field>
            <Field label="Status">
              <select value={f.status || "aktif"} onChange={set("status")}>
                <option value="aktif">Aktif</option>
                <option value="selesai">Selesai</option>
                <option value="drop_out">Drop out</option>
                {["menunggu", "ditolak"].includes(initial.status) && (
                  <option value={initial.status}>{initial.status === "menunggu" ? "Menunggu persetujuan" : "Ditolak"}</option>
                )}
              </select>
            </Field>
            <Field label="No. HP / WhatsApp">{input("phone", { type: "tel" })}</Field>
            <Field label="Mulai penelitian" hint="Post-test dijadwalkan 4 minggu setelahnya">{input("study_start", { type: "date" })}</Field>
            <Field label="Sesi direncanakan" hint="Mis. 28 = 1 sesi/hari × 4 minggu">{input("planned_sessions", { type: "number", min: 1 })}</Field>
          </div>
        </fieldset>

        <fieldset>
          <legend>Karakteristik responden</legend>
          <div className="form-grid">
            <Field label="Jenis kelamin">
              <select value={f.sex || ""} onChange={set("sex")}>
                <option value="">-</option>
                <option value="L">Laki-laki</option>
                <option value="P">Perempuan</option>
              </select>
            </Field>
            <Field label="Tanggal lahir">{input("birth_date", { type: "date" })}</Field>
            <Field label="Lama DM (tahun)">{input("dm_duration_years", { type: "number", step: "0.5", min: 0 })}</Field>
            <Field label="HbA1c (%)">{input("hba1c", { type: "number", step: "0.1" })}</Field>
            <Field label="Gula darah (mg/dL)">{input("blood_glucose", { type: "number" })}</Field>
            <Field label="Sistolik (mmHg)">{input("systolic", { type: "number" })}</Field>
            <Field label="Diastolik (mmHg)">{input("diastolic", { type: "number" })}</Field>
            <Field label="Tinggi badan (cm)">{input("height", { type: "number", step: "0.1" })}</Field>
            <Field label="Berat badan (kg)">{input("weight", { type: "number", step: "0.1" })}</Field>
            <Field label="Merokok">
              <select value={f.smoking || ""} onChange={set("smoking")}>
                <option value="">-</option>
                <option value="tidak">Tidak</option>
                <option value="mantan">Mantan perokok</option>
                <option value="ya">Ya</option>
              </select>
            </Field>
            <Field label="Aktivitas fisik">
              <select value={f.physical_activity || ""} onChange={set("physical_activity")}>
                <option value="">-</option>
                <option value="rendah">Rendah</option>
                <option value="sedang">Sedang</option>
                <option value="tinggi">Tinggi</option>
              </select>
            </Field>
          </div>
          <div className="form-grid" style={{ marginTop: 14 }}>
            <Field label="Penyakit penyerta">{input("comorbidities")}</Field>
            <Field label="Terapi antidiabetes">{input("antidiabetic")}</Field>
            <Field label="Analgesik">{input("analgesic")}</Field>
            <Field label="Obat neuropati">{input("neuropathy_drug")}</Field>
          </div>
          <div style={{ marginTop: 14 }}>
            <Field label="Catatan">
              <textarea value={f.notes ?? ""} onChange={set("notes")} />
            </Field>
          </div>
        </fieldset>
        <div style={{ marginTop: 14 }}><ErrorBox error={error} /></div>
      </form>
    </Modal>
  );
}
