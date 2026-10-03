import { getDb, run } from '../src/lib/db/client';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = dirname(fileURLToPath(import.meta.url));
const s = readFileSync(join(HERE,'qac_morphology_0_4.txt'),'utf8').replace(/\r\n/g,'\n');
const lines = s.split('\n');
const db = await getDb();
const roots = new Map<string,number>();
let n=0;
for (let i=57;i<lines.length;i++){
  const L = lines[i];
  if (!L.trim()) continue;
  if (!L.startsWith('(')) continue;
  const parts = L.split('\t');
  if (parts.length>=5){
    const m = parts[4].match(/ROOT:([A-Za-z]+)/);
    if (m){ const r=m[1]; roots.set(r,(roots.get(r)||0)+1); }
  }
  n++;
}
console.log('n',n,'r',roots.size);
let c=0;
for (const [r,rc] of roots){
  await run(db,`INSERT INTO roots (root_letters,derived,occurrence_count) VALUES ($1,true,$2) ON CONFLICT (root_letters) DO NOTHING`,[r,rc]);
  c++;
}
console.log('ins',c);
process.exit(0);
