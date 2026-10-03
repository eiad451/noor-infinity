/**
 * Citation validator (§14): verify parsed citations against indexed sources/entities.
 * - Never display a fabricated citation as verified
 * - If verification fails, mark as rejected/unresolved with reason
 */
export type CiteStatus = 'verified' | 'partial' | 'rejected' | 'unresolved';

export class CitationValidator {
  parseQuran(raw: string): { ok: boolean; surah?: number; ayah?: number; text?: string } {
    // Look for surah:ayah pattern in typical forms (1:1, 1:2–3)
    const m = raw.match(/([0-9]{1,3})\s*:\s*([0-9]{1,3})/);
    if (!m) return { ok: false, text: raw };
    const surah = parseInt(m[1]);
    const ayah = parseInt(m[2]);
    if (surah < 1 || surah > 114 || ayah < 1) return { ok: false, text: raw };
    return { ok: true, surah, ayah, text: raw };
  }

  // In the full build, we would hit DB. For the scaffold/ingest phase we only
  // validate syntax; actual resolution happens in the research pipeline.
  verifyQuran(surah: number, ayah: number): { status: CiteStatus; reason?: string } {
    if (surah < 1 || surah > 114 || ayah < 1) return { status: 'rejected', reason: 'invalid range' };
    return { status: 'unresolved', reason: 'not-resolved-in-this-phase' };
  }
}