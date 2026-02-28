"use client";

import { useCallback, useEffect, useState } from "react";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import type { DashboardSummary } from "@/types/api";
import { ApiError } from "@/types/errors";
import { useAuth } from "@/hooks/useAuth";

interface UseDashboardSummaryReturn {
  data: DashboardSummary | null;
  loading: boolean;
  error: ApiError | null;
  refetch: () => Promise<void>;
}

export function useDashboardSummary(): UseDashboardSummaryReturn {
  const [data, setData] = useState<DashboardSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<ApiError | null>(null);
  const { setKillSwitchEnabled } = useAuth();

  const fetchSummary = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const summary = await apiClient<DashboardSummary>(API_ROUTES.DASHBOARD_SUMMARY, {
        screenId: SCREEN_IDS.DASHBOARD,
      });
      setData(summary);
      setKillSwitchEnabled(summary.killSwitchEnabled);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        setError(thrown);
      }
    } finally {
      setLoading(false);
    }
  }, [setKillSwitchEnabled]);

  useEffect(() => {
    fetchSummary();
  }, [fetchSummary]);

  return { data, loading, error, refetch: fetchSummary };
}
