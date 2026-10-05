import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

const api = import.meta.env.VITE_API_URL;

function ProductGrid({ products, loading, error, authenticated, onLogin }) {
  if (!authenticated) return <div className="catalog-empty"><span className="empty-icon">🔐</span><h3>Catálogo protegido</h3><p>Faça login para consultar os produtos no Resource Server.</p><button onClick={onLogin}>Entrar para visualizar</button></div>;
  if (loading) return <div className="catalog-empty"><span className="spinner" /><p>Carregando produtos...</p></div>;
  if (error) return <div className="catalog-empty error-state"><span className="empty-icon">!</span><h3>Não foi possível carregar</h3><p>{error}</p></div>;
  return <div className="product-grid">{products.map(product => <article className="product-card" key={product.name}><div className="product-icon">{product.icon}</div><div className="product-info"><span className="product-category">{product.category}</span><h3>{product.name}</h3><strong>{new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(product.price)}</strong></div></article>)}</div>;
}

function App() {
  const [session, setSession] = useState({ authenticated: false });
  const [view, setView] = useState('home');
  const [products, setProducts] = useState([]);
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [catalogError, setCatalogError] = useState(null);
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => { fetch(`${api}/auth/session`, { credentials: 'include' }).then(response => response.json()).then(setSession).catch(() => setSession({ authenticated: false })).finally(() => setLoading(false)); }, []);
  useEffect(() => {
    if (!session.authenticated) { setProducts([]); return; }
    setCatalogLoading(true); setCatalogError(null);
    fetch(`${api}/api/products`, { credentials: 'include' }).then(async response => { const body = await response.json(); if (!response.ok) throw new Error(body.message || `HTTP ${response.status}`); return body; }).then(setProducts).catch(error => setCatalogError(error.message)).finally(() => setCatalogLoading(false));
  }, [session.authenticated]);

  const login = () => { window.location.href = `${api}/auth/login`; };
  const logout = () => { window.location.href = `${api}/auth/logout`; };
  const call = async endpoint => { const response = await fetch(`${api}/api/${endpoint}`, { credentials: 'include' }); setResult({ endpoint, status: response.status, body: await response.json() }); };

  return <div className="app-shell">
    <header className="site-header"><a className="brand" href="#home" onClick={() => setView('home')}><span className="brand-mark">◈</span><span><strong>POC Store</strong><small>Arquitetura A · Gateway</small></span></a><nav className="main-nav" aria-label="Navegação principal"><button className={view === 'home' ? 'active' : ''} onClick={() => setView('home')}>Home</button><button className={view === 'catalog' ? 'active' : ''} onClick={() => setView('catalog')}>Produtos</button></nav><div className="header-actions">{session.authenticated ? <><span className="user-chip">{session.username}</span><button className="button secondary" onClick={logout}>Logout</button></> : <button className="button" onClick={login}>Login</button>}</div></header>
    <main>{loading ? <div className="loading-page"><span className="spinner" /><p>Consultando sessão...</p></div> : <>
      {view === 'home' && <section className="hero"><div className="hero-copy"><span className="eyebrow">RESOURCE SERVER · CATÁLOGO</span><h1>Produtos simples.<br /><em>Arquitetura segura.</em></h1><p>Uma home React atrás do Kong, com autenticação na borda e o catálogo protegido pelo Resource Server.</p><button className="button hero-button" onClick={() => setView('catalog')}>Explorar catálogo <span>→</span></button></div><div className="hero-art"><span className="hero-orbit orbit-one" /><span className="hero-orbit orbit-two" /><span className="hero-core">◈</span><span className="hero-label label-top">KONG</span><span className="hero-label label-bottom">RESOURCE<br />SERVER</span></div></section>}
      <section className="catalog-section" id="catalog"><div className="section-heading"><div><span className="eyebrow">COLEÇÃO EM DESTAQUE</span><h2>{view === 'catalog' ? 'Catálogo de produtos' : 'Veja alguns produtos'}</h2></div>{session.authenticated && <span className="secure-badge">✓ sessão protegida</span>}</div><ProductGrid products={products} loading={catalogLoading} error={catalogError} authenticated={session.authenticated} onLogin={login} /></section>
      {session.authenticated && <section className="diagnostics"><div><span className="eyebrow">POC · VERIFICAÇÃO</span><h2>Recursos protegidos</h2><p>Teste as autorizações passando por Kong e gateway-auth.</p></div><div className="actions"><button onClick={() => call('protected')}>Protected</button><button onClick={() => call('admin')}>Admin</button><button onClick={() => call('me')}>Me</button></div>{result && <pre>{JSON.stringify(result, null, 2)}</pre>}</section>}
    </>}</main>
    <footer className="site-footer"><div><strong>POC Store</strong><span>Catálogo demonstrativo para a Arquitetura A.</span></div><span>React · Kong · Keycloak · Resource Server</span></footer>
  </div>;
}

createRoot(document.getElementById('root')).render(<App />);
