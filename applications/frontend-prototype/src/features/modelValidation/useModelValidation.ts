"use client";

import { useCallback, useEffect, useState } from "react";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import type { ModelValidationListResponse, ModelValidationListParams, ModelValidationDetail, ModelStatus } from "@/types/api";
import { ApiError } from "@/types/errors";

interface UseModelValidationReturn {
  data: ModelValidationListResponse | null;
  selectedModel: ModelValidationDetail | null;
  comparisonModel: ModelValidationDetail | null;
  loading: boolean;
  detailLoading: boolean;
  error: ApiError | null;
  statusFilter: ModelStatus | undefined;
  setStatusFilter: (status: ModelStatus | undefined) => void;
  refetch: () => Promise<void>;
  fetchModelDetail: (modelVersion: string) => Promise<void>;
  fetchComparisonModel: (modelVersion: string) => Promise<void>;
  clearComparison: () => void;
}

export function useModelValidation(): UseModelValidationReturn {
  const [data, setData] = useState<ModelValidationListResponse | null>(null);
  const [selectedModel, setSelectedModel] = useState<ModelValidationDetail | null>(null);
  const [comparisonModel, setComparisonModel] = useState<ModelValidationDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [detailLoading, setDetailLoading] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [statusFilter, setStatusFilter] = useState<ModelStatus | undefined>(undefined);

  const fetchModels = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const params: ModelValidationListParams = {};
      if (statusFilter) params.status = statusFilter;
      const response = await apiClient<ModelValidationListResponse>(API_ROUTES.MODELS_VALIDATION, {
        screenId: SCREEN_IDS.MODEL_VALIDATION,
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
  }, [statusFilter]);

  const fetchModelDetail = useCallback(async (modelVersion: string) => {
    setDetailLoading(true);
    try {
      const detail = await apiClient<ModelValidationDetail>(
        API_ROUTES.MODEL_VALIDATION_DETAIL(modelVersion),
        { screenId: SCREEN_IDS.MODEL_VALIDATION }
      );
      setSelectedModel(detail);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        setError(thrown);
      }
    } finally {
      setDetailLoading(false);
    }
  }, []);

  const fetchComparisonModel = useCallback(async (modelVersion: string) => {
    try {
      const detail = await apiClient<ModelValidationDetail>(
        API_ROUTES.MODEL_VALIDATION_DETAIL(modelVersion),
        { screenId: SCREEN_IDS.MODEL_VALIDATION }
      );
      setComparisonModel(detail);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        setError(thrown);
      }
    }
  }, []);

  const clearComparison = useCallback(() => {
    setComparisonModel(null);
  }, []);

  useEffect(() => {
    fetchModels();
  }, [fetchModels]);

  return {
    data,
    selectedModel,
    comparisonModel,
    loading,
    detailLoading,
    error,
    statusFilter,
    setStatusFilter,
    refetch: fetchModels,
    fetchModelDetail,
    fetchComparisonModel,
    clearComparison,
  };
}
