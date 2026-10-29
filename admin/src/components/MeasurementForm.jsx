import { useMemo, useState } from "react";
import { ErrorBox, Field, Modal } from "./ui";
import {
  DN4_ITEMS, NTSS6_FREQ, NTSS6_INTENSITY, NTSS6_SYMPTOMS, SKIN_POINTS,
  abiCategory, fmtNum, nrsCategory, ntss6Score,
} from "../constants";

/** Input kunjungan pengukuran: ABI, NTSS-6, DN4/NRS, suhu kulit kaki, laktat. */
export default function MeasurementForm({ initial, participant, onSave, onClose }) {
  const [f, setF] = useState(() => ({
    ...initial,
    ntss6_items: initial.ntss6_items || {},
    dn4_items: initial.dn4_items || Array(10).fill(0),
    skin_temp_points: initial.skin_temp_points || { left: {}, right: {} },
  }));
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const set = (k) => (e) => setF((s) => ({ ...s, [k]: e.target.value }));
  const num = (k, props = {}) => <input type="number" inputMode="decimal" step="any" value={f[k] ?? ""} onChange={set(k)} {...props} />;

  // Pratinjau skor (dihitung ulang di server saat disimpan).
  const abi = useMemo(() => {
    const v = (k) => Number(f[k]) || 0;
    const brachial = Math.max(v("brachial_left"), v("brachial_right"));
    if (!brachial) return { left: f.abi_left, right: f.abi_right, computed: false };
    const l = Math.max(v("dp_left"), v("pt_left"));
    const r = Math.max(v("dp_right"), v("pt_right"));
    return { left: l ? Math.round((l / brachial) * 100) / 100 : null, right: r ? Math.round((r / brachial) * 100) / 100 : null, computed: true };
  }, [f]);
  const ntss = ntss6Score(f.ntss6_items);
  const dn4 = f.dn4_items.filter(Boolean).length;
  const skinMean = (side) => {
    const vals = Object.values(f.skin_temp_points[side] || {}).filter((v) => v !== "" && v != null).map(Number);
    return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : null;
  };
  const skinL = skinMean("left") ?? (f.skin_temp_left === "" ? null : f.skin_temp_left);
  const skinR = skinMean("right") ?? (f.skin_temp_right === "" ? null : f.skin_temp_right);
  const asym = skinL != null && skinR != null ? Math.abs(skinL - skinR) : null;

  const setNtss = (key, field, value) =>
    setF((s) => {
      const cur = { ...(s.ntss6_items[key] || { freq: 0, intensity: 0 }), [field]: Number(value) };
      if (field === "freq" && cur.freq === 0) cur.intensity = 0;
      if (field === "freq" && cur.freq > 0 && !cur.intensity) cur.intensity = 1;
      return { ...s, ntss6_items: { ...s.ntss6_items, [key]: cur } };
    });
  const setPoint = (side, key, value) =>
    setF((s) => ({ ...s, skin_temp_points: { ...s.skin_temp_points, [side]: { ...s.skin_temp_points[side], [key]: value } } }));

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      const pts = f.skin_temp_points;
      const hasPoints = ["left", "right"].some((s) => Object.values(pts[s] || {}).some((v) => v !== "" && v != null));
      await onSave({
        ...f,
        abi_left: abi.computed ? null : f.abi_left,
        abi_right: abi.computed ? null : f.abi_right,
        skin_temp_points: hasPoints ? pts : null,
      });
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <Modal
      title={`${initial.id ? "Ubah" : "Input"} pengukuran — ${participant.code}`}
      onClose={onClose}
      footer={
        <>
          <span className="small muted" style={{ marginRight: "auto" }}>Skor dihitung otomatis</span>
          <button className="btn secondary" onClick={onClose}>Batal</button>
          <button className="btn" onClick={submit} disabled={busy}>{busy ? "Menyimpan…" : "Simpan pengukuran"}</button>
        </>
      }
    >
      <div className="form-grid">
        <Field label="Waktu pengukuran">
          <select value={f.timepoint} onChange={set("timepoint")}>
            <option value="pre">Pre-test (awal)</option>
            <option value="post">Post-test (setelah 4 minggu)</option>
            <option value="lainnya">Lainnya</option>
          </select>
        </Field>
        <Field label="Tanggal"><input type="date" value={f.measured_at || ""} onChange={set("measured_at")} /></Field>
        <Field label="Suhu ruangan (°C)">{num("room_temp")}</Field>
      </div>

      <fieldset style={{ marginTop: 16 }}>
        <legend>Ankle-Brachial Index (ABI)</legend>
        <p className="small muted" style={{ marginTop: 0 }}>
          Tekanan sistolik (mmHg) dengan Doppler. ABI tiap tungkai = tekanan tertinggi dorsalis pedis/tibialis posterior ÷ brakialis tertinggi.
        </p>
        <div className="form-grid">
          <Field label="Brakialis kiri">{num("brachial_left")}</Field>
          <Field label="Brakialis kanan">{num("brachial_right")}</Field>
          <Field label="Dorsalis pedis kiri">{num("dp_left")}</Field>
          <Field label="Tibialis posterior kiri">{num("pt_left")}</Field>
          <Field label="Dorsalis pedis kanan">{num("dp_right")}</Field>
          <Field label="Tibialis posterior kanan">{num("pt_right")}</Field>
        </div>
        {!abi.computed && (
          <div className="form-grid" style={{ marginTop: 12 }}>
            <Field label="atau ABI kiri langsung">{num("abi_left")}</Field>
            <Field label="ABI kanan langsung">{num("abi_right")}</Field>
          </div>
        )}
        <div className="row" style={{ marginTop: 12 }}>
          <AbiPreview label="ABI kiri" value={abi.left} />
          <AbiPreview label="ABI kanan" value={abi.right} />
        </div>
      </fieldset>

      <fieldset>
        <legend>NTSS-6 (parestesia) — skor {fmtNum(ntss)}</legend>
        <div className="table-wrap">
          <table>
            <thead><tr><th>Gejala</th><th>Frekuensi</th><th>Intensitas</th></tr></thead>
            <tbody>
              {NTSS6_SYMPTOMS.map((s) => {
                const it = f.ntss6_items[s.key] || { freq: 0, intensity: 0 };
                return (
                  <tr key={s.key}>
                    <td>{s.label}</td>
                    <td>
                      <select value={it.freq} onChange={(e) => setNtss(s.key, "freq", e.target.value)}>
                        {NTSS6_FREQ.map((l, i) => <option key={i} value={i}>{l}</option>)}
                      </select>
                    </td>
                    <td>
                      <select value={it.intensity} disabled={!it.freq} onChange={(e) => setNtss(s.key, "intensity", e.target.value)}>
                        {!it.freq && <option value={0}>-</option>}
                        {[1, 2, 3].map((i) => <option key={i} value={i}>{NTSS6_INTENSITY[i]}</option>)}
                      </select>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </fieldset>

      <fieldset>
        <legend>DN4 & NRS (nyeri neuropatik)</legend>
        <div className="grid grid-2">
          <div>
            <div className="small muted" style={{ marginBottom: 6 }}>
              DN4 — skor <b>{dn4}</b>/10 {dn4 >= 4 && <span style={{ color: "var(--warning)" }}>(≥ 4: kemungkinan nyeri neuropatik)</span>}
            </div>
            {DN4_ITEMS.map((label, i) => (
              <label key={i} className="check small" style={{ padding: "3px 0" }}>
                <input type="checkbox" checked={!!f.dn4_items[i]}
                  onChange={(e) => setF((s) => ({ ...s, dn4_items: s.dn4_items.map((v, j) => (j === i ? (e.target.checked ? 1 : 0) : v)) }))} />
                {i + 1}. {label}
              </label>
            ))}
          </div>
          <div>
            <Field label={`NRS nyeri kaki: ${f.nrs ?? "-"} ${f.nrs != null && f.nrs !== "" ? `(${nrsCategory(Number(f.nrs))})` : ""}`}>
              <input type="range" min="0" max="10" step="1" value={f.nrs ?? 0}
                onChange={(e) => setF((s) => ({ ...s, nrs: Number(e.target.value) }))} />
            </Field>
            <div className="row small muted" style={{ justifyContent: "space-between" }}><span>0 tidak nyeri</span><span>10 terberat</span></div>
          </div>
        </div>
      </fieldset>

      <fieldset>
        <legend>Suhu kulit kaki (termometer inframerah, °C)</legend>
        <p className="small muted" style={{ marginTop: 0 }}>Isi per titik (rerata dua kali ukur). Suhu kaki = rerata titik yang diisi.</p>
        <div className="table-wrap">
          <table>
            <thead><tr><th>Titik</th><th>Kiri</th><th>Kanan</th></tr></thead>
            <tbody>
              {SKIN_POINTS.map((pt) => (
                <tr key={pt.key}>
                  <td>{pt.label}</td>
                  {["left", "right"].map((side) => (
                    <td key={side}>
                      <input type="number" step="0.1" inputMode="decimal" value={f.skin_temp_points[side]?.[pt.key] ?? ""}
                        onChange={(e) => setPoint(side, pt.key, e.target.value)} />
                    </td>
                  ))}
                </tr>
              ))}
              <tr>
                <td><b>Rerata</b></td>
                <td className="num"><b>{fmtNum(skinL, 1)}</b></td>
                <td className="num"><b>{fmtNum(skinR, 1)}</b></td>
              </tr>
            </tbody>
          </table>
        </div>
        {asym != null && asym >= 2.2 && (
          <div className="error-box" style={{ marginTop: 10, background: "var(--warning-soft)", color: "var(--warning)" }}>
            Selisih suhu kiri–kanan {fmtNum(asym, 1)}°C (≥ 2,2°C) — alert asimetri akan dibuat.
          </div>
        )}
      </fieldset>

      <fieldset>
        <legend>Laktat darah & catatan</legend>
        <div className="form-grid">
          <Field label="Laktat (mmol/L)">{num("lactate")}</Field>
        </div>
        <div style={{ marginTop: 12 }}>
          <Field label="Catatan (kondisi, alat, nomor lot strip, dll.)">
            <textarea value={f.notes ?? ""} onChange={set("notes")} />
          </Field>
        </div>
      </fieldset>

      <div style={{ marginTop: 14 }}><ErrorBox error={error} /></div>
    </Modal>
  );
}

function AbiPreview({ label, value }) {
  const c = abiCategory(value == null || value === "" ? null : Number(value));
  return (
    <span className="badge" style={{ fontSize: 13, padding: "4px 10px" }}>
      {label}: <b className="num">{value == null || value === "" ? "-" : fmtNum(value)}</b>
      {c && <span className={`badge ${c.tone}`} style={{ marginLeft: 4 }}>{c.label}</span>}
    </span>
  );
}
