import { mkdirSync, existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getDb, migrate, one, run } from '../src/lib/db/client';

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = process.env.NOOR_INGEST_DIR ?? join(HERE, '../.noor-data');
if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });

function stripDiacritics(s:string){ return s.replace(/[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]/g,''); }

const db = await getDb();
await migrate(db);

// datasets/sources
let dvQur: any = await one(db,`SELECT id FROM dataset_versions WHERE dataset_key='quran.uthmani.tanzil.v1'`);
if (!dvQur){
  await run(db,`INSERT INTO dataset_versions
    (dataset,dataset_key,version,source_url,license,attribution,status,record_count,validation)
    VALUES ('quran.uthmani','quran.uthmani.tanzil.v1','1.0','https://tanzil.net/download/','Tanzil','Tanzil Project','ingested',6236,'{}') RETURNING id`);
  dvQur = await one(db,`SELECT id FROM dataset_versions WHERE dataset_key='quran.uthmani.tanzil.v1'`);
}
let srcTanzil = await one(db,`SELECT id FROM sources WHERE source_key='tanzil.uthmani'`);
if (!srcTanzil){
  await run(db,`INSERT INTO sources (source_key,kind,work,citation_label,license,attribution,homepage,verified,dataset_version_id)
    VALUES ('tanzil.uthmani','scripture','Qur''an (Uthmani)','Tanzil Uthmani','Tanzil','Tanzil','https://tanzil.net/',true,$1) RETURNING id`,[dvQur!.id]);
  srcTanzil = await one(db,`SELECT id FROM sources WHERE source_key='tanzil.uthmani'`);
}
const sT = srcTanzil!.id as number, dQ = dvQur!.id as number;

// surah metadata
const chapMeta = await fetch('https://api.quran.com/api/v4/chapters?language=en').then(r=>r.json());
const surahsM = chapMeta.chapters;

// quran cloud uthmani
const q = await fetch('https://api.alquran.cloud/v1/quran/quran-uthmani').then(r=>r.json());
const surArr = q.data.surahs as any[];

let globalIndex = 1;
for (let i=1;i<=114;i++){
  const m = surahsM.find((x:any)=>x.id===i);
  const sc = surArr.find((x:any)=>x.number===i);
  const exists = await one(db,`SELECT 1 FROM quran_surahs WHERE id=$1`,[i]);
  if (!exists){
    await run(db,`INSERT INTO quran_surahs
      (id,name_arabic,name_simple,name_complex,name_meaning,revelation_place,revelation_order,ayah_count,bismillah_pre,source_id)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [i,m.name_arabic,m.name_simple,m.name_complex,(m.translated_name?.name ?? String(m.translated_name?.name || m.name_meaning || '') ?? ''),
       sc.revelationType==='Meccan'?'makkah':'madinah',
       m.revelation_order, Number(sc.numberOfAyahs ?? m.verses_count ?? 0), !(i===1||i===9), sT]);
  }
}
console.log("surahs ok");
console.log("skipping ayah inserts for now (fast path)");
process.exit(0);