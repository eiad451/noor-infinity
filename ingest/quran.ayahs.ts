import { getDb, migrate, one, run } from '../src/lib/db/client';
import { readFileSync } from 'node:fs';

function stripDiacritics(s:string){ return s.replace(/[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]/g,''); }

const db = await getDb();
await migrate(db);

const dvQur: any = await one(db,`SELECT id FROM dataset_versions WHERE dataset_key='quran.uthmani.tanzil.v1'`);
const srcTanzil: any = await one(db,`SELECT id FROM sources WHERE source_key='tanzil.uthmani'`);
const sT = srcTanzil!.id, dQ = dvQur!.id;

// fetch from alquran.cloud (fast, served well)
const q = await fetch('https://api.alquran.cloud/v1/quran/quran-uthmani').then(r=>r.json());
const surArr = q.data.surahs as any[];
let globalIndex = 1;
for (let i=1;i<=114;i++){
  const sc = surArr.find((x:any)=>x.number===i);
  const ayList = sc.ayahs;
  for (let a=0;a<ayList.length;a++){
    const ay = ayList[a];
    await db.query(`
      INSERT INTO quran_ayahs
        (global_index,surah_id,ayah_number,juz_number,hizb_number,rub_number,page,sajda,
         text_arabic,text_search,char_count,words,source_id,dataset_version_id)
      VALUES ($1,$2,$3,1,1,1,1,false,$4,$5,$6,'[]'::jsonb,$7,$8)
      ON CONFLICT (surah_id,ayah_number) DO NOTHING
    `,[globalIndex++, i, ay.numberInSurah, ay.text, stripDiacritics(ay.text), ay.text.length, sT, dQ]);
  }
  if (i%10===0) console.log('done',i);
}
const r = await db.query<any>(`SELECT count(*)::int as n FROM quran_ayahs`);
console.log('total ayahs', r.rows[0].n);
