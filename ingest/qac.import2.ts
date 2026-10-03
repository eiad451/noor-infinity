import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getDb, one, run } from '../src/lib/db/client';

const HERE = dirname(fileURLToPath(import.meta.url));
const p = join(HERE,'qac_morphology_0_4.txt');
const db = await getDb();
const raw = readFileSync(p,'utf-8');
const lines = raw.split('\n');
const roots = new Map<string,number>();
let n=0;
for (let i=0;i<lines.length;i++){
  const L = lines[i];
  if (L.startsWith('#')||L.trim()==='') continue;
  if (L.startsWith('LOCATION')) continue;
  if (!L.startsWith('(')) continue;
  const t = L.split('\t');
  if (t.length<5) continue;
  const feat = t[4];
  const m = feat.match(/ROOT:([A-Za-z]+)/);
  if (m){
    const r = m[1];
    roots.set(r,(roots.get(r)||0)+1);
  }
  n++;
  if (n%50000===0) console.log('n',n,'roots',roots.size);
}
console.log('total',n,'roots',roots.size);
for (const [r,c] of roots){
  await run(db,`INSERT INTO roots (root_letters,derived,occurrence_count) VALUES ($1,true,$2) ON CONFLICT (root_letters) DO NOTHING`,[r,c]);
}
console.log('ok');
process.exit(0);
