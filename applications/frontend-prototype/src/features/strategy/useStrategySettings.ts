"use client";

import { useCallback, useEffect, useState } from "react";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import type { StrategySettings } from "@/types/api";
import { ApiError } from "@/types/errors";

interface UseStrategySettingsReturn {
  data: StrategySettings | null;
  loading: boolean;
  error: ApiError | null;
  refetch: () => Promise<void>;
}

export function useStrategySettings(): UseStrategySettingsReturn {
  const [data, setData] = useState<StrategySettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<ApiError | null>(null);

  const fetchSettings = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const settings = await apiClient<StrategySettings>(API_ROUTES.SETTINGS_STRATEGY, {
        screenId: SCREEN_IDS.STRATEGY_SETTINGS,
      });
      setData(settings);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        setError(thrown);
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  return { data, loading, error, refetch: fetchSettings };
}
