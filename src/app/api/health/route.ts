export const runtime = 'edge';
export async function GET() {
  return Response.json({ status: 'ok', name: 'NOOR ∞ API', version: '1.0.0' });
}
