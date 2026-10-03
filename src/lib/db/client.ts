import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
export const MIGRATIONS_DIR = join(HERE, '../../../db/migrations');
export const DATA_DIR = process.env.NOOR_DATA_DIR ?? join(HERE, '../../../.noor-data');

let instance: PGlite | null = null;
let starting: Promise<PGlite> | null = null;

export async function getDb(): Promise<PGlite> {
  if (instance) return instance;
  if (starting) return starting;
  starting = (async () => {
    const db = await PGlite.create({ dataDir: DATA_DIR });
    await db.exec(`SELECT set_config('noor.app', 'noor', false)`);
    instance = db;
    return db;
  })();
  return starting;
}

export async function createTestDb(): Promise<PGlite> {
  return PGlite.create();
}

export function checksum(sql: string): string {
  return createHash('sha256').update(sql).digest('hex').slice(0, 32);
}

export async function migrate(db: PGlite, dir = MIGRATIONS_DIR): Promise<string[]> {
  const applied: string[] = [];
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();

  await (db as any).exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now(), checksum text NOT NULL)`);

  const { rows } = await (db as any).query(
    'SELECT version, checksum FROM schema_migrations',
  );
  const seen = new Map(rows.map((r:any) => [r.version, r.checksum]));

  for (const file of files) {
    const sql = readFileSync(join(dir, file), 'utf8');
    const version = file.replace(/\.sql$/, '');
    const sum = checksum(sql);

    const prior = seen.get(version);
    if (prior) {
      if (prior !== sum) {
        throw new Error(`MIGRATION DRIFT: ${version}`);
      }
      continue;
    }

    await (db as any).exec('BEGIN');
    try {
      await (db as any).exec(sql);
      await (db as any).query('INSERT INTO schema_migrations (version, checksum) VALUES ($1,$2)', [version, sum]);
      await (db as any).exec('COMMIT');
      applied.push(version);
    } catch (err) {
      await (db as any).exec('ROLLBACK').catch(() => {});
      const msg = err instanceof Error ? err.message : String(err);
      throw new Error(`Migration ${version} failed: ${msg}`);
    }
  }
  return applied;
}

export async function asUser<T>(db: PGlite, uid: number | null, fn: (q: any) => Promise<T>): Promise<T> {
  await db.query(`SELECT set_config('noor.user_id', $1, false)`, [uid === null ? '' : String(uid)]);
  try { return await fn(db as any); } finally { await db.query(`SELECT set_config('noor.user_id', '', false)`); }
}

export async function all<T = Row>(db: PGlite, sql: string, params: unknown[] = []): Promise<T[]> {
  const r = await (db as any).query(sql, params as never[]);
  return r.rows as T[];
}
export async function one<T = Row>(db: PGlite, sql: string, params: unknown[] = []): Promise<T | null> {
  const r = await (db as any).query(sql, params as never[]);
  return (r.rows[0] as T) ?? null;
}
export async function run(db: PGlite, sql: string, params: unknown[] = []) {
  return (db as any).query(sql, params as never[]);
}
export type Row = Record<string, unknown>;
