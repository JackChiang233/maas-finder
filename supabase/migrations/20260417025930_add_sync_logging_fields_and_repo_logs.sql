/*
  # Add sync logging: search conditions on sync_jobs, and sync_repo_logs table

  ## Summary
  Two changes to provide full traceability of GitHub sync executions:
  1. Add search-condition columns to `sync_jobs` so each job records exactly what
     queries and filter parameters were used when it ran.
  2. Create `sync_repo_logs` to record per-repository processing results for every
     sync execution (accepted, rejected, skipped, error).

  ## Modified Tables

  ### sync_jobs (new columns)
  - `search_queries` (jsonb) — array of GitHub search query strings used
  - `time_window_since` (date, nullable) — for incremental jobs: the earliest date
    of the `created:>` filter applied (null for init jobs)
  - `competitor_list` (jsonb) — snapshot of ALL_COMPETITORS array at run time
  - `min_competitor_hits` (int) — the threshold used (default 2)
  - `total_accepted` (int) — repos that passed competitor scan
  - `total_skipped_existing` (int) — repos already in github_projects
  - `total_skipped_qiniu` (int) — repos excluded because they already mention Qiniu
  - `total_rejected` (int) — repos rejected by competitor scan (below threshold)
  - `total_errors` (int) — repos that produced fetch errors

  ## New Tables

  ### sync_repo_logs
  - `id` (uuid, primary key)
  - `sync_job_id` (uuid, FK → sync_jobs.id)
  - `repo_full_name` (text) — e.g. "owner/repo"
  - `github_id` (bigint)
  - `stars` (int)
  - `language` (text, nullable)
  - `search_query` (text, nullable) — which search query surfaced this repo (init only)
  - `result` (text) — one of: accepted, rejected, skipped_existing, skipped_qiniu,
    skipped_archived, error
  - `reject_reason` (text, nullable) — e.g. "low_hits"
  - `matched_terms` (jsonb) — competitor terms found
  - `distinct_brands` (jsonb) — de-aliased brand list
  - `hit_count` (int)
  - `created_at` (timestamptz)

  ## Security
  - RLS enabled on sync_repo_logs
  - Authenticated users can read all repo logs (for admin review)
  - Only service role can insert/update (managed by Edge Functions)

  ## Notes
  1. New sync_jobs columns default to empty arrays / 0 so existing rows are unaffected.
  2. sync_repo_logs has an index on sync_job_id for fast per-job lookups.
  3. An index on result allows efficient filtering by outcome.
*/

-- ── sync_jobs: add search-condition columns ──────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'search_queries'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN search_queries jsonb NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'time_window_since'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN time_window_since date;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'competitor_list'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN competitor_list jsonb NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'min_competitor_hits'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN min_competitor_hits integer NOT NULL DEFAULT 2;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'total_accepted'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN total_accepted integer NOT NULL DEFAULT 0;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'total_skipped_existing'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN total_skipped_existing integer NOT NULL DEFAULT 0;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'total_skipped_qiniu'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN total_skipped_qiniu integer NOT NULL DEFAULT 0;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'total_rejected'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN total_rejected integer NOT NULL DEFAULT 0;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sync_jobs' AND column_name = 'total_errors'
  ) THEN
    ALTER TABLE public.sync_jobs ADD COLUMN total_errors integer NOT NULL DEFAULT 0;
  END IF;
END $$;

-- ── sync_repo_logs ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.sync_repo_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sync_job_id uuid NOT NULL REFERENCES public.sync_jobs(id) ON DELETE CASCADE,
  repo_full_name text NOT NULL,
  github_id bigint,
  stars integer NOT NULL DEFAULT 0,
  language text,
  search_query text,
  result text NOT NULL,
  reject_reason text,
  matched_terms jsonb NOT NULL DEFAULT '[]'::jsonb,
  distinct_brands jsonb NOT NULL DEFAULT '[]'::jsonb,
  hit_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.sync_repo_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read sync repo logs"
  ON public.sync_repo_logs
  FOR SELECT
  TO authenticated
  USING (true);

CREATE INDEX IF NOT EXISTS idx_sync_repo_logs_job_id ON public.sync_repo_logs (sync_job_id);
CREATE INDEX IF NOT EXISTS idx_sync_repo_logs_result ON public.sync_repo_logs (result);
CREATE INDEX IF NOT EXISTS idx_sync_repo_logs_created_at ON public.sync_repo_logs (created_at DESC);
