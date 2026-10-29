// Label & instrumen klinis (sesuai proposal Tahap III).

export const GROUP_LABEL = { intervensi: "Intervensi", kontrol: "Kontrol" };
export const STATUS_LABEL = { aktif: "Aktif", selesai: "Selesai", drop_out: "Drop out", menunggu: "Menunggu persetujuan", ditolak: "Ditolak" };
export const STATUS_TONE = { aktif: "success", drop_out: "danger", ditolak: "danger", menunggu: "warning" };
export const TIMEPOINT_LABEL = { pre: "Pre-test", post: "Post-test", lainnya: "Lainnya" };

export const NTSS6_SYMPTOMS = [
  { key: "baal", label: "Baal / mati rasa" },
  { key: "kesemutan", label: "Kesemutan" },
  { key: "rasa_terbakar", label: "Rasa terbakar" },
  { key: "nyeri_tumpul", label: "Nyeri tumpul / tertekan" },
  { key: "nyeri_tajam", label: "Nyeri tajam / menusuk" },
  { key: "alodinia", label: "Alodinia / hiperalgesia" },
];
export const NTSS6_FREQ = ["Tidak ada", "Kadang-kadang", "Sering", "Hampir terus-menerus"];
export const NTSS6_INTENSITY = ["", "Ringan", "Sedang", "Berat"];
const NTSS6_MATRIX = { 1: [0, 1.0, 2.0, 3.0], 2: [0, 1.33, 2.33, 3.33], 3: [0, 1.66, 2.66, 3.66] };
export const ntss6Score = (items) =>
  Math.round(
    NTSS6_SYMPTOMS.reduce((sum, s) => {
      const it = items?.[s.key];
      return sum + (it && it.freq > 0 && it.intensity > 0 ? NTSS6_MATRIX[it.freq][it.intensity] : 0);
    }, 0) * 100
  ) / 100;

export const DN4_ITEMS = [
  "Rasa terbakar",
  "Rasa dingin yang menyakitkan",
  "Seperti tersengat listrik",
  "Kesemutan",
  "Seperti ditusuk jarum",
  "Baal / mati rasa",
  "Gatal",
  "Hipoestesia terhadap sentuhan",
  "Hipoestesia terhadap tusukan jarum",
  "Nyeri dipicu / bertambah dengan sikatan",
];

export const SKIN_POINTS = [
  { key: "dorsum", label: "Dorsum" },
  { key: "hallux", label: "Ibu jari" },
  { key: "mth1", label: "Metatarsal 1" },
  { key: "mth5", label: "Metatarsal 5" },
  { key: "tumit", label: "Tumit" },
];

export const AE_TYPES = [
  { key: "kemerahan", label: "Kemerahan" },
  { key: "rasa_panas_berlebih", label: "Rasa panas berlebihan" },
  { key: "iritasi", label: "Iritasi" },
  { key: "luka_bakar", label: "Luka bakar" },
  { key: "peningkatan_nyeri", label: "Peningkatan nyeri" },
  { key: "pusing", label: "Pusing" },
  { key: "gangguan_perangkat", label: "Gangguan perangkat" },
  { key: "lainnya", label: "Lainnya" },
];

export const ALERT_TYPE_LABEL = {
  abi_abnormal: "ABI abnormal",
  suhu_asimetris: "Suhu kulit asimetris",
  nyeri_meningkat: "Nyeri meningkat",
  kejadian_tidak_diinginkan: "Kejadian tidak diinginkan",
  suhu_berlebih: "Suhu terapi berlebih",
  tidak_terapi: "Tidak terapi",
  kepatuhan_rendah: "Kepatuhan rendah",
  pindah_kelompok: "Pindah ke intervensi",
};
export const SEVERITY_LABEL = { critical: "Kritis", warning: "Perhatian", info: "Info" };
export const ALERT_STATUS_LABEL = { open: "Baru", acknowledged: "Ditangani", resolved: "Selesai" };

export const abiCategory = (abi) => {
  if (abi == null) return null;
  if (abi <= 0.9) return { label: "Abnormal", tone: "danger" };
  if (abi < 1.0) return { label: "Borderline", tone: "warning" };
  if (abi <= 1.4) return { label: "Normal", tone: "success" };
  return { label: "Tidak terkompresi", tone: "warning" };
};

export const nrsCategory = (n) =>
  n == null ? null : n === 0 ? "Tidak nyeri" : n <= 3 ? "Ringan" : n <= 6 ? "Sedang" : "Berat";

export const today = () => new Date().toISOString().slice(0, 10);

export const fmtDate = (d) => {
  if (!d) return "-";
  const t = Date.parse(d.length <= 10 ? `${d}T00:00:00` : d.replace(" ", "T"));
  if (Number.isNaN(t)) return d;
  return new Date(t).toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" });
};

export const fmtNum = (v, digits = 2) =>
  v == null || v === "" ? "-" : Number(v).toLocaleString("id-ID", { maximumFractionDigits: digits });

export const age = (birth) => {
  if (!birth) return null;
  const b = new Date(birth);
  const n = new Date();
  let a = n.getFullYear() - b.getFullYear();
  if (n < new Date(n.getFullYear(), b.getMonth(), b.getDate())) a--;
  return a;
};
