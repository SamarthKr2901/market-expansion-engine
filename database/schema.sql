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
  e.enriched_at
FROM leads l
LEFT JOIN lead_enrichment e ON l.place_id = e.place_id;
