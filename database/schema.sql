-- Market Expansion Engine — Supabase Schema
-- Run this in your Supabase SQL editor before importing the n8n workflows.

-- ============================================================
-- TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS leads (
  place_id              TEXT PRIMARY KEY,
  business_name         TEXT NOT NULL,
  category              TEXT,
  full_address          TEXT,
  city                  TEXT,
  state                 TEXT,
  zip                   TEXT,
  phone                 TEXT,
  website               TEXT,
  google_rating         NUMERIC(3,1),
  review_count          INTEGER DEFAULT 0,
  maps_description      TEXT,
  opening_hours         TEXT,
  google_maps_url       TEXT,
  latitude              NUMERIC(10,7),
  longitude             NUMERIC(10,7),
  source_query          TEXT,
  source_lat            NUMERIC(10,7),
  source_lng            NUMERIC(10,7),
  source_country_code   TEXT DEFAULT 'us',
  source_language       TEXT DEFAULT 'en',
  scraped_at            TIMESTAMPTZ DEFAULT NOW(),
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lead_enrichment (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  place_id            TEXT REFERENCES leads(place_id) ON DELETE CASCADE UNIQUE,
  -- Contact data
  email               TEXT,
  all_emails_found    TEXT,
  website_phone       TEXT,
  all_phones_found    TEXT,
  owner_name          TEXT,
  -- Social platforms
  linkedin_profiles   TEXT,   -- individual linkedin.com/in/ URLs
  linkedin            TEXT,   -- company page
  facebook            TEXT,
  instagram           TEXT,
  twitter             TEXT,
  youtube             TEXT,
  tiktok              TEXT,
  -- Metadata
  company_description TEXT,
  email_valid         TEXT,   -- 'valid', 'no MX', 'check failed', or empty
  crawl_status        TEXT,   -- 'ok (N/3 pages)', 'blocked - ...', 'no website'
  sitemap_used        BOOLEAN DEFAULT FALSE,
  pages_crawled       INTEGER DEFAULT 0,
  enriched_at         TIMESTAMPTZ DEFAULT NOW(),
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lead_errors (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  place_id        TEXT REFERENCES leads(place_id) ON DELETE SET NULL,
  run_id          UUID,
  run_type        TEXT,         -- 'scrape' or 'enrich'
  error_type      TEXT,         -- 'HARD_BLOCKED', 'NO_EMAIL_FOUND', etc.
  error_details   TEXT,
  url_attempted   TEXT,
  ua_used         TEXT,
  http_status     INTEGER,
  created_at      TIMESTAMPTZ DEFAULT NOW()
  -- No unique constraint: intentionally append-only log per run
);

CREATE TABLE IF NOT EXISTS scrape_runs (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  queries             TEXT[],
  lat                 NUMERIC(10,7),
  lng                 NUMERIC(10,7),
  zoom                INTEGER,
  country_code        TEXT,
  language            TEXT,
  results_per_query   INTEGER,
  leads_found         INTEGER,
  leads_new           INTEGER,
  leads_updated       INTEGER,
  status              TEXT DEFAULT 'running',  -- 'running', 'success', 'error'
  started_at          TIMESTAMPTZ DEFAULT NOW(),
  completed_at        TIMESTAMPTZ,
  error_message       TEXT
);

CREATE TABLE IF NOT EXISTS enrichment_runs (
  id                      UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  leads_processed         INTEGER,
  emails_found            INTEGER,
  hard_blocked            INTEGER,
  sitemap_fallback_used   INTEGER,
  sitemap_helped          INTEGER,
  status                  TEXT DEFAULT 'running',
  started_at              TIMESTAMPTZ DEFAULT NOW(),
  completed_at            TIMESTAMPTZ,
  error_message           TEXT
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_leads_city             ON leads(city);
CREATE INDEX IF NOT EXISTS idx_leads_state            ON leads(state);
CREATE INDEX IF NOT EXISTS idx_leads_source_country   ON leads(source_country_code);
CREATE INDEX IF NOT EXISTS idx_leads_scraped_at       ON leads(scraped_at DESC);
CREATE INDEX IF NOT EXISTS idx_enrichment_place_id    ON lead_enrichment(place_id);
CREATE INDEX IF NOT EXISTS idx_enrichment_email       ON lead_enrichment(email);
CREATE INDEX IF NOT EXISTS idx_errors_place_id        ON lead_errors(place_id);
CREATE INDEX IF NOT EXISTS idx_errors_run_id          ON lead_errors(run_id);
CREATE INDEX IF NOT EXISTS idx_errors_error_type      ON lead_errors(error_type);
CREATE INDEX IF NOT EXISTS idx_scrape_runs_status     ON scrape_runs(status);
CREATE INDEX IF NOT EXISTS idx_enrichment_runs_status ON enrichment_runs(status);

-- ============================================================
-- AUTO-UPDATE TRIGGERS (updated_at)
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_leads_updated_at ON leads;
CREATE TRIGGER update_leads_updated_at
  BEFORE UPDATE ON leads
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_enrichment_updated_at ON lead_enrichment;
CREATE TRIGGER update_enrichment_updated_at
  BEFORE UPDATE ON lead_enrichment
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- SENDER PROFILES — outreach sender identities / pitch library
-- ============================================================

CREATE TABLE IF NOT EXISTS sender_profiles (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_name        TEXT NOT NULL,           -- "My agency pitch", "My SaaS pitch"
  owner_name          TEXT NOT NULL,           -- sender's actual name
  company_name        TEXT NOT NULL,
  service_description TEXT NOT NULL,           -- what you do / offer
  value_proposition   TEXT,                    -- what makes you different
  target_industry     TEXT,                    -- e.g. "property management", "dental"
  is_default          BOOLEAN DEFAULT FALSE,   -- the global fallback profile
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lead_outreach (
  id                       UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  place_id                 TEXT REFERENCES leads(place_id) ON DELETE CASCADE,
  profile_id               UUID REFERENCES sender_profiles(id) ON DELETE SET NULL,
  channel                  TEXT NOT NULL CHECK (channel IN ('email', 'linkedin', 'whatsapp')),
  tone                     TEXT NOT NULL DEFAULT 'professional' CHECK (tone IN ('professional', 'conversational', 'direct')),
  subject_line             TEXT,
  message_body             TEXT NOT NULL,
  linkedin_connection_note TEXT,
  whatsapp_link            TEXT,
  personalization_score    INTEGER CHECK (personalization_score BETWEEN 1 AND 5),
  personalization_notes    TEXT,
  status                   TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'replied')),
  sent_at                  TIMESTAMPTZ,
  model_used               TEXT,               -- 'groq-llama3.3-70b', 'gemini-2.0-flash', 'failed'
  generated_at             TIMESTAMPTZ DEFAULT NOW(),
  created_at               TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT lead_outreach_unique UNIQUE (place_id, profile_id, channel)
);

CREATE INDEX IF NOT EXISTS idx_sender_profiles_default  ON sender_profiles(is_default);
CREATE INDEX IF NOT EXISTS idx_lead_outreach_place_id   ON lead_outreach(place_id);
CREATE INDEX IF NOT EXISTS idx_lead_outreach_profile_id ON lead_outreach(profile_id);
CREATE INDEX IF NOT EXISTS idx_lead_outreach_status     ON lead_outreach(status);
CREATE INDEX IF NOT EXISTS idx_lead_outreach_channel    ON lead_outreach(channel);

DROP TRIGGER IF EXISTS update_sender_profiles_updated_at ON sender_profiles;
CREATE TRIGGER update_sender_profiles_updated_at
  BEFORE UPDATE ON sender_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-set sent_at when outreach status changes to 'sent' (T4.4)
CREATE OR REPLACE FUNCTION set_outreach_sent_at()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'sent' AND (OLD.status IS DISTINCT FROM 'sent') THEN
    NEW.sent_at = NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_outreach_sent_at ON lead_outreach;
CREATE TRIGGER trg_outreach_sent_at
  BEFORE UPDATE ON lead_outreach
  FOR EACH ROW EXECUTE FUNCTION set_outreach_sent_at();

-- ============================================================
-- LEAD QUALITY SCORING FUNCTION
-- Scores each enriched lead 0-100 across four blocks:
--   A) Contact reachability  (max 48)
--   B) Data depth            (max 22)
--   C) Business legitimacy   (max 25)
--   D) LLM personalization   (max 10, bonus)
-- Penalties: hard-blocked (-10), no website (cap at 25)
-- ============================================================

CREATE OR REPLACE FUNCTION compute_lead_quality_score(
  p_website             TEXT,
  p_google_rating       NUMERIC,
  p_review_count        INTEGER,
  p_maps_description    TEXT,
  p_opening_hours       TEXT,
  p_email               TEXT,
  p_email_valid         TEXT,
  p_website_phone       TEXT,
  p_owner_name          TEXT,
  p_company_description TEXT,
  p_crawl_status        TEXT,
  p_pages_crawled       INTEGER,
  p_sitemap_used        BOOLEAN,
  p_linkedin_profiles   TEXT,
  p_best_personalization_score INTEGER
) RETURNS INTEGER AS $$
DECLARE
  score          INTEGER := 0;
  email_domain   TEXT;
  website_domain TEXT;
  is_free_email  BOOLEAN := FALSE;
BEGIN
  -- BLOCK A: CONTACT REACHABILITY (max 48)
  IF p_email_valid = 'valid' THEN score := score + 25;
  ELSIF p_email IS NOT NULL AND p_email != '' THEN score := score + 12;
  END IF;

  IF p_email IS NOT NULL AND p_email != '' THEN
    email_domain := LOWER(SPLIT_PART(p_email, '@', 2));
    is_free_email := email_domain = ANY(ARRAY[
      'gmail.com','yahoo.com','hotmail.com','outlook.com','icloud.com',
      'aol.com','yahoo.co.in','rediffmail.com','live.com','msn.com'
    ]);
    IF NOT is_free_email THEN
      IF p_website IS NOT NULL AND p_website != '' THEN
        website_domain := LOWER(REGEXP_REPLACE(p_website,'^https?://(www\.)?([^/?#]+).*$','\2'));
        IF email_domain = website_domain THEN score := score + 8;
        ELSE score := score + 4; END IF;
      ELSE score := score + 4; END IF;
    END IF;
  END IF;

  IF p_owner_name IS NOT NULL AND p_owner_name != ''         THEN score := score + 7; END IF;
  IF p_website_phone IS NOT NULL AND p_website_phone != ''   THEN score := score + 5; END IF;
  IF p_linkedin_profiles IS NOT NULL AND p_linkedin_profiles != '' THEN score := score + 3; END IF;

  -- BLOCK B: DATA DEPTH (max 22)
  IF    p_pages_crawled >= 3 THEN score := score + 12;
  ELSIF p_pages_crawled >= 1 THEN score := score + 7; END IF;

  IF p_company_description IS NOT NULL THEN
    IF    LENGTH(p_company_description) > 100 THEN score := score + 8;
    ELSIF LENGTH(p_company_description) > 20  THEN score := score + 4; END IF;
  END IF;

  IF p_sitemap_used = TRUE THEN score := score + 2; END IF;

  -- BLOCK C: BUSINESS LEGITIMACY (max 25)
  IF    p_google_rating >= 4.5 THEN score := score + 10;
  ELSIF p_google_rating >= 4.0 THEN score := score + 7;
  ELSIF p_google_rating >= 3.5 THEN score := score + 4;
  ELSIF p_google_rating >= 3.0 THEN score := score + 2; END IF;

  IF    p_review_count IS NULL OR p_review_count = 0 THEN score := score - 5;
  ELSIF p_review_count < 5  THEN score := score - 3;
  ELSIF p_review_count < 10 THEN score := score + 1;
  ELSIF p_review_count < 20 THEN score := score + 3;
  ELSIF p_review_count < 50 THEN score := score + 5;
  ELSE                           score := score + 8; END IF;

  IF p_maps_description IS NOT NULL AND p_maps_description != '' THEN score := score + 4; END IF;
  IF p_opening_hours IS NOT NULL AND p_opening_hours != ''       THEN score := score + 3; END IF;

  -- BLOCK D: LLM PERSONALIZATION BONUS (max 10)
  IF    p_best_personalization_score >= 5 THEN score := score + 10;
  ELSIF p_best_personalization_score >= 4 THEN score := score + 7;
  ELSIF p_best_personalization_score >= 3 THEN score := score + 4; END IF;

  -- PENALTIES
  IF p_crawl_status LIKE 'blocked%' THEN score := score - 10; END IF;

  -- Hard gate: no website caps score at 25
  IF p_website IS NULL OR p_website = '' THEN
    RETURN GREATEST(0, LEAST(25, score));
  END IF;

  RETURN GREATEST(0, LEAST(100, score));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================
-- VIEW
-- ============================================================

DROP VIEW IF EXISTS leads_full;
CREATE VIEW leads_full AS
SELECT
  l.*,
  e.email,
  e.all_emails_found,
  e.website_phone,
  e.all_phones_found,
  e.owner_name,
  e.linkedin_profiles,
  e.linkedin,
  e.facebook,
  e.instagram,
  e.twitter,
  e.youtube,
  e.tiktok,
  e.company_description,
  e.email_valid,
  e.crawl_status,
  e.sitemap_used,
  e.pages_crawled,
  e.enriched_at,
  lo.best_personalization_score,
  compute_lead_quality_score(
    l.website, l.google_rating, l.review_count, l.maps_description,
    l.opening_hours, e.email, e.email_valid, e.website_phone,
    e.owner_name, e.company_description, e.crawl_status,
    e.pages_crawled, e.sitemap_used, e.linkedin_profiles,
    lo.best_personalization_score
  ) AS lead_quality_score
FROM leads l
LEFT JOIN lead_enrichment e ON l.place_id = e.place_id
LEFT JOIN (
  SELECT place_id, MAX(personalization_score) AS best_personalization_score
  FROM lead_outreach
  WHERE model_used IS NOT NULL AND model_used != 'failed'
  GROUP BY place_id
) lo ON l.place_id = lo.place_id;
