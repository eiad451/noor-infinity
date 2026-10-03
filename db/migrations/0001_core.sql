-- ═══════════════════════════════════════════════════════════════════════════
-- NOOR ∞ — 0001_core.sql
-- Islamic Knowledge Operating System — core normalized schema
-- Target: PostgreSQL 15+ (developed against PGlite = PostgreSQL 17 WASM)
--
-- DESIGN LAWS (enforced, not aspirational):
--  L1  No religious text ever enters this database without a row in `sources`
--      and a `dataset_versions` entry. source_id is NOT NULL on all content.
--  L2  Imported scripture text is immutable. Corrections go through a new
--      dataset_version, never an UPDATE (enforced by trigger below).
--  L3  User-private data is tenant-scoped by user_id and guarded by RLS.
--  L4  Grading is an attributed opinion, never a boolean on the hadith.
-- ═══════════════════════════════════════════════════════════════════════════

-- schema_migrations is owned by the runner (ingest/migrate.ts), not by a migration.

-- ─────────────────────────────── DATASET LINEAGE ───────────────────────────
-- §34 Data pipelines: versioning, validation, error reporting.
CREATE TABLE dataset_versions (
  id             bigserial PRIMARY KEY,
  dataset        text NOT NULL,            -- 'quran.uthmani' | 'qac.morphology' | ...
  version        text NOT NULL,            -- upstream version string
  dataset_key    text UNIQUE,              -- deterministic key for idempotent re-ingest
  source_url     text NOT NULL,
  license        text NOT NULL,
  attribution    text NOT NULL,
  upstream_sha256 text,
  byte_size      bigint,
  record_count   integer,
  status         text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','validated','ingested','rejected','quarantined')),
  validation     jsonb NOT NULL DEFAULT '{}'::jsonb,
  errors         jsonb NOT NULL DEFAULT '[]'::jsonb,
  ingested_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (dataset, version)
);

CREATE TABLE sources (
  id             bigserial PRIMARY KEY,
  source_key     text UNIQUE NOT NULL,     -- stable machine id, e.g. 'tanzil.uthmani'
  kind           text NOT NULL,            -- scripture | hadith | tafsir | seerah | lexicon | audio | dataset
  work           text NOT NULL,
  author         text,
  author_death   integer,
  citation_label text NOT NULL,            -- how the source is shown to humans
  edition        text,
  license        text,
  attribution    text,                     -- required display string
  homepage       text,
  dataset_version_id bigint REFERENCES dataset_versions(id),
  -- §43 zero fake functionality: a source with no real edition is not a source
  verified       boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────── QURAN ─────────────────────────────────────
CREATE TABLE quran_surahs (
  id            smallint PRIMARY KEY,      -- canonical surah number 1..114
  name_arabic   text NOT NULL,
  name_simple   text NOT NULL,
  name_complex  text NOT NULL,
  name_meaning  text NOT NULL,
  revelation_place text NOT NULL CHECK (revelation_place IN ('makkah','madinah')),
  revelation_order smallint NOT NULL,
  ayah_count    smallint NOT NULL CHECK (ayah_count > 0),
  start_page    smallint,
  juz_start     smallint,
  bismillah_pre boolean NOT NULL DEFAULT true,
  source_id     bigint NOT NULL REFERENCES sources(id),
  UNIQUE (name_simple)
);

CREATE TABLE quran_ayahs (
  id           bigserial PRIMARY KEY,
  global_index integer NOT NULL UNIQUE,    -- 1..6236 canonical order
  surah_id     smallint NOT NULL REFERENCES quran_surahs(id),
  ayah_number  smallint NOT NULL,
  juz_number   smallint NOT NULL CHECK (juz_number BETWEEN 1 AND 30),
  hizb_number  smallint NOT NULL CHECK (hizb_number BETWEEN 1 AND 60),
  rub_number   smallint NOT NULL CHECK (rub_number BETWEEN 1 AND 60),
  page         smallint NOT NULL,
  sajda        boolean NOT NULL DEFAULT false,
  sajdah_index smallint,                   -- which sajda within the surah
  text_arabic  text NOT NULL,              -- Uthmani, traceable
  text_search  text NOT NULL,              -- normalized (diacritics stripped) for search
  char_count   integer NOT NULL,
  words        jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{i,ar,tr}] real segmentation
  source_id    bigint NOT NULL REFERENCES sources(id),
  dataset_version_id bigint NOT NULL REFERENCES dataset_versions(id),
  UNIQUE (surah_id, ayah_number),
  UNIQUE (id, surah_id)
);
CREATE INDEX idx_ayah_surah      ON quran_ayahs (surah_id, ayah_number);
CREATE INDEX idx_ayah_juz        ON quran_ayahs (juz_number, global_index);
CREATE INDEX idx_ayah_page       ON quran_ayahs (page);
CREATE INDEX idx_ayah_words      ON quran_ayahs USING gin (words jsonb_path_ops);

-- FTS: scripture surface (Arabic config) + English translations joined later.
CREATE INDEX idx_ayah_ar_fts ON quran_ayahs
  USING gin (to_tsvector('arabic', text_search));
CREATE INDEX idx_ayah_len    ON quran_ayahs (char_count);

-- L2 immutability of ingested scripture text.
CREATE OR REPLACE FUNCTION forbid_scripture_mutation() RETURNS trigger AS $$
BEGIN
  IF NEW.text_arabic IS DISTINCT FROM OLD.text_arabic
     OR NEW.surah_id    IS DISTINCT FROM OLD.surah_id
     OR NEW.ayah_number IS DISTINCT FROM OLD.ayah_number THEN
    RAISE EXCEPTION
      'Quran text is immutable. Publish a new dataset_version (L2). row=% text=% -> %',
      OLD.id, left(OLD.text_arabic,20), left(NEW.text_arabic,20);
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_scripture_immutable BEFORE UPDATE ON quran_ayahs
  FOR EACH ROW EXECUTE FUNCTION forbid_scripture_mutation();

CREATE TABLE translations (
  id            bigserial PRIMARY KEY,
  resource_key  text UNIQUE NOT NULL,      -- 'en.sahih' | 'fr.hamidullah' ...
  language      text NOT NULL,
  language_name text NOT NULL,
  name          text NOT NULL,
  translator    text,
  type          text NOT NULL CHECK (type IN ('translation','tafsir')),
  source_id     bigint NOT NULL REFERENCES sources(id),
  verified      boolean NOT NULL DEFAULT false
);

CREATE TABLE quran_ayah_translations (
  ayah_id          bigint NOT NULL REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  translation_id   bigint NOT NULL REFERENCES translations(id) ON DELETE CASCADE,
  text             text NOT NULL,
  text_search      text NOT NULL,
  PRIMARY KEY (ayah_id, translation_id)
);
CREATE INDEX idx_ayat_tr ON quran_ayah_translations (translation_id, ayah_id);
CREATE INDEX idx_ayat_en_fts ON quran_ayah_translations
  USING gin (to_tsvector('english', text_search));

-- ───────────────────── MORPHOLOGY  (Quranic Arabic Corpus) ─────────────────
-- §8/§9: WORD → ROOT → OCCURRENCES. Real corpus annotation only.
CREATE TABLE roots (
  id             smallserial PRIMARY KEY,
  root_letters   text UNIQUE NOT NULL,     -- QAC Buckwalter translit, e.g. 'smw'
  root_arabic    text,                      -- normalized Arabic letters when derivable
  derived        boolean NOT NULL DEFAULT false,  -- true = normalized from translit
  occurrence_count integer NOT NULL DEFAULT 0
);

CREATE TABLE quran_words (
  id            bigserial PRIMARY KEY,
  ayah_id       bigint NOT NULL REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  word_index    smallint NOT NULL,          -- 1-based within ayah
  cluster_index smallint,                   -- QAC cluster (word group), nullable
  segment_index smallint NOT NULL,          -- prefix/suffix/stem decomposition
  form          text NOT NULL,              -- QAC FORM (Buckwalter transliteration)
  pos_tag       text NOT NULL,              -- QAC TAG: N,V,ADJ,PN,PRON,...
  features      jsonb NOT NULL DEFAULT '[]'::jsonb,
  lemma         text,
  root_id       smallint REFERENCES roots(id),
  glyph_arabic  text,                       -- Arabic word from word-by-word source
  dataset_version_id bigint NOT NULL REFERENCES dataset_versions(id),
  UNIQUE (ayah_id, word_index, segment_index)
);
CREATE INDEX idx_word_root ON quran_words (root_id);
CREATE INDEX idx_word_lemma ON quran_words (lemma);
CREATE INDEX idx_word_form  ON quran_words (form);
CREATE INDEX idx_word_ayah  ON quran_words (ayah_id);

-- ─────────────────────────────── HADITH ────────────────────────────────────
CREATE TABLE hadith_collections (
  id            smallserial PRIMARY KEY,
  collection_key text UNIQUE NOT NULL,      -- 'bukhari' | 'muslim' | ...
  name_arabic   text NOT NULL,
  name_english  text NOT NULL,
  author        text,
  author_death  integer,
  compiled      text,                       -- e.g. 3rd century AH
  hadith_count  integer,
  source_id     bigint NOT NULL REFERENCES sources(id),
  grading_system text NOT NULL DEFAULT 'none'
    CHECK (grading_system IN ('none','albani','alqadisi','nawawi','inline','explicit'))
);

CREATE TABLE hadith_chapters (
  id            bigserial PRIMARY KEY,
  collection_id smallint NOT NULL REFERENCES hadith_collections(id) ON DELETE CASCADE,
  book_number   smallint NOT NULL,
  chapter_number smallint NOT NULL,
  title_arabic  text NOT NULL,
  title_english text NOT NULL,
  hadith_count  integer,
  UNIQUE (collection_id, book_number, chapter_number)
);
CREATE INDEX idx_hchapter_book ON hadith_chapters (collection_id, book_number);

CREATE TABLE hadith (
  id            bigserial PRIMARY KEY,
  collection_id smallint NOT NULL REFERENCES hadith_collections(id) ON DELETE CASCADE,
  chapter_id    bigint REFERENCES hadith_chapters(id) ON DELETE SET NULL,
  ref_number    integer NOT NULL,           -- number within collection
  ref_in_book   integer NOT NULL,
  text_arabic   text,
  text_english  text,
  text_search   text NOT NULL DEFAULT '',
  chain_arabic  text,                       -- isnad when the dataset carries one
  source_id     bigint NOT NULL REFERENCES sources(id),
  dataset_version_id bigint NOT NULL REFERENCES dataset_versions(id),
  UNIQUE (collection_id, ref_number)
);
CREATE INDEX idx_hadith_chapter ON hadith (chapter_id);
CREATE INDEX idx_hadith_book    ON hadith (collection_id, ref_in_book);
CREATE INDEX idx_hadith_en_fts  ON hadith USING gin (to_tsvector('english', coalesce(text_search,'')));

-- L4: grading is an attributed opinion, may disagree, never collapses.
CREATE TABLE hadith_gradings (
  id            bigserial PRIMARY KEY,
  hadith_id     bigint NOT NULL REFERENCES hadith(id) ON DELETE CASCADE,
  grade         text NOT NULL,              -- 'Sahih' | 'Hasan' | 'Daif' | ...
  graded_by     text,                       -- scholar / muqri', nullable
  grading_source_id bigint REFERENCES sources(id),  -- who published the grading
  note          text,
  UNIQUE (hadith_id, grade, graded_by)
);
CREATE INDEX idx_hgrading ON hadith_gradings (hadith_id);

CREATE TABLE hadith_narrators (
  id           bigserial PRIMARY KEY,
  hadith_id    bigint NOT NULL REFERENCES hadith(id) ON DELETE CASCADE,
  position     smallint NOT NULL,
  name_arabic  text,
  name_normalized text,
  person_id    bigint,                        -- FK added below (people is defined later)
  UNIQUE (hadith_id, position)
);

-- ─────────────────────── KNOWLEDGE GRAPH (§10) ─────────────────────────────
CREATE TABLE entities (
  id           bigserial PRIMARY KEY,
  entity_key   text UNIQUE NOT NULL,        -- 'ayah:2:255' | 'person:ibrahim' | ...
  entity_type  text NOT NULL CHECK (entity_type IN
    ('ayah','surah','hadith','person','prophet','event','place','book','topic','scholar','source','term')),
  label        text NOT NULL,
  label_arabic text,
  description  text,
  payload      jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_id    bigint REFERENCES sources(id),
  confidence   numeric(3,2) NOT NULL DEFAULT 1.00
                CHECK (confidence >= 0 AND confidence <= 1),
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_entity_type ON entities (entity_type);
CREATE INDEX idx_entity_label ON entities USING gin (to_tsvector('simple', label));

CREATE TABLE relations (
  id           bigserial PRIMARY KEY,
  subject_id   bigint NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
  object_id    bigint NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
  relation_type text NOT NULL CHECK (relation_type IN
    ('REFERENCES','EXPLAINS','MENTIONS','RELATED_TO','OCCURRED_AT',
     'PART_OF','AUTHORED_BY','GRADED_BY','NARRATED_BY','SEGMENT_OF','OCCURS_IN')),
  weight       numeric(4,3) NOT NULL DEFAULT 1.000,
  source_id    bigint REFERENCES sources(id),
  confidence   numeric(3,2) NOT NULL DEFAULT 1.00,
  UNIQUE (subject_id, object_id, relation_type),
  CHECK (subject_id <> object_id)
);
CREATE INDEX idx_relation_subj ON relations (subject_id);
CREATE INDEX idx_relation_obj  ON relations (object_id);
CREATE INDEX idx_relation_type ON relations (relation_type);

-- ───────────────────────────── PEOPLE / PLACES / EVENTS ─────────────────────
CREATE TABLE people (
  id            bigserial PRIMARY KEY,
  person_key    text UNIQUE NOT NULL,       -- 'ibrahim', 'umar-ibn-al-khattab'
  name_arabic   text,
  name_latin    text NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('prophet','companion','successor',
                   'scholar','sahabi','imam','poet','other')),
  birth_year_ah integer, death_year_ah integer,
  birth_year    integer, death_year        integer,   -- Gregorian when certain
  date_precision text NOT NULL DEFAULT 'unknown'
                 CHECK (date_precision IN ('exact','approximate','unknown')),
  birth_approx  boolean NOT NULL DEFAULT false,
  death_approx  boolean NOT NULL DEFAULT false,
  tribe         text,
  epithet       text,
  biography     text,
  quran_refs    jsonb NOT NULL DEFAULT '[]'::jsonb,  -- [{surah,ayahs:[],note}]
  summary       text,
  source_id     bigint NOT NULL REFERENCES sources(id)
);
CREATE INDEX idx_people_kind ON people (kind);

ALTER TABLE hadith_narrators
  ADD CONSTRAINT fk_hadith_narrators_person
  FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE SET NULL;

CREATE TABLE places (
  id            bigserial PRIMARY KEY,
  place_key     text UNIQUE NOT NULL,       -- 'makkah','uhud','tabuk'
  name_arabic   text,
  name_latin    text NOT NULL,
  kind          text NOT NULL CHECK (kind IN
    ('sacred_site','city','mountain','valley','desert','river','region','oasis','port')),
  modern_country text,
  latitude      numeric(9,6), longitude     numeric(9,6),
  coordinate_precision text NOT NULL DEFAULT 'city'
                 CHECK (coordinate_precision IN ('exact','site','city','region','unknown')),
  note          text,
  source_id     bigint NOT NULL REFERENCES sources(id),
  CHECK (latitude  IS NULL OR (latitude  BETWEEN  -90 AND  90)),
  CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180))
);

CREATE TABLE events (
  id            bigserial PRIMARY KEY,
  event_key     text UNIQUE NOT NULL,
  title         text NOT NULL,
  title_arabic  text,
  summary       text,
  detail        text,
  hijri_year    integer, hijri_month smallint, hijri_day smallint,
  gregorian_year integer, gregorian_month smallint, gregorian_day smallint,
  date_precision text NOT NULL DEFAULT 'unknown'
                 CHECK (date_precision IN ('exact','approximate','unknown','hijri_only','gregorian_only')),
  date_note     text,                        -- explains why precision is what it is
  place_id      bigint REFERENCES places(id) ON DELETE SET NULL,
  category      text NOT NULL DEFAULT 'seerah'
                 CHECK (category IN ('seerah','history','prophethood','compilation','science')),
  hijri_month_name_guess boolean NOT NULL DEFAULT false,  -- arithmetic conversions are guesses
  -- §43: a scene that cannot be sourced must not exist
  sourced       boolean NOT NULL DEFAULT false,
  uncertainty   text,
  source_id     bigint NOT NULL REFERENCES sources(id)
);
CREATE INDEX idx_events_year ON events (gregorian_year);
CREATE INDEX idx_events_cat  ON events (category);

CREATE TABLE event_people (
  event_id  bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  person_id bigint NOT NULL REFERENCES people(id) ON DELETE CASCADE,
  role      text NOT NULL DEFAULT 'involved',
  PRIMARY KEY (event_id, person_id, role)
);

CREATE TABLE event_places (
  event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  place_id bigint NOT NULL REFERENCES places(id) ON DELETE CASCADE,
  PRIMARY KEY (event_id, place_id)
);

CREATE TABLE event_references (
  id         bigserial PRIMARY KEY,
  event_id   bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  ayah_id    bigint REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  hadith_id  bigint REFERENCES hadith(id) ON DELETE CASCADE,
  source_id  bigint NOT NULL REFERENCES sources(id),
  note       text,
  CHECK (ayah_id IS NOT NULL OR hadith_id IS NOT NULL)
);

CREATE TABLE topics (
  id        bigserial PRIMARY KEY,
  topic_key text UNIQUE NOT NULL,
  name_en   text NOT NULL,
  name_ar   text,
  parent_id bigint REFERENCES topics(id) ON DELETE SET NULL,
  summary   text,
  source_id bigint REFERENCES sources(id)
);

CREATE TABLE ayah_topics (
  ayah_id    bigint NOT NULL REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  topic_id   bigint NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
  method     text NOT NULL DEFAULT 'curated'   -- curated | corpus-derived | ai-suggested
             CHECK (method IN ('curated','corpus-derived','ai-suggested')),
  confidence numeric(3,2) NOT NULL DEFAULT 1.00,
  source_id  bigint REFERENCES sources(id),
  PRIMARY KEY (ayah_id, topic_id)
);

CREATE TABLE ayah_links (
  ayah_id     bigint NOT NULL REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  related_id  bigint NOT NULL REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  relation    text NOT NULL DEFAULT 'RELATED_TO'
              CHECK (relation IN ('RELATED_TO','REFLECTS','PARALLELS','CONTRASTS')),
  note        text,
  source_id   bigint REFERENCES sources(id),
  PRIMARY KEY (ayah_id, related_id, relation),
  CHECK (ayah_id <> related_id)
);

-- ───────────────────────────── TAFSIR (§7, §12) ────────────────────────────
-- Only tafsir text the pipeline actually retrieved from a named work is stored.
CREATE TABLE tafsir (
  id           bigserial PRIMARY KEY,
  ayah_id      bigint NOT NULL REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  translation_id bigint REFERENCES translations(id) ON DELETE SET NULL,
  author       text NOT NULL,
  work         text NOT NULL,
  volume       text, page_no text, edition text,
  language     text NOT NULL DEFAULT 'en',
  text         text NOT NULL,
  text_search  text NOT NULL,
  source_id    bigint NOT NULL REFERENCES sources(id),
  dataset_version_id bigint REFERENCES dataset_versions(id),
  UNIQUE (ayah_id, work, language, edition)
);
CREATE INDEX idx_tafsir_ayah ON tafsir (ayah_id);
CREATE INDEX idx_tafsir_fts  ON tafsir USING gin (to_tsvector('english', text_search));

-- ───────────────────────────── AUDIO (§20) ─────────────────────────────────
-- We LINK to recitations; we never bundle third-party audio.
CREATE TABLE audio_tracks (
  id           bigserial PRIMARY KEY,
  track_key    text UNIQUE NOT NULL,
  reciter      text NOT NULL,
  style        text,                          -- murattal | mujawwad
  audio_url    text NOT NULL,                -- direct CDN, everyayah / islamic.network
  duration_s   integer,
  bitrate      integer,
  license_note text NOT NULL,
  source_id    bigint NOT NULL REFERENCES sources(id),
  available    boolean NOT NULL DEFAULT true,
  CHECK (audio_url ~ '^https://')
);

CREATE TABLE audio_segments (
  id        bigserial PRIMARY KEY,
  track_id  bigint NOT NULL REFERENCES audio_tracks(id) ON DELETE CASCADE,
  ayah_id   bigint NOT NULL REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  url       text NOT NULL CHECK (url ~ '^https://'),
  start_ms  integer,                         -- only when timing data exists
  end_ms    integer,
  duration_s integer,
  has_timing boolean NOT NULL DEFAULT false,
  UNIQUE (track_id, ayah_id)
);

-- ───────────────────── ADHKAR & DUAS (§25) ─────────────────────────────────
CREATE TABLE duas (
  id          bigserial PRIMARY KEY,
  dua_key     text UNIQUE NOT NULL,
  title_en    text NOT NULL, title_ar text,
  category    text NOT NULL,
  arabic_text text NOT NULL,
  transliteration text, translation text,
  occasions   text,
  repetitions integer,                       -- NULL = no sourced repetition count
  repetition_source text,                    -- must name where the count comes from
  reference   text,                          -- e.g. 'Sahih al-Bukhari 6309'
  hadith_id   bigint REFERENCES hadith(id) ON DELETE SET NULL,
  source_id   bigint NOT NULL REFERENCES sources(id),
  verified    boolean NOT NULL DEFAULT false
);

CREATE TABLE adhkar (
  id          bigserial PRIMARY KEY,
  dhikr_key   text UNIQUE NOT NULL,
  category    text NOT NULL,
  arabic_text text NOT NULL,
  transliteration text, translation text,
  repetitions integer,
  repetition_source text,
  reference   text,
  source_id   bigint NOT NULL REFERENCES sources(id),
  verified    boolean NOT NULL DEFAULT false
);
CREATE INDEX idx_adhkar_cat ON adhkar (category);

-- ───────────────────────── LEARNING (§21, §23) ─────────────────────────────
CREATE TABLE learning_paths (
  id        bigserial PRIMARY KEY,
  path_key  text UNIQUE NOT NULL,
  title     text NOT NULL, description text,
  level     text NOT NULL CHECK (level IN ('FOUNDATION','INTERMEDIATE','ADVANCED','RESEARCH')),
  subject   text NOT NULL,
  position  integer NOT NULL DEFAULT 0
);

CREATE TABLE learning_lessons (
  id        bigserial PRIMARY KEY,
  path_id   bigint NOT NULL REFERENCES learning_paths(id) ON DELETE CASCADE,
  position  integer NOT NULL,
  title     text NOT NULL,
  body      text NOT NULL,
  objective text,
  ayah_id   bigint REFERENCES quran_ayahs(id) ON DELETE SET NULL,
  hadith_id bigint REFERENCES hadith(id) ON DELETE SET NULL,
  UNIQUE (path_id, position)
);

CREATE TABLE progress (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL,
  lesson_id   bigint NOT NULL REFERENCES learning_lessons(id) ON DELETE CASCADE,
  status      text NOT NULL DEFAULT 'not_started'
              CHECK (status IN ('not_started','in_progress','completed')),
  -- §23: progress on material only. No score of the person, no faith rating.
  started_at  timestamptz, completed_at timestamptz,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, lesson_id)
);

CREATE TABLE memorization_items (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL,
  ayah_id     bigint NOT NULL REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  ease        numeric(3,2) NOT NULL DEFAULT 2.50,
  interval_days integer NOT NULL DEFAULT 0,
  repetitions  integer NOT NULL DEFAULT 0,
  lapses       integer NOT NULL DEFAULT 0,
  due_at      timestamptz NOT NULL DEFAULT now(),
  last_reviewed_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, ayah_id)
);
CREATE INDEX idx_memo_due ON memorization_items (user_id, due_at);

CREATE TABLE revision_sessions (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL,
  mode       text NOT NULL CHECK (mode IN ('hide_reveal','audio_loop','dictation')),
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at   timestamptz,
  items_seen integer NOT NULL DEFAULT 0,
  revealed   integer NOT NULL DEFAULT 0,
  correct    integer NOT NULL DEFAULT 0,
  mistake_ids jsonb NOT NULL DEFAULT '[]'::jsonb
);

-- ─────────────────────── PERSONAL KNOWLEDGE VAULT (§22) ────────────────────
CREATE TABLE collections (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL,
  name       text NOT NULL,
  kind       text NOT NULL DEFAULT 'mixed'
             CHECK (kind IN ('mixed','ayah','hadith','research','note','audio','topic','video')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, name)
);

CREATE TABLE bookmarks (
  id           bigserial PRIMARY KEY,
  user_id      bigint NOT NULL,
  target_type  text NOT NULL CHECK (target_type IN
               ('ayah','surah','hadith','person','place','event','topic','track','dua','dhikr','collection')),
  target_id    bigint NOT NULL,
  surah_id     smallint REFERENCES quran_surahs(id) ON DELETE CASCADE,
  label        text,
  note         text,
  ayah_id      bigint REFERENCES quran_ayahs(id) ON DELETE CASCADE,
  hadith_id    bigint REFERENCES hadith(id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, target_type, target_id)
);
CREATE INDEX idx_bm_user ON bookmarks (user_id, created_at DESC);

CREATE TABLE notes (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL,
  body        text NOT NULL,
  title       text,
  collection_id bigint REFERENCES collections(id) ON DELETE SET NULL,
  ayah_id     bigint REFERENCES quran_ayahs(id) ON DELETE SET NULL,
  hadith_id   bigint REFERENCES hadith(id) ON DELETE SET NULL,
  tags        text[] NOT NULL DEFAULT '{}',
  encrypted   boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notes_user ON notes (user_id, updated_at DESC);

-- ─────────────────────────── RESEARCH LAB (§12) ────────────────────────────
CREATE TABLE research_projects (
  id          bigserial PRIMARY KEY,
  user_id     bigint,
  slug        text UNIQUE NOT NULL,
  question    text NOT NULL,
  language    text NOT NULL DEFAULT 'en',
  status      text NOT NULL DEFAULT 'open'
              CHECK (status IN ('open','complete','failed')),
  scope       jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- hard separation: source content vs interpretation vs AI analysis
  findings    jsonb NOT NULL DEFAULT '[]'::jsonb,
  uncertainties jsonb NOT NULL DEFAULT '[]'::jsonb,
  differences jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE research_sources (
  id          bigserial PRIMARY KEY,
  project_id  bigint NOT NULL REFERENCES research_projects(id) ON DELETE CASCADE,
  tier        text NOT NULL CHECK (tier IN ('primary','secondary','tertiary')),
  entity_type text NOT NULL,
  entity_id   bigint NOT NULL,
  relevance   numeric(4,3) NOT NULL DEFAULT 1.0,
  rank_score  jsonb NOT NULL DEFAULT '{}'::jsonb,
  selected_by text NOT NULL DEFAULT 'retrieval'
              CHECK (selected_by IN ('retrieval','user','ai-suggested'))
);
CREATE INDEX idx_rs_project ON research_sources (project_id, relevance DESC);

-- §13/§14 the citation ledger. Nothing the AI said exists without a row here.
CREATE TABLE citations (
  id            bigserial PRIMARY KEY,
  project_id    bigint REFERENCES research_projects(id) ON DELETE CASCADE,
  answer_id     bigint,
  raw           text NOT NULL,
  parsed_type   text, parsed_surah smallint, parsed_ayah smallint,
  parsed_hadith_collection text, parsed_hadith_number integer,
  resolved_entity_id bigint REFERENCES entities(id) ON DELETE SET NULL,
  status        text NOT NULL DEFAULT 'unverified'
                CHECK (status IN ('verified','partial','rejected','unresolved')),
  verdict_reason text,
  matched_text  text,
  similarity    numeric(5,4),
  validator     text,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_cite_project ON citations (project_id);

CREATE TABLE ai_answers (
  id          bigserial PRIMARY KEY,
  project_id  bigint NOT NULL REFERENCES research_projects(id) ON DELETE CASCADE,
  provider    text NOT NULL,
  model       text NOT NULL,
  mode        text NOT NULL,              -- 'generated' | 'extractive-no-provider'
  text        text NOT NULL,
  context_entities jsonb NOT NULL DEFAULT '[]'::jsonb,
  prompt_tokens integer, completion_tokens integer,
  latency_ms  integer,
  failed      boolean NOT NULL DEFAULT false,
  failure_reason text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────── IDENTITY & RBAC (§31) ─────────────────────────
CREATE TABLE roles (
  id    smallserial PRIMARY KEY,
  key   text UNIQUE NOT NULL CHECK (key IN ('anonymous','user','researcher','editor','admin')),
  name  text NOT NULL,
  description text
);

CREATE TABLE permissions (
  id    smallserial PRIMARY KEY,
  key   text UNIQUE NOT NULL,     -- 'quran:read', 'admin:write', ...
  description text
);

CREATE TABLE role_permissions (
  role_id       smallint NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id smallint NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE users (
  id            bigserial PRIMARY KEY,
  email         text NOT NULL CHECK (email = lower(email) AND position('@' in email) > 1),
  password_hash text,                              -- scrypt: N$r$p$salt$hash
  display_name  text NOT NULL,
  locale        text NOT NULL DEFAULT 'en' CHECK (locale IN ('en','ar')),
  theme         text NOT NULL DEFAULT 'system'
                CHECK (theme IN ('system','dark','light','high-contrast')),
  reduced_motion boolean NOT NULL DEFAULT false,
  disabled      boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_login_at timestamptz
);
CREATE UNIQUE INDEX idx_users_email ON users (email);

CREATE TABLE user_roles (
  user_id  bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id  smallint NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

CREATE TABLE sessions (
  id           text PRIMARY KEY,             -- sha256 of the opaque token
  user_id      bigint REFERENCES users(id) ON DELETE CASCADE,
  csrf_token   text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  ip_hash      text,
  user_agent   text,
  revoked_at   timestamptz
);
CREATE INDEX idx_sessions_user ON sessions (user_id);
CREATE INDEX idx_sessions_exp  ON sessions (expires_at);

-- ──────────────────── AUDIT LOG (§31, §33) ────────────────────────────────
CREATE TABLE audit_logs (
  id          bigserial PRIMARY KEY,
  at          timestamptz NOT NULL DEFAULT now(),
  user_id     bigint,
  actor       text NOT NULL,
  action      text NOT NULL,
  target_type text, target_id text,
  outcome     text NOT NULL DEFAULT 'ok' CHECK (outcome IN ('ok','denied','error')),
  ip_hash     text,
  meta        jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX idx_audit_at   ON audit_logs (at DESC);
CREATE INDEX idx_audit_user ON audit_logs (user_id, at DESC);
CREATE INDEX idx_audit_act  ON audit_logs (action, at DESC);

-- ─────────────────── PRAYER SETTINGS (§26) ─────────────────────────────────
CREATE TABLE prayer_settings (
  user_id        bigint PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  latitude       numeric(9,6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude      numeric(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  city_name      text NOT NULL,
  time_zone      text,                          -- IANA, e.g. Africa/Cairo
  utc_offset_min integer NOT NULL DEFAULT 0,
  method         text NOT NULL DEFAULT 'MWL'
    CHECK (method IN ('MWL','ISNA','EGYPT','MAKKAH','KARACHI','TEHRAN','JAFAR','UMQALRAH','GULF','KUWAIT','QATAR','SINGAPORE','TURKEY','FRANCE','RUSSIA','MOONSIGHTING_COMMITTEE')),
  asr_method     text NOT NULL DEFAULT 'standard' CHECK (asr_method IN ('standard','hanafi')),
  high_lat_method text NOT NULL DEFAULT 'middleofnight'
    CHECK (high_lat_method IN ('middleofnight','anglebased','onefifth','twilight')),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- ─────────────── DAILY NOOR (§24) — deterministic, sourced ─────────────────
CREATE TABLE daily_noor (
  day          date PRIMARY KEY,
  ayah_id      bigint NOT NULL REFERENCES quran_ayahs(id),
  tafsir_id    bigint REFERENCES tafsir(id) ON DELETE SET NULL,
  hadith_id    bigint REFERENCES hadith(id) ON DELETE SET NULL,
  event_id     bigint REFERENCES events(id) ON DELETE SET NULL,
  topic_id     bigint REFERENCES topics(id) ON DELETE SET NULL,
  reflection_prompt text NOT NULL,
  provenance   jsonb NOT NULL DEFAULT '{}'::jsonb,
  generated_at timestamptz NOT NULL DEFAULT now()
);

-- ─────────── OBSERVABILITY + SEARCH METRICS (§36) ─────────────────────────
CREATE TABLE search_logs (
  id          bigserial PRIMARY KEY,
  user_id     bigint,
  query       text NOT NULL,
  language    text, intent text, normalized text,
  result_count integer NOT NULL DEFAULT 0,
  latency_ms  integer NOT NULL,
  stages      jsonb NOT NULL DEFAULT '[]'::jsonb,
  at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_slog_at ON search_logs (at DESC);
-- §36: never log sensitive user content unnecessarily
CREATE TABLE ai_events (
  id         bigserial PRIMARY KEY,
  provider   text NOT NULL, model text NOT NULL,
  ok         boolean NOT NULL, latency_ms integer,
  tokens_in  integer, tokens_out integer,
  citation_failures integer NOT NULL DEFAULT 0,
  error_class text, at timestamptz NOT NULL DEFAULT now()
);

-- ═══════════════════════ ROW LEVEL SECURITY (L3) ══════════════════════════
ALTER TABLE notes             ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookmarks         ENABLE ROW LEVEL SECURITY;
ALTER TABLE research_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress          ENABLE ROW LEVEL SECURITY;
ALTER TABLE memorization_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE collections       ENABLE ROW LEVEL SECURITY;
ALTER TABLE prayer_settings   ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION current_uid() RETURNS bigint AS $$
  SELECT NULLIF(current_setting('noor.user_id', true), '')::bigint;
$$ LANGUAGE sql STABLE;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['notes','bookmarks','research_projects','progress',
                           'memorization_items','collections','prayer_settings'] LOOP
    EXECUTE format($f$
      CREATE POLICY %1$s_own ON %1$I
        USING (user_id IS NOT DISTINCT FROM current_uid())
        WITH CHECK (user_id IS NOT DISTINCT FROM current_uid());
    $f$, t);
  END LOOP;
END $$;

-- ═════════════════════ SEED: RBAC + ROLES (§31) ═══════════════════════════
INSERT INTO roles (key, name, description) VALUES
 ('anonymous','Visitor','Unauthenticated, read-only public knowledge'),
 ('user','Member','Full personal vault, learning and research'),
 ('researcher','Researcher','Create and share public research projects'),
 ('editor','Content Editor','Import and version datasets'),
 ('admin','Administrator','System administration, audited');

INSERT INTO permissions (key, description) VALUES
 ('quran:read','Read Quran text, translations, tafsir'),
 ('hadith:read','Read hadith collections and gradings'),
 ('search:use','Run omnisearch and semantic retrieval'),
 ('research:create','Create research projects'),
 ('research:public','Publish research projects'),
 ('vault:write','Write personal collections, notes, bookmarks'),
 ('learning:write','Record learning progress and revision'),
 ('audio:play','Stream recitation audio'),
 ('admin:content','Import and version datasets'),
 ('admin:users','Manage users and roles'),
 ('admin:audit','Read audit logs'),
 ('admin:system','Read system health and metrics');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON (
  (r.key='anonymous' AND p.key IN ('quran:read','hadith:read','search:use','audio:play'))
  OR (r.key IN ('user','researcher','editor','admin') AND p.key IN
      ('quran:read','hadith:read','search:use','research:create','vault:write','learning:write','audio:play'))
  OR (r.key IN ('researcher','editor','admin') AND p.key='research:public')
  OR (r.key IN ('editor','admin') AND p.key='admin:content')
  OR (r.key='admin' AND p.key IN ('admin:users','admin:audit','admin:system'))
);