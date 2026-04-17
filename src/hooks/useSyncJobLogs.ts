import { useState, useCallback, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";

export interface SyncRepoLog {
  id: string;
  sync_job_id: string;
  repo_full_name: string;
  github_id: number | null;
  stars: number;
  language: string | null;
  search_query: string | null;
  result: string;
  reject_reason: string | null;
  matched_terms: string[];
  distinct_brands: string[];
  hit_count: number;
  created_at: string;
}

export type RepoLogResult = "all" | "accepted" | "rejected" | "skipped_existing" | "skipped_qiniu" | "skipped_archived" | "error";

const PAGE_SIZE = 200;

export function useSyncJobLogs(jobId: string | null, resultFilter: RepoLogResult = "all") {
  const [logs, setLogs] = useState<SyncRepoLog[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isFetchingMore, setIsFetchingMore] = useState(false);
  const [hasMore, setHasMore] = useState(false);
  const [page, setPage] = useState(0);

  const fetchPage = useCallback(async (pageIndex: number, filter: RepoLogResult, append: boolean) => {
    if (!jobId) return;
    const start = pageIndex * PAGE_SIZE;
    const end = start + PAGE_SIZE - 1;

    let q = supabase
      .from("sync_repo_logs")
      .select("*")
      .eq("sync_job_id", jobId)
      .order("created_at", { ascending: true })
      .range(start, end);

    if (filter !== "all") {
      q = q.eq("result", filter);
    }

    const { data, error } = await q;
    if (error) throw error;

    const rows = (data ?? []) as SyncRepoLog[];
    if (append) {
      setLogs((prev) => [...prev, ...rows]);
    } else {
      setLogs(rows);
    }
    setHasMore(rows.length === PAGE_SIZE);
    setPage(pageIndex);
  }, [jobId]);

  useEffect(() => {
    if (!jobId) return;
    setIsLoading(true);
    setLogs([]);
    setPage(0);
    setHasMore(false);
    fetchPage(0, resultFilter, false).finally(() => setIsLoading(false));
  }, [jobId, resultFilter, fetchPage]);

  const fetchNextPage = useCallback(async () => {
    setIsFetchingMore(true);
    try {
      await fetchPage(page + 1, resultFilter, true);
    } finally {
      setIsFetchingMore(false);
    }
  }, [fetchPage, page, resultFilter]);

  return { data: logs, isLoading, isFetchingMore, hasMore, fetchNextPage };
}
