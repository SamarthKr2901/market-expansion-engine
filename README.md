# Market Expansion Engine (MEE)

Automated B2B lead generation pipeline. Takes a location and business type as input, scrapes Google Maps for matching businesses, crawls each company website for contact data, and stores everything in a structured Supabase database ready for outreach.

Built on n8n (self-hosted), SerpAPI, and Supabase. Near-zero running cost using free API tiers.

> **Status: Work In Progress**

---

## What It Does

**1. Scrape** — Query Google Maps via SerpAPI for any industry and location. Returns up to 20 businesses per query with name, address, phone, rating, hours, and coordinates.

**2. Enrich** — For each lead with a website, crawl up to 3 pages (homepage, /contact, /about) with Chrome then Firefox UA fallback. Extract:
- Email addresses (mailto links, regex, JSON-LD structured data)
- Phone numbers (tel: links, formatted patterns)
- 6 social platforms: LinkedIn company page, Facebook, Instagram, Twitter, YouTube, TikTok
- Individual LinkedIn profiles linked from About/team pages
- Company description (OpenGraph, meta tags, JSON-LD)
- Owner/founder name (JSON-LD Person schema, text patterns)
- Email validity via DNS MX record lookup

**3. Store** — Upsert to Supabase PostgreSQL by Google Place ID. Full error logging and run audit trail.

---

## Stack

| Layer | Tool |
|---|---|
| Workflow orchestration | n8n (self-hosted) |
| Google Maps data | SerpAPI (100 free searches/month) |
| Database | Supabase (PostgreSQL + REST API) |
| Web crawling | Custom HTTP + regex + JSON-LD + OpenGraph |
| Email validation | DNS MX record lookup via dns.google |

---

## Progress

### Done

- [x] Google Maps scraping via SerpAPI (any location, any industry, any country)
- [x] Website crawling with Chrome/Firefox UA fallback per page
- [x] Sitemap.xml fallback when /contact and /about both fail
- [x] Email extraction: mailto links, regex, JSON-LD structured data
- [x] Phone extraction: tel: links + formatted patterns with strict validation
- [x] 6 social platform extraction with false-positive blacklists
- [x] Individual LinkedIn profile extraction from About/team pages
- [x] Company description extraction (OpenGraph, meta, JSON-LD)
- [x] Owner name extraction from JSON-LD Person schema and text patterns
- [x] Location-aware email scoring (prefers city-relevant email over generic)
- [x] DNS MX validation for extracted emails
- [x] Multi-query support with Place ID deduplication
- [x] Webhook-based API (parameterized for any location and industry)
- [x] Supabase schema: leads, lead_enrichment, lead_errors, scrape_runs, enrichment_runs
- [x] Error logging per lead (HARD_BLOCKED, NO_EMAIL_FOUND)
- [x] Run audit trail for every scrape and enrichment execution
- [x] Combined pipeline endpoint (scrape + enrich in one webhook call)
- [x] Tested across two countries: Dallas TX (US) and Lucknow, India
- [x] LLM outreach generation: Groq (Llama 3.3-70b) generates cold email, LinkedIn message, WhatsApp message per lead
- [x] Sender profile library: multiple named profiles ("My agency pitch", "My SaaS pitch") with per-run channel + tone selection
- [x] Personalization score (1-5) and notes per generated message
- [x] WhatsApp wa.me deep links auto-generated from lead phone numbers
- [x] Outreach stored in Supabase lead_outreach table, upsert by (lead, profile, channel)
- [x] LinkedIn (36/37) and WhatsApp (35/37) drafts generated — wa.me deep links auto-built from lead phone numbers
- [x] Gmail send path added as dormant nodes (disabled by default, activate when Google OAuth2 is configured)

### To Do

- [x] Caching layer: skip re-enriching leads enriched within last 30 days (reads from leads_full, filters enriched_at)
- [x] Lead quality score (0-100): computed column in leads_full view via Postgres function across 4 blocks — contact reachability (max 48), data depth (max 22), business legitimacy (max 25), LLM personalization bonus (max 10)
- [ ] Gemini Flash fallback for Groq outreach generation failures
- [x] Gmail send node: added as dormant nodes (Split Email Items + Gmail Send) — enable after adding Google OAuth2 credential
- [x] Outreach status tracking: `sent_at` auto-set via trigger when status changes to 'sent'. UI marks draft→sent→replied
- [x] Multi-query runs: `/mee-enrich` and `/mee-run` accept `place_ids[]` to bypass 30-day cache and target specific leads
- [x] Vertical-specific prompt tuning: 13 industry pain-point maps injected into LLM prompt when `target_industry` matches (property management, dental, restaurant, legal, and 9 more)
- [x] Re-enrich specific leads: pass `place_ids[]` to `/mee-enrich` to force-re-crawl specific leads regardless of cache
- [ ] Decision maker extraction improvement: owner name + title from team pages
- [ ] Hunter.io fallback: 25 free domain email searches/month for leads with no email found
- [ ] Apollo.io fallback: 50 free credits/month, returns name + title + email together
- [ ] Frontend dashboard: Next.js over Supabase to run searches, view leads, trigger outreach
- [ ] Geographic grid scanning: tile a search area for more than 20 results per run
- [ ] LLM query expansion: auto-generate industry query variations per search

---

## Workflows

| File | n8n Workflow | Description |
|---|---|---|
| `workflows/01_mee-scraper.json` | MEE — Google Maps Scraper | Accepts webhook POST, queries SerpAPI, writes leads to Supabase |
| `workflows/02_mee-enrichment.json` | MEE — Website Enrichment | Reads all leads from Supabase, crawls websites, writes contact data |
| `workflows/03_mee-combined.json` | MEE — Combined Run | Calls scraper then enrichment in sequence, returns unified response |
| `workflows/04_mee-outreach.json` | MEE — LLM Outreach Generator | Reads enriched leads, calls Groq (Llama 3.3-70b), generates cold email / LinkedIn / WhatsApp messages, stores in Supabase |

---

## Setup

### Prerequisites

- n8n instance (self-hosted or cloud)
- SerpAPI account — [serpapi.com](https://serpapi.com) (free tier: 100 searches/month)
- Supabase project — [supabase.com](https://supabase.com) (free tier available)

### 1. Database

Run `database/schema.sql` in your Supabase SQL editor to create all tables, indexes, triggers, and the `leads_full` view.

### 2. Replace Placeholders

Before importing workflows into n8n, replace these strings in the JSON files:

| Placeholder | Replace with |
|---|---|
| `YOUR_SERPAPI_KEY` | Your SerpAPI API key |
| `YOUR_SUPABASE_PROJECT_REF` | Your Supabase project reference ID |
| `YOUR_SUPABASE_PUBLISHABLE_KEY` | Your Supabase anon/publishable key |
| `YOUR_N8N_INSTANCE_URL` | Your n8n instance hostname |
| `YOUR_GROQ_API_KEY` | Your Groq API key (free at console.groq.com) — only needed for workflow 04 |

### 3. Import Workflows

In n8n: Settings > Import workflow. Import in order: scraper, enrichment, combined. Activate all three.

---

## Usage

### Full pipeline (scrape + enrich)

```bash
curl -X POST "https://YOUR_N8N_INSTANCE_URL/webhook/mee-run" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "property management companies",
    "lat": 32.7767,
    "lng": -96.797,
    "zoom": 12,
    "countryCode": "us"
  }'
```

### Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `query` | Yes | | Business type to search for |
| `lat` | Yes | | Latitude of target area |
| `lng` | Yes | | Longitude of target area |
| `zoom` | No | 12 | Search radius (11=wider, 14=tighter) |
| `countryCode` | No | `us` | Two-letter country code |
| `language` | No | `en` | Language code |
| `resultsPerQuery` | No | 20 | Max results (capped at 20) |

### Endpoints

| Endpoint | Use |
|---|---|
| `POST /webhook/mee-run` | Full pipeline: scrape + enrich |
| `POST /webhook/mee-scrape` | Scrape only |
| `POST /webhook/mee-enrich` | Enrich existing leads only, body can be `{}` |
| `POST /webhook/mee-outreach` | Generate LLM outreach messages for enriched leads |

### Outreach (generate messages)

First create a sender profile in Supabase:

```sql
INSERT INTO sender_profiles (profile_name, owner_name, company_name, service_description, value_proposition, target_industry)
VALUES ('My agency pitch', 'Your Name', 'Your Company', 'We build marketing automation systems for local service businesses', 'Done-for-you setup, no monthly retainer', 'property management');
```

Then call the outreach endpoint with the returned profile UUID:

```bash
curl -X POST "http://localhost:5678/webhook/mee-outreach" \
  -H "Content-Type: application/json" \
  -d '{
    "profile_id": "uuid-from-sender-profiles-table",
    "channel": "email",
    "tone": "professional",
    "place_ids": []
  }'
```

Leave `place_ids` empty to generate for all enriched leads (up to 50), or pass specific IDs to target a subset.

### Outreach parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `profile_id` | Yes | | UUID from sender_profiles table |
| `channel` | No | `email` | `email`, `linkedin`, or `whatsapp` |
| `tone` | No | `professional` | `professional`, `conversational`, or `direct` |
| `place_ids` | No | `[]` | Array of place IDs. Empty = all enriched leads |

---

## Database Schema

Five tables and one view in Supabase:

| Table | Purpose |
|---|---|
| `leads` | Core business data from Google Maps, keyed by Place ID |
| `lead_enrichment` | Website crawl results, one row per lead |
| `lead_errors` | Append-only error log per run (HARD_BLOCKED, NO_EMAIL_FOUND) |
| `scrape_runs` | Audit log for every scrape execution |
| `enrichment_runs` | Audit log for every enrichment execution |
| `sender_profiles` | Named outreach sender identities ("My agency pitch", "My SaaS pitch") |
| `lead_outreach` | Generated messages per lead, upsert by (lead, profile, channel) |
| `leads_full` (view) | Joined view: leads + enrichment + best personalization score + computed `lead_quality_score` (0-100) |

Leads and enrichment upsert by `place_id` (no duplicates across runs). Error and run tables are append-only. Outreach upserts by `(place_id, profile_id, channel)` — re-running regenerates and overwrites the draft.

### Lead Quality Score

`lead_quality_score` (0-100) is a computed column in `leads_full`, calculated by `compute_lead_quality_score()`:

| Block | Max | Key signals |
|---|---|---|
| Contact reachability | 48 | Valid email (+25), domain match (+8), owner name (+7), phone (+5), LinkedIn profiles (+3) |
| Data depth | 22 | Pages crawled (+12/7), company description (+8/4), sitemap used (+2) |
| Business legitimacy | 25 | Google rating (+10 to +2), review count (+8 to -5), has description/hours |
| LLM personalization | 10 | Best personalization_score across channels (5→+10, 4→+7, 3→+4) |
| Penalties | — | Hard blocked (-10), no website (cap at 25) |

**Tiers:** 🟢 75-100 Ready · 🟡 50-74 Review · 🟠 25-49 Low · 🔴 0-24 Skip

---

## Results on Test Data

| Location | Leads | With Email | With Phone | Blocked |
|---|---|---|---|---|
| Dallas, TX (US) | 20 | 10 | 17 | 3 |
| Lucknow, India | 20 | 10 | 3 | 1 |

Enrichment runs in under 90 seconds for 20 leads. Total infrastructure cost: free tier on all services.
