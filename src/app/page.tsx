'use client';
import { useState } from 'react';

export default function Home() {
  const [q, setQ] = useState('');
  return (
    <main style={{ maxWidth: 1200, margin: '48px auto', padding: '0 24px' }}>
      <div style={{ display:'flex', flexDirection:'column', gap:24 }}>
        <header>
          <h1 style={{ fontSize: 56, margin: 0, letterSpacing: -0.5 }}>NOOR ∞</h1>
          <p style={{ opacity: 0.85, fontSize: 18, marginTop: 8 }}>Explore. Understand. Reflect.</p>
          <small style={{ opacity: 0.6 }}>Unified Islamic Knowledge Operating System — Accuracy • Trust • Privacy</small>
        </header>
        <div>
          <form onSubmit={(e)=>{e.preventDefault(); window.location.href = `/search?q=${encodeURIComponent(q)}`;}}>
            <input
              value={q}
              onChange={(e)=>setQ(e.target.value)}
              placeholder="Search Quran, Hadith, Tafsir, History, People, Places… (Ctrl+K)"
              style={{ width:'100%', padding:16, fontSize:18, border:'1px solid #ddd', borderRadius:12 }}
            />
          </form>
          <p style={{ fontSize:12, opacity:.6, marginTop:8 }}>
            Provenance-first. No manufactured religious evidence. Citations are verifiable.
          </p>
        </div>
        <nav style={{ display:'flex', flexWrap:'wrap', gap:12 }}>
          <a href="/quran">Quran</a>
          <a href="/explore">Explore</a>
          <a href="/research">Research Lab</a>
          <a href="/audio">Audio</a>
          <a href="/library">Library</a>
        </nav>
        <section style={{ padding:24, border:'1px solid #eee', borderRadius:12, background:'#fafafa' }}>
          <h2 style={{ marginTop:0 }}>Core Status</h2>
          <ul>
            <li>Database: PostgreSQL (PGlite) — schema migrated, RLS active</li>
            <li>Quran: 114 surahs, 6236 āyāt (Uthmani, Tanzil) — real, traceable</li>
            <li>Roots: 1532 Quranic roots (QAC v0.4) — morphology available</li>
            <li>AI: Provider abstraction + offline extractive mode (honest by design)</li>
            <li>Principle: Never fabricate citations or scripture</li>
          </ul>
        </section>
      </div>
    </main>
  );
}
