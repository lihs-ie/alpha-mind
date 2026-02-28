"use client";

import { useCallback, useEffect, useState } from "react";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import type { OrderListResponse, OrderListParams, OrderDetail } from "@/types/api";
import { ApiError } from "@/types/errors";

interface UseOrdersReturn {
  data: OrderListResponse | null;
  selectedOrder: OrderDetail | null;
  loading: boolean;
  detailLoading: boolean;
  error: ApiError | null;
  params: OrderListParams;
  setParams: (params: OrderListParams) => void;
  refetch: () => Promise<void>;
  fetchOrderDetail: (orderId: string) => Promise<void>;
  loadMore: () => Promise<void>;
}

export function useOrders(): UseOrdersReturn {
  const [data, setData] = useState<OrderListResponse | null>(null);
  const [selectedOrder, setSelectedOrder] = useState<OrderDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [detailLoading, setDetailLoading] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [params, setParams] = useState<OrderListParams>({});

  const fetchOrders = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await apiClient<OrderListResponse>(API_ROUTES.ORDERS, {
        screenId: SCREEN_IDS.ORDERS,
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

  const fetchOrderDetail = useCallback(async (orderId: string) => {
    setDetailLoading(true);
    try {
      const detail = await apiClient<OrderDetail>(API_ROUTES.ORDER_DETAIL(orderId), {
        screenId: SCREEN_IDS.ORDERS,
      });
      setSelectedOrder(detail);
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
      const response = await apiClient<OrderListResponse>(API_ROUTES.ORDERS, {
        screenId: SCREEN_IDS.ORDERS,
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
    fetchOrders();
  }, [fetchOrders]);

  return {
    data,
    selectedOrder,
    loading,
    detailLoading,
    error,
    params,
    setParams,
    refetch: fetchOrders,
    fetchOrderDetail,
    loadMore,
  };
}
