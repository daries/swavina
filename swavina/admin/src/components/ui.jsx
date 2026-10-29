import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { GROUP_LABEL, SEVERITY_LABEL } from "../constants";

/** Ambil data async dengan status loading/error dan fungsi reload. */
export function useAsync(fn, deps = []) {
  const [state, setState] = useState({ data: null, loading: true, error: null });
  const fnRef = useRef(fn);
  fnRef.current = fn;
  const load = useCallback(async () => {
    setState((s) => ({ ...s, loading: true, error: null }));
    try {
      const data = await fnRef.current();
      setState({ data, loading: false, error: null });
    } catch (e) {
      setState((s) => ({ ...s, loading: false, error: e.message }));
    }
  }, []);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { load(); }, deps);
  return { ...state, reload: load, setData: (data) => setState((s) => ({ ...s, data })) };
}

const ToastCtx = createContext(() => {});
export const useToast = () => useContext(ToastCtx);
export function ToastProvider({ children }) {
  const [msg, setMsg] = useState(null);
  const show = useCallback((m) => {
    setMsg(m);
    clearTimeout(show.t);
    show.t = setTimeout(() => setMsg(null), 2600);
  }, []);
  return (
    <ToastCtx.Provider value={show}>
      {children}
      {msg && <div className="toast" role="status">{msg}</div>}
    </ToastCtx.Provider>
  );
}

export function Card({ title, actions, children, className = "", ...rest }) {
  return (
    <section className={`card ${className}`} {...rest}>
      {(title || actions) && (
        <div className="card-head">
          {typeof title === "string" ? <h2>{title}</h2> : title}
          {actions && <div className="row">{actions}</div>}
        </div>
      )}
      {children}
    </section>
  );
}

export const Badge = ({ tone = "", children }) => <span className={`badge ${tone}`}>{children}</span>;
export const GroupBadge = ({ group }) => <Badge tone={group}>{GROUP_LABEL[group] || group}</Badge>;
export const SeverityBadge = ({ severity }) => (
  <Badge tone={{ critical: "danger", warning: "warning", info: "info" }[severity]}>{SEVERITY_LABEL[severity]}</Badge>
);

export function Field({ label, hint, children }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
      {hint && <small>{hint}</small>}
    </label>
  );
}

export function Segmented({ value, onChange, options }) {
  return (
    <div className="segmented" role="tablist">
      {options.map((o) => (
        <button key={o.value} type="button" role="tab" aria-selected={value === o.value}
          className={value === o.value ? "active" : ""} onClick={() => onChange(o.value)}>
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Tabs({ value, onChange, tabs }) {
  return (
    <div className="tabs" role="tablist">
      {tabs.map((t) => (
        <button key={t.value} type="button" role="tab" aria-selected={value === t.value}
          className={value === t.value ? "active" : ""} onClick={() => onChange(t.value)}>
          {t.label}
        </button>
      ))}
    </div>
  );
}

export function Modal({ title, onClose, children, footer }) {
  useEffect(() => {
    const onKey = (e) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head">
          <h2>{title}</h2>
          <button className="btn ghost" onClick={onClose} aria-label="Tutup">✕</button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>
  );
}

export function Progress({ percent }) {
  const p = Math.max(0, Math.min(100, percent ?? 0));
  const tone = percent == null ? "" : p >= 80 ? "" : p >= 50 ? "warn" : "bad";
  return (
    <div className={`progress ${tone}`} role="progressbar" aria-valuenow={p} aria-valuemin={0} aria-valuemax={100}>
      <div style={{ width: `${p}%` }} />
    </div>
  );
}

export const Loading = () => <div className="empty">Memuat…</div>;
export const ErrorBox = ({ error }) => (error ? <div className="error-box">{error}</div> : null);
export const Empty = ({ children }) => <div className="empty">{children}</div>;
