# NOOR ∞ — Islamic Knowledge Operating System

"Explore. Understand. Reflect."

Production-grade Islamic knowledge platform built for accuracy, trust, and privacy.

## Key Principles
- Provenance-first: every claim traces to a verifiable source
- No manufactured evidence: never invents Quran/Hadith/Tafsir/citations
- Separation of concerns: source content vs interpretation vs AI analysis
- Privacy by default, RLS enforced, audit logging

## Stack
- Next.js 15 + TypeScript (App Router)
- PGlite (PostgreSQL in WASM)
- Normalized schema with dataset versioning

## Quick Start

```bash
pnpm install
pnpm db:migrate
pnpm db:ingest  # imports real Quran + roots (optional)
pnpm dev        # http://localhost:3000
pnpm build
pnpm start
```

## Data
- Quran: 114 surahs, 6236 āyāt (Uthmani, Tanzil.net)
- QAC morphology: 1532 roots (corpus.quran.com, GPL 3.0)

## License & Attribution
See data sources in schema/datasets. Respect upstream licenses.
