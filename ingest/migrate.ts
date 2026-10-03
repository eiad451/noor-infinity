/** Applies db/migrations to the local PGlite instance and prints what ran. */
import { getDb, migrate } from '../src/lib/db/client';

const db = await getDb();
const applied = await migrate(db);
console.log(applied.length ? `applied: ${applied.join(', ')}` : 'schema already current');

const { rows } = await db.query<{ n: number }>(
  `SELECT count(*)::int AS n FROM information_schema.tables
   WHERE table_schema='public' AND table_type='BASE TABLE'`,
);
console.log(`tables: ${rows[0].n}`);

const pol = await db.query<{ n: number }>(
  `SELECT count(*)::int AS n FROM pg_policies WHERE schemaname='public'`,
);
console.log(`rls policies: ${pol.rows[0].n}`);

// Arabic text search config must exist — omnisearch depends on it.
const cfg = await db.query<{ n: number }>(
  `SELECT count(*)::int AS n FROM pg_ts_config WHERE cfgname='arabic'`,
);
if (cfg.rows[0].n !== 1) throw new Error('PostgreSQL `arabic` text-search configuration is missing');
console.log('arabic tsvector config: present');
process.exit(0);