import { getDb, run } from '../src/lib/db/client';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const HERE = dirname(fileURLToPath(import.meta.url));
const db = await getDb();
const s = readFileSync(join(HERE,'qac_morphology_0_4.txt'),'utf8');
const lines = s.split('\n');
for (let i=0;i<lines.length;i++){
  const L = lines[i];
  if (!L||L[0]=='#'||L.startsWith('LOCATION')||!L.startsWith('(')) continue;
  const t = L.split('\t');
  if (t.length>=4){
    const f = t[3];
    const m = /ROOT:([A-Za-z]+)/.exec(f);
    if (m){
      const r = m[1];
      // write small batch? skip heavy loop writes - roots already inserted
    }
  }
}
console.log('ok');
