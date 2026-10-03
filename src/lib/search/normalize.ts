export function stripDiacritics(s: string): string {
  return s.replace(/[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]/g, '');
}
export function normalizeQuery(s: string): string {
  let q = s.trim();
  q = q.replace(/ٱ/g, 'ا').replace(/آ/g, 'ا').replace(/أ/g, 'ا').replace(/إ/g, 'ا').replace(/ة/g, 'ه');
  return stripDiacritics(q);
}
export function isArabic(s: string): boolean {
  return /[\u0600-\u06FF]/.test(s);
}
