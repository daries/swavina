import { createContext, useContext, useEffect, useState } from "react";
import { NavLink, Navigate, Route, Routes, useLocation, useNavigate } from "react-router-dom";
import { api, clearSession, getSession, saveSession, setUnauthorizedHandler } from "./api";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Participants from "./pages/Participants";
import ParticipantDetail from "./pages/ParticipantDetail";
import Alerts from "./pages/Alerts";
import Analysis from "./pages/Analysis";

const ROLE_LABEL = { nurse: "Perawat", researcher: "Peneliti", admin: "Admin" };
const STAFF = Object.keys(ROLE_LABEL);

const AuthCtx = createContext(null);
export const useAuth = () => useContext(AuthCtx);

export default function App() {
  const [session, setSession] = useState(getSession);
  const navigate = useNavigate();

  const logout = () => {
    clearSession();
    setSession(null);
    navigate("/login");
  };

  // Kurung kurawal penting: jangan kembalikan logout sebagai cleanup effect,
  // karena StrictMode (dev) menjalankan cleanup → logout setiap kali halaman dimuat.
  useEffect(() => {
    setUnauthorizedHandler(logout);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const login = async (email, password) => {
    const res = await api("/auth/login", { method: "POST", body: { email, password } });
    if (!STAFF.includes(res.role)) {
      throw new Error("Akun ini bukan akun perawat/peneliti. Gunakan aplikasi pasien SWAVINA.");
    }
    const user = { id: res.userId, email, name: res.name || email, role: res.role };
    saveSession(res.token, user);
    setSession({ token: res.token, user });
    navigate("/");
  };

  if (!session) {
    return (
      <Routes>
        <Route path="*" element={<Login onLogin={login} />} />
      </Routes>
    );
  }

  return (
    <AuthCtx.Provider value={{ user: session.user, logout }}>
      <div className="shell">
        <Sidebar user={session.user} onLogout={logout} />
        <main className="main">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/pasien" element={<Participants />} />
            <Route path="/pasien/:id" element={<ParticipantDetail />} />
            <Route path="/alert" element={<Alerts />} />
            <Route path="/analisis" element={<Analysis />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </main>
      </div>
    </AuthCtx.Provider>
  );
}

function Sidebar({ user, onLogout }) {
  const [openAlerts, setOpenAlerts] = useState(0);
  const [pending, setPending] = useState(0);
  const location = useLocation();
  // Perbarui badge saat pindah halaman & tiap menit.
  useEffect(() => {
    let alive = true;
    const load = () => {
      api("/admin/alerts?status=open")
        .then((a) => alive && setOpenAlerts(a.length))
        .catch(() => {});
      api("/admin/approvals")
        .then((a) => alive && setPending(a.length))
        .catch(() => {});
    };
    load();
    const t = setInterval(load, 60000);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, [location.pathname]);

  const Icon = ({ d }) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  );

  return (
    <aside className="sidebar">
      <div className="brand">
        <img src="/icon-192.png" alt="" />
        <div>
          <b>SWAVINA</b>
          <span>Monitoring Penelitian</span>
        </div>
      </div>
      <nav className="nav">
        <NavLink to="/" end><Icon d="M3 12l9-8 9 8M5 10v10h14V10" />Dashboard</NavLink>
        <NavLink to="/pasien"><Icon d="M16 20v-2a4 4 0 00-4-4H6a4 4 0 00-4 4v2M9 10a4 4 0 100-8 4 4 0 000 8M22 20v-2a4 4 0 00-3-3.87M16 2.13a4 4 0 010 7.75" />Pasien
          {pending > 0 && <span className="count" style={{ background: "var(--warning)" }} title="Registrasi menunggu persetujuan">{pending}</span>}
        </NavLink>
        <NavLink to="/alert">
          <Icon d="M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 01-3.46 0" />Alert
          {openAlerts > 0 && <span className="count">{openAlerts}</span>}
        </NavLink>
        <NavLink to="/analisis"><Icon d="M18 20V10M12 20V4M6 20v-6" />Analisis</NavLink>
      </nav>
      <div className="me">
        <div style={{ fontWeight: 650 }}>{user.name}</div>
        <div className="muted small">{ROLE_LABEL[user.role]} · {user.email}</div>
        <button className="btn ghost sm" style={{ marginTop: 6, paddingLeft: 0 }} onClick={onLogout}>Keluar</button>
      </div>
    </aside>
  );
}
