// Klien REST ke backend SWAVINA. Token JWT disimpan di localStorage.
// Alamat API: VITE_API_URL (lihat admin/.env.production), default "/api" (dev via proxy Vite).
const API_URL = (import.meta.env.VITE_API_URL || "/api").replace(/\/$/, "");

const TOKEN_KEY = "swavina_admin_token";
const USER_KEY = "swavina_admin_user";

function safeGet(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}
function safeSet(key, value) {
  try {
    if (value == null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    /* penyimpanan diblokir: sesi hanya bertahan di memori */
  }
}

let memoryToken = safeGet(TOKEN_KEY);

export function getSession() {
  const raw = safeGet(USER_KEY);
  if (!memoryToken || !raw) return null;
  try {
    return { token: memoryToken, user: JSON.parse(raw) };
  } catch {
    return null;
  }
}

export function saveSession(token, user) {
  memoryToken = token;
  safeSet(TOKEN_KEY, token);
  safeSet(USER_KEY, JSON.stringify(user));
}

export function clearSession() {
  memoryToken = null;
  safeSet(TOKEN_KEY, null);
  safeSet(USER_KEY, null);
}

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

let onUnauthorized = () => {};
export function setUnauthorizedHandler(fn) {
  onUnauthorized = fn;
}

export async function api(path, { method = "GET", body } = {}) {
  const res = await fetch(`${API_URL}${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(memoryToken ? { Authorization: `Bearer ${memoryToken}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (res.status === 401) onUnauthorized();
  if (!res.ok) throw new ApiError(data?.message || `Gagal (${res.status})`, res.status);
  return data;
}

/** Unduh CSV ekspor (butuh header Authorization, jadi tidak bisa lewat <a href>). */
export async function downloadCsv(path, fallbackName) {
  const res = await fetch(`${API_URL}${path}`, { headers: { Authorization: `Bearer ${memoryToken}` } });
  if (!res.ok) throw new ApiError(`Ekspor gagal (${res.status})`, res.status);
  const blob = await res.blob();
  const name = /filename="([^"]+)"/.exec(res.headers.get("Content-Disposition") || "")?.[1] || fallbackName;
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
