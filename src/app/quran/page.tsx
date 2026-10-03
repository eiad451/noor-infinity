import { getDb, one } from '@/lib/db/client';

export default async function QuranPage() {
  const db = await getDb();
  const surahs = await db.query<any>(`SELECT id,name_arabic,name_simple,ayah_count,revelation_place FROM quran_surahs ORDER BY id`);
  return (
    <main style={{ maxWidth: 900, margin: '40px auto', padding: '0 20px' }}>
      <h1>Qurʾān</h1>
      <p style={{ opacity:.8 }}>Uthmani text • Source: Tanzil • Verified dataset</p>
      <ol style={{ columns:2, columnGap:40, listStyle:'none', padding:0 }}>
        {surahs.rows.map((s:any)=>(
          <li key={s.id} style={{ marginBottom:12 }}>
            <a href={`/quran/${s.id}`}>{s.id}. {s.name_arabic} — {s.name_simple} ({s.ayah_count}) • {s.revelation_place}</a>
          </li>
        ))}
      </ol>
    </main>
  );
}
