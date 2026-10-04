import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import Keycloak from 'keycloak-js';
import './style.css';

const api = 'http://localhost:8081';
const keycloak = new Keycloak({ url: 'http://localhost:8180', realm: 'poc-sso', clientId: 'spa-client' });

function App() {
  const client = useRef(keycloak); const [ready, setReady] = useState(false); const [session, setSession] = useState(null); const [result, setResult] = useState(null);
  useEffect(() => { client.current.init({ onLoad: 'check-sso', pkceMethod: 'S256' }).then(authenticated => { setSession(authenticated ? { authenticated: true, username: client.current.tokenParsed?.preferred_username, roles: client.current.tokenParsed?.realm_access?.roles || [] } : { authenticated: false }); setReady(true); }).catch(error => { setResult({ error: String(error) }); setReady(true); }); }, []);
  const login = () => client.current.login();
  const logout = () => client.current.logout({ redirectUri: window.location.origin });
  const call = async endpoint => { await client.current.updateToken(30); const response = await fetch(`${api}/api/${endpoint}`, { headers: { Authorization: `Bearer ${client.current.token}` } }); setResult({ endpoint, status: response.status, body: await response.json() }); };
  if (!ready) return <main><p>Inicializando keycloak-js...</p></main>;
  return <main><header><span className="eyebrow">POC SSO KEYCLOAK</span><h1>Arquitetura C</h1><p className="subtitle">React + keycloak-js</p></header>{!session?.authenticated ? <section className="card"><p>Status: <b>Nao autenticado</b></p><button onClick={login}>Login</button><p className="hint">O navegador executa OIDC e mantem o token no contexto React.</p></section> : <section className="card"><p>Usuario: <b>{session.username}</b></p><p>Roles: {session.roles.join(', ')}</p><div className="actions"><button onClick={() => call('protected')}>Protected</button><button onClick={() => call('admin')}>Admin</button><button onClick={() => call('me')}>Me</button><button className="secondary" onClick={logout}>Logout</button></div>{result && <pre>{JSON.stringify(result, null, 2)}</pre>}<details><summary>Debug da PoC (token presente no navegador)</summary><p>access_token_visible=true</p><p>refresh_token_visible={String(Boolean(client.current.refreshToken))}</p><p>token_preview={client.current.token ? `${client.current.token.slice(0, 18)}...&lt;REDACTED&gt;` : 'none'}</p></details></section>}</main>;
}
createRoot(document.getElementById('root')).render(<App />);

