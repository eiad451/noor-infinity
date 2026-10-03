import { getDb, run } from '../src/lib/db/client';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = dirname(fileURLToPath(import.meta.url));
const s = readFileSync(join(HERE,'qac_morphology_0_4.txt'),'utf8').replace(/\r\n/g,'\n').replace(/\r/g,'\n');
const lines = s.split('\n');
const db = await getDb();
const roots = new Map<string,number>();
let n=0;
for (let i=0;i<lines.length;i++){
  const L = lines[i];
  if (!L.trim()) continue;
  if (L.startsWith('#')) continue;
  if (L.startsWith('LOCATION')) continue;
  if (!L.startsWith('(')) continue;
  const t = L.split('\t');
  if (t.length>=5){
    const feat = t[4];
    const m = /ROOT:([A-Za-z]+)/.exec(feat);
    if (m){ const r=m[1]; roots.set(r,(roots.get(r)||0)+1); }
  }
  n++;
}
console.log(n, roots.size);
let ins=0;
for (const [r,c] of roots){
  await run(db,`INSERT INTO roots (root_letters,derived,occurrence_count) VALUES ($1,true,$2) ON CONFLICT (root_letters) DO NOTHING`,[r,c]);
  ins++;
}
console.log(ins);
process.exit(0);
