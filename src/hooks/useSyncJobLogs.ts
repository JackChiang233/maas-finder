import { useQuery } from "@tanstack/react-query";
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

export function useSyncJobLogs(jobId: string | null, resultFilter: RepoLogResult = "all") {
  return useQuery({
    queryKey: ["sync-repo-logs", jobId, resultFilter],
    queryFn: async () => {
      if (!jobId) return [];
      let q = supabase
        .from("sync_repo_logs")
        .select("*")
        .eq("sync_job_id", jobId)
        .order("created_at", { ascending: true })
        .limit(500);
      if (resultFilter !== "all") {
        q = q.eq("result", resultFilter);
      }
      const { data, error } = await q;
      if (error) throw error;
      return data as SyncRepoLog[];
    },
    enabled: !!jobId,
    staleTime: 30_000,
  });
}
