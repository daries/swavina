import { useState } from "react";
import { Card, ErrorBox, Field } from "../components/ui";

export default function Login({ onLogin }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await onLogin(email.trim(), password);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="login-wrap">
      <Card className="login-card">
        <div className="brand">
          <img src="/icon-192.png" alt="" />
          <div>
            <b style={{ fontSize: 20 }}>SWAVINA Monitoring</b>
            <span>Login tenaga kesehatan &amp; peneliti</span>
          </div>
        </div>
        <form onSubmit={submit} className="grid">
          <Field label="Email">
            <input type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </Field>
          <Field label="Password">
            <input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </Field>
          <ErrorBox error={error} />
          <button className="btn" disabled={busy}>{busy ? "Masuk…" : "Masuk"}</button>
        </form>
      </Card>
    </div>
  );
}
