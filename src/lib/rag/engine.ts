/**
 * Provider abstraction (§13): swap providers without rewriting app.
 * RAG pipeline: retrieve → filter → rank → context → answer → citation validation.
 */
export type Provider = {
  id: string;
  name: string;
  supports: string[];
  generate: (ctx: RAGContext) => Promise<RAGResult>;
};

export type RAGContext = {
  question: string;
  language: 'ar'|'en';
  topK: number;
  sources: Array<{ entityId: number; text: string; title: string; type: 'ayah'|'hadith'|'tafsir'|'seerah' }>;
};

export type RAGResult = {
  text: string;
  mode: 'generated'|'extractive-no-provider';
  providerId: string;
  model: string;
  citations: Array<{ raw: string; status: string }>;
  failed: boolean;
  failureReason?: string;
};

/** Offline extractive mode: must not fabricate religious references. (§2, §14) */
export const offlineExtractive: Provider = {
  id: 'offline-extractive',
  name: 'NOOR Offline Extractive',
  supports: ['ayah-explain'],
  async generate(ctx: RAGContext): Promise<RAGResult> {
    if (ctx.sources.length === 0) {
      return {
        text: 'لا يمكن تقديم تحليل ديني مستند لعدم وجود مصادر مؤكدة في السياق. يمكن توسيع البحث أو استخدام مصادر فعلية.',
        mode: 'extractive-no-provider',
        providerId: 'offline-extractive',
        model: 'rules-1',
        citations: [],
        failed: false,
      };
    }
    // Concatenate source text verbatim (separation: SOURCE CONTENT not AI analysis)
    const parts = ctx.sources.map(s => s.text).join('\n\n');
    return {
      text: `Source material (verbatim excerpts from indexed corpus):\n\n${parts}\n\n[Interpretation: none generated in offline mode. User to draw conclusions from sources only.]`,
      mode: 'extractive-no-provider',
      providerId: 'offline-extractive',
      model: 'rules-1',
      citations: [],
      failed: false,
    };
  }
};

export class AIEngine {
  private providers = new Map<string, Provider>();
  constructor(){ this.providers.set('offline-extractive', offlineExtractive); }
  register(p: Provider){ this.providers.set(p.id,p); }
  async answer(ctx: RAGContext, pid='offline-extractive'): Promise<RAGResult> {
    const p = this.providers.get(pid); if (!p) throw new Error('unknown provider');
    return p.generate(ctx);
  }
}
