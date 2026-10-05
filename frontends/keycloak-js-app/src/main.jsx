import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import Keycloak from 'keycloak-js';
import './style.css';

const api = 'http://localhost:8081';
const keycloak = new Keycloak({ url: 'http://localhost:8180', realm: 'poc-sso', clientId: 'spa-client' });

function ProductGrid({ products, loading, error, authenticated, onLogin }) {
  if (!authenticated) return <div className="catalog-empty"><span className="empty-icon">🔐</span><h3>Catálogo protegido</h3><p>Faça login para consultar os produtos no Resource Server.</p><button onClick={onLogin}>Entrar para visualizar</button></div>;
  if (loading) return <div className="catalog-empty"><span className="spinner" /><p>Carregando produtos...</p></div>;
  if (error) return <div className="catalog-empty error-state"><span className="empty-icon">!</span><h3>Não foi possível carregar</h3><p>{error}</p></div>;
  return <div className="product-grid">{products.map(product => <article className="product-card" key={product.name}><div className="product-icon">{product.icon}</div><div className="product-info"><span className="product-category">{product.category}</span><h3>{product.name}</h3><strong>{new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(product.price)}</strong></div></article>)}</div>;
}

function App() {
  const client = useRef(keycloak);
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState({ authenticated: false });
  const [view, setView] = useState('home');
  const [products, setProducts] = useState([]);
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [catalogError, setCatalogError] = useState(null);
  const [result, setResult] = useState(null);

  useEffect(() => { client.current.init({ onLoad: 'check-sso', pkceMethod: 'S256' }).then(authenticated => { setSession(authenticated ? { authenticated: true, username: client.current.tokenParsed?.preferred_username, roles: client.current.tokenParsed?.realm_access?.roles || [] } : { authenticated: false }); setReady(true); }).catch(error => { setResult({ error: String(error) }); setReady(true); }); }, []);
  useEffect(() => {
    if (!session.authenticated) { setProducts([]); return; }
    setCatalogLoading(true); setCatalogError(null);
    client.current.updateToken(30).then(() => fetch(`${api}/api/products`, { headers: { Authorization: `Bearer ${client.current.token}` } })).then(async response => { const body = await response.json(); if (!response.ok) throw new Error(body.message || `HTTP ${response.status}`); return body; }).then(setProducts).catch(error => setCatalogError(error.message)).finally(() => setCatalogLoading(false));
  }, [session.authenticated]);

  const login = () => client.current.login();
  const logout = () => client.current.logout({ redirectUri: window.location.origin });
  const call = async endpoint => { await client.current.updateToken(30); const response = await fetch(`${api}/api/${endpoint}`, { headers: { Authorization: `Bearer ${client.current.token}` } }); setResult({ endpoint, status: response.status, body: await response.json() }); };
  if (!ready) return <div className="app-shell"><div className="loading-page"><span className="spinner" /><p>Inicializando keycloak-js...</p></div></div>;

  return <div className="app-shell">
    <header className="site-header"><a className="brand" href="#home" onClick={() => setView('home')}><span className="brand-mark">◈</span><span><strong>POC Store</strong><small>Arquitetura C · SPA</small></span></a><nav className="main-nav" aria-label="Navegação principal"><button className={view === 'home' ? 'active' : ''} onClick={() => setView('home')}>Home</button><button className={view === 'catalog' ? 'active' : ''} onClick={() => setView('catalog')}>Produtos</button></nav><div className="header-actions">{session.authenticated ? <><span className="user-chip">{session.username}</span><button className="button secondary" onClick={logout}>Logout</button></> : <button className="button" onClick={login}>Login</button>}</div></header>
    <main>{view === 'home' && <section className="hero"><div className="hero-copy"><span className="eyebrow">RESOURCE SERVER · CATÁLOGO</span><h1>Produtos simples.<br /><em>Arquitetura segura.</em></h1><p>Uma home React executando OIDC com PKCE e consumindo o catálogo protegido diretamente no Resource Server.</p><button className="button hero-button" onClick={() => setView('catalog')}>Explorar catálogo <span>→</span></button></div><div className="hero-art"><span className="hero-orbit orbit-one" /><span className="hero-orbit orbit-two" /><span className="hero-core">◈</span><span className="hero-label label-top">PKCE</span><span className="hero-label label-bottom">RESOURCE<br />SERVER</span></div></section>}<section className="catalog-section" id="catalog"><div className="section-heading"><div><span className="eyebrow">COLEÇÃO EM DESTAQUE</span><h2>{view === 'catalog' ? 'Catálogo de produtos' : 'Veja alguns produtos'}</h2></div>{session.authenticated && <span className="secure-badge">✓ sessão protegida</span>}</div><ProductGrid products={products} loading={catalogLoading} error={catalogError} authenticated={session.authenticated} onLogin={login} /></section>{session.authenticated && <section className="diagnostics"><div><span className="eyebrow">POC · VERIFICAÇÃO</span><h2>Recursos protegidos</h2><p>O navegador envia o access token Bearer diretamente ao Resource Server.</p></div><div className="actions"><button onClick={() => call('protected')}>Protected</button><button onClick={() => call('admin')}>Admin</button><button onClick={() => call('me')}>Me</button></div>{result && <pre>{JSON.stringify(result, null, 2)}</pre>}<details><summary>Detalhes da SPA</summary><p>access_token_visible=true</p><p>refresh_token_visible={String(Boolean(client.current.refreshToken))}</p></details></section>}</main>
    <footer className="site-footer"><div><strong>POC Store</strong><span>Catálogo demonstrativo para a Arquitetura C.</span></div><span>React · PKCE · Keycloak · Resource Server</span></footer>
  </div>;
}

createRoot(document.getElementById('root')).render(<App />);
