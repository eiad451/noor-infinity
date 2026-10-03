import { mkdirSync, existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getDb, one, run } from '../src/lib/db/client';

const HERE = dirname(fileURLToPath(import.meta.url));

async function main(){
  const db = await getDb();
  let dv = await one(db,`SELECT id FROM dataset_versions WHERE dataset_key='qac.morphology.0.4'`);
  if (dv && (dv as any).id) await run(db,`UPDATE dataset_versions SET status='pending' WHERE id=$1`,[(dv as any).id]);
  const p = join(HERE,'qac_morphology_0_4.txt');
  if (!existsSync(p)) { console.error('MISSING',p); process.exit(1); }
  const raw = readFileSync(p,'utf8');
  const lines = raw.split(/\r?\n/);
  let roots = new Map<string,string>();
  let count=0, rootSet=0;
  for (let i=0;i<lines.length;i++){
    const L=lines[i]; if (L.startsWith('#')||L.trim()==='') continue;
    if (L.startsWith('LOCATION')) continue;
    const t=L.split('\t');
    if (t.length<5) continue;
    const feat = t[4];
    const mroot = feat.match(/ROOT:([A-Za-z]+)/);
    if (mroot){
      const r = mroot[1];
      if (!roots.has(r)){ roots.set(r,r); rootSet++; }
    }
    count++;
    if (count%200000===0) console.log('scanned',count,'roots',rootSet);
  }
  console.log('done scan',count,rootSet);
  // small insert
  for (const [r] of roots){
    await run(db,`INSERT INTO roots (root_letters, derived) VALUES ($1,true) ON CONFLICT DO NOTHING`,[r]);
  }
  console.log('roots inserted');
  process.exit(0);
}
main().catch(e=>{console.error(e);process.exit(1);});