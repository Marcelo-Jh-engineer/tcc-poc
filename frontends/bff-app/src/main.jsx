import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

const api = import.meta.env.VITE_API_URL;
const architecture = import.meta.env.VITE_ARCHITECTURE || 'B';

async function parseResponse(response) {
  const text = await response.text();
  if (!text) return {};
  try { return JSON.parse(text); } catch { return { message: text }; }
}

function ProductGrid({ products, loading, error, authenticated, onLogin }) {
  if (!authenticated) return <div className="catalog-empty"><span className="empty-icon">[ ]</span><h3>Catalogo protegido</h3><p>Faca login para consultar os produtos.</p><button onClick={onLogin}>Entrar para visualizar</button></div>;
  if (loading) return <div className="catalog-empty"><span className="spinner" /><p>Carregando produtos...</p></div>;
  if (error) return <div className="catalog-empty error-state"><span className="empty-icon">!</span><h3>Nao foi possivel carregar</h3><p>{error}</p></div>;
  if (!products.length) return <div className="catalog-empty"><span className="empty-icon">?</span><h3>Nenhum produto encontrado</h3><p>Tente buscar por outro nome.</p></div>;
  return <div className="product-grid">{products.map(product => <article className="product-card" key={product.id || product.name}><div className="product-icon">{product.icon}</div><div className="product-info"><span className="product-category">{product.category}</span><h3>{product.name}</h3><strong>{new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(product.price)}</strong></div></article>)}</div>;
}

function App() {
  const [session, setSession] = useState({ authenticated: false });
  const [view, setView] = useState('home');
  const [products, setProducts] = useState([]);
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [catalogError, setCatalogError] = useState(null);
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [showProductForm, setShowProductForm] = useState(false);
  const [formError, setFormError] = useState(null);
  const [draft, setDraft] = useState({ name: '', price: '', icon: '*', category: '' });

  const loadSession = () => fetch(`${api}/auth/session`, { credentials: 'include' }).then(response => response.json()).then(setSession).catch(() => setSession({ authenticated: false })).finally(() => setLoading(false));
  useEffect(() => { loadSession(); }, []);

  useEffect(() => {
    if (!session.authenticated) { setProducts([]); return; }
    setCatalogLoading(true);
    setCatalogError(null);
    fetch(`${api}/api/products`, { credentials: 'include' }).then(async response => { const body = await parseResponse(response); if (!response.ok) { if (response.status === 401) setSession({ authenticated: false }); throw new Error(body.error || body.message || `HTTP ${response.status}`); } return body; }).then(setProducts).catch(error => setCatalogError(error.message)).finally(() => setCatalogLoading(false));
  }, [session.authenticated]);

  const login = () => { window.location.href = `${api}/auth/login`; };
  const logout = () => { window.location.href = `${api}/auth/logout`; };
  const call = async endpoint => { const response = await fetch(`${api}/api/${endpoint}`, { credentials: 'include' }); setResult({ endpoint, status: response.status, body: await parseResponse(response) }); };
  const visibleProducts = products.filter(product => product.name.toLowerCase().includes(searchTerm.toLowerCase().trim()));
  const createProduct = async event => {
    event.preventDefault();
    setFormError(null);
    const response = await fetch(`${api}/api/products`, { method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...draft, price: Number(draft.price) }) });
    const body = await parseResponse(response);
    if (!response.ok) { setFormError(body.message || `HTTP ${response.status}`); return; }
    setProducts(current => [...current, body]);
    setDraft({ name: '', price: '', icon: '*', category: '' });
    setShowProductForm(false);
  };

  return <div className="app-shell">
    <header className="site-header">
      <a className="brand" href="#home" onClick={() => setView('home')}><span className="brand-mark">*</span><span><strong>POC Store</strong><small>Architecture {architecture} - BFF</small></span></a>
      <nav className="main-nav" aria-label="Main navigation"><button className={view === 'home' ? 'active' : ''} onClick={() => setView('home')}>Home</button><button className={view === 'catalog' ? 'active' : ''} onClick={() => setView('catalog')}>Products</button>{session.authenticated && <span className="protected-nav"><button onClick={() => call('protected')}>Protected</button><button onClick={() => call('admin')}>Admin</button><button onClick={() => call('me')}>Me</button></span>}</nav>
      <div className="header-actions">{session.authenticated ? <><span className="user-chip">{session.username}</span><button className="button secondary" onClick={logout}>Logout</button></> : <button className="button" onClick={login}>Login</button>}</div>
    </header>
    <main>
      {loading ? <div className="loading-page"><span className="spinner" /><p>Checking session...</p></div> : <>
        {view === 'home' && <section className="hero"><div className="hero-copy"><span className="eyebrow">RESOURCE SERVER - CATALOG</span><h1>Simple products.<br /><em>Secure architecture.</em></h1><p>A React home consuming a catalog protected by the Resource Server while the BFF keeps tokens outside the browser.</p><button className="button hero-button" onClick={() => setView('catalog')}>Explore catalog <span>-&gt;</span></button></div><div className="hero-art"><span className="hero-orbit orbit-one" /><span className="hero-orbit orbit-two" /><span className="hero-core">*</span><span className="hero-label label-top">BFF</span><span className="hero-label label-bottom">RESOURCE<br />SERVER</span></div></section>}
        <section className="catalog-section" id="catalog">
          <div className="section-heading"><div><span className="eyebrow">FEATURED COLLECTION</span><h2>{view === 'catalog' ? 'Product catalog' : 'See some products'}</h2></div>{session.authenticated && <span className="secure-badge">session protected</span>}</div>
          {session.authenticated && <>
            <div className="catalog-toolbar"><label className="search-field"><span>Search by name</span><input value={searchTerm} onChange={event => setSearchTerm(event.target.value)} placeholder="Ex.: Bluetooth" /></label><button className="button" onClick={() => setShowProductForm(current => !current)}>{showProductForm ? 'Close' : 'Insert product'}</button></div>
            {showProductForm && <form className="product-form" onSubmit={createProduct}><div className="form-row"><label>Name<input required value={draft.name} onChange={event => setDraft({ ...draft, name: event.target.value })} /></label><label>Price<input required type="number" min="0" step="0.01" value={draft.price} onChange={event => setDraft({ ...draft, price: event.target.value })} /></label></div><div className="form-row"><label>Icon<input required maxLength="4" value={draft.icon} onChange={event => setDraft({ ...draft, icon: event.target.value })} /></label><label>Category<input required value={draft.category} onChange={event => setDraft({ ...draft, category: event.target.value })} /></label></div>{formError && <p className="form-error">{formError}</p>}<button className="button" type="submit">Save product</button></form>}
            <ProductGrid products={visibleProducts} loading={catalogLoading} error={catalogError} authenticated onLogin={login} />
          </>}
          {!session.authenticated && <ProductGrid products={products} loading={catalogLoading} error={catalogError} authenticated={false} onLogin={login} />}
        </section>
        {session.authenticated && <section className="diagnostics"><div><span className="eyebrow">POC - CHECKS</span><h2>Protected resources</h2><p>Test Resource Server permissions using the BFF session.</p></div><div className="actions"><button onClick={() => call('protected')}>Protected</button><button onClick={() => call('admin')}>Admin</button><button onClick={() => call('me')}>Me</button></div>{result && <pre>{JSON.stringify(result, null, 2)}</pre>}</section>}
      </>}
    </main>
    <footer className="site-footer"><div><strong>POC Store</strong><span>Demonstration catalog for Architecture {architecture}.</span></div><span>React - Keycloak - Resource Server</span></footer>
  </div>;
}

createRoot(document.getElementById('root')).render(<App />);
