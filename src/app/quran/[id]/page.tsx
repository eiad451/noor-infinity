import { getDb } from '@/lib/db/client';
import { notFound } from 'next/navigation';

export default async function SurahPage({ params }: { params: { id: string } }) {
  const surahId = parseInt(params.id);
  const db = await getDb();
  const s = await db.query<any>(`SELECT * FROM quran_surahs WHERE id=$1`,[surahId]);
  if (s.rows.length===0) notFound();
  const sur = s.rows[0];
  const ay = await db.query<any>(`SELECT ayah_number,text_arabic FROM quran_ayahs WHERE surah_id=$1 ORDER BY ayah_number`,[surahId]);
  return (
    <main style={{ maxWidth: 900, margin:'40px auto', padding:'0 20px', direction:'rtl', fontFamily:'"Uthmanic Hafs", "Amiri", serif' }}>
      <h1 dir="rtl">{sur.name_arabic} — سُورَةُ {sur.name_arabic}</h1>
      <p dir="ltr" style={{ opacity:.8 }}>Surah {sur.id} • {sur.name_simple} • {sur.ayah_count} āyāt • {sur.revelation_place}</p>
      <div style={{ lineHeight:2.4, fontSize:24 }}>
        {ay.rows.map((a:any)=>(
          <span key={a.ayah_number}>{a.text_arabic}<small style={{ fontSize:12, opacity:.7, marginInline:6 }}>﴿{a.ayah_number}﴾</small> </span>
        ))}
      </div>
      <p dir="ltr" style={{ marginTop:40, opacity:.6, fontSize:12 }}>
        Source: Tanzil Uthmani (tanzil.net) — verified. Text shown as-is from indexed corpus.
      </p>
    </main>
  );
}
