# Setup Guide

## 1. Supabase

1. Create a new project at [supabase.com](https://supabase.com)
2. Go to SQL Editor and run `database/schema.sql`
3. Note your project ref (in the project URL) and anon/publishable key (Settings > API)

## 2. SerpAPI

1. Sign up at [serpapi.com](https://serpapi.com) — free tier gives 100 searches/month
2. Copy your API key from the dashboard

## 2b. Groq (for outreach workflow only)

1. Sign up at [console.groq.com](https://console.groq.com) — free tier, no card required
2. Create an API key under API Keys
3. Free limits: 14,400 requests/day, 500,000 tokens/day — more than enough for 50 leads/run

## 3. n8n

1. Install n8n: `npm install -g n8n` or use the Docker image
2. Start it: `n8n start` (or `docker run -p 5678:5678 n8nio/n8n`)

## 4. Import Workflows

1. Open each workflow JSON in a text editor
2. Replace all placeholder strings (see README)
3. In n8n: Settings > Import workflow, import in order:
   - `01_mee-scraper.json`
   - `02_mee-enrichment.json`
   - `03_mee-combined.json`
   - `04_mee-outreach.json`
4. Activate all four workflows

## 5. Create Your First Sender Profile

Run this in your Supabase SQL editor (adjust to your actual details):

```sql
INSERT INTO sender_profiles (profile_name, owner_name, company_name, service_description, value_proposition, target_industry)
VALUES (
  'My default pitch',
  'Your Name',
  'Your Company Name',
  'One sentence: what you do and who you help',
  'One sentence: why choose you over alternatives',
  'property management'  -- or whatever industry you are targeting
);
```

Note the UUID it returns — you will pass it as `profile_id` when calling `/webhook/mee-outreach`.

## 5. Test Run

```bash
curl -X POST "http://localhost:5678/webhook/mee-run" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "dentists",
    "lat": 40.7128,
    "lng": -74.006,
    "zoom": 12,
    "countryCode": "us"
  }'
```

Check your Supabase `leads` and `lead_enrichment` tables for results.

## Finding Coordinates

Right-click any location in Google Maps and click the coordinates shown at the top of the context menu. Use zoom 12 for a roughly 10-mile radius, 11 for wider, 14 for tighter.

## SerpAPI Quota

Each call to `/mee-scrape` or `/mee-run` uses 1 SerpAPI credit per query.
Free tier: 100 credits/month. Paid tier starts at $50/month for 5,000 credits.
