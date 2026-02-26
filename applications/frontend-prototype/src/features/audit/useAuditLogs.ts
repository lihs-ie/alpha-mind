"use client";

import { useCallback, useEffect, useState } from "react";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import type { AuditListResponse, AuditListParams, AuditDetail } from "@/types/api";
import { ApiError } from "@/types/errors";

interface UseAuditLogsReturn {
  data: AuditListResponse | null;
  selectedLog: AuditDetail | null;
  loading: boolean;
  detailLoading: boolean;
  error: ApiError | null;
  params: AuditListParams;
  setParams: (params: AuditListParams) => void;
  refetch: () => Promise<void>;
  fetchLogDetail: (logId: string) => Promise<void>;
  loadMore: () => Promise<void>;
}

export function useAuditLogs(): UseAuditLogsReturn {
  const [data, setData] = useState<AuditListResponse | null>(null);
  const [selectedLog, setSelectedLog] = useState<AuditDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [detailLoading, setDetailLoading] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [params, setParams] = useState<AuditListParams>({});

  const fetchLogs = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await apiClient<AuditListResponse>(API_ROUTES.AUDIT, {
        screenId: SCREEN_IDS.AUDIT,
        params: params as Record<string, string | number | undefined>,
      });
      setData(response);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        setError(thrown);
      }
    } finally {
      setLoading(false);
    }
  }, [params]);

  const fetchLogDetail = useCallback(async (logId: string) => {
    setDetailLoading(true);
    try {
      const detail = await apiClient<AuditDetail>(API_ROUTES.AUDIT_DETAIL(logId), {
        screenId: SCREEN_IDS.AUDIT,
      });
      setSelectedLog(detail);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        setError(thrown);
      }
    } finally {
      setDetailLoading(false);
    }
  }, []);

  const loadMore = useCallback(async () => {
    if (!data?.nextCursor) return;
    try {
      const response = await apiClient<AuditListResponse>(API_ROUTES.AUDIT, {
        screenId: SCREEN_IDS.AUDIT,
        params: { ...params, cursor: data.nextCursor } as Record<string, string | number | undefined>,
      });
      setData((previous) => ({
        items: [...(previous?.items ?? []), ...response.items],
        nextCursor: response.nextCursor,
      }));
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        setError(thrown);
      }
    }
  }, [data?.nextCursor, params]);

  useEffect(() => {
    fetchLogs();
  }, [fetchLogs]);

  return {
    data,
    selectedLog,
    loading,
    detailLoading,
    error,
    params,
    setParams,
    refetch: fetchLogs,
    fetchLogDetail,
    loadMore,
  };
}
