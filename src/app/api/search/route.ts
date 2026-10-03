export const runtime = 'edge';
export default async function SearchAPI(req: Request) {
  const { searchParams } = new URL(req.url);
  const q = searchParams.get('q') || '';
  return Response.json({ query: q, results: [], message: 'Omnisearch scaffold — pipeline implementation pending', sources: ['corpus:scaffold'] });
}
