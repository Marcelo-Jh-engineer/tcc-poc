import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

const api = import.meta.env.VITE_API_URL;
function App() {
  const [session, setSession] = useState({ authenticated: false }); const [result, setResult] = useState(null); const [loading, setLoading] = useState(true);
  useEffect(() => { fetch(`${api}/auth/session`, { credentials: 'include' }).then(r => r.json()).then(setSession).finally(() => setLoading(false)); }, []);
  const call = async endpoint => { const response = await fetch(`${api}/api/${endpoint}`, { credentials: 'include' }); setResult({ endpoint, status: response.status, body: await response.json() }); };
  return <main><header><span className="eyebrow">POC SSO KEYCLOAK</span><h1>Arquitetura A</h1><p className="subtitle">Gateway + sessao opaca</p></header>{loading ? <p>Consultando sessao...</p> : !session.authenticated ? <section className="card"><p>Status: <b>Nao autenticado</b></p><button onClick={() => window.location.href = `${api}/auth/login`}>Login</button><p className="hint">Kong e gateway-auth protegem a borda; o navegador recebe apenas SESSION_ID.</p></section> : <section className="card"><p>Usuario: <b>{session.username}</b></p><p>Roles: {session.roles?.join(', ')}</p><div className="actions"><button onClick={() => call('protected')}>Protected</button><button onClick={() => call('admin')}>Admin</button><button onClick={() => call('me')}>Me</button><button className="secondary" onClick={() => window.location.href = `${api}/auth/logout`}>Logout</button></div>{result && <pre>{JSON.stringify(result, null, 2)}</pre>}<p className="hint">Nenhum access token e entregue ao JavaScript.</p></section>}</main>;
}
createRoot(document.getElementById('root')).render(<App />);

