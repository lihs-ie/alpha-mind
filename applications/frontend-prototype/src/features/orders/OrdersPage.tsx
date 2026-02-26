"use client";

import { useState } from "react";
import { useOrders } from "./useOrders";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/useToast";
import { useConfirmation } from "@/hooks/useConfirmation";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import { ACTION_IDS } from "@/constants/actionIds";
import { MESSAGES } from "@/constants/messages";
import { formatDatetime, formatInteger } from "@/lib/formatters";
import type { OrderSummary, OperationResult, CommandAccepted, OrderStatus } from "@/types/api";
import { ApiError } from "@/types/errors";
import { DataTable, type Column } from "@/components/data-display/DataTable";
import { DetailPanel } from "@/components/data-display/DetailPanel";
import { StatusBadge } from "@/components/data-display/StatusBadge";
import { SelectInput } from "@/components/form/SelectInput";
import { TextInput } from "@/components/form/TextInput";
import { DateRangePicker } from "@/components/form/DateRangePicker";
import { Button } from "@/components/actions/Button";
import { ConfirmationModal } from "@/components/feedback/ConfirmationModal";
import { EmptyState } from "@/components/feedback/EmptyState";
import { RetryBanner } from "@/components/feedback/RetryBanner";
import { TableSkeleton } from "@/components/skeleton/TableSkeleton";
import styles from "./OrdersPage.module.css";

const ORDER_STATUS_OPTIONS = [
  { value: "", label: "すべて" },
  { value: "PROPOSED", label: "提案中" },
  { value: "APPROVED", label: "承認済" },
  { value: "REJECTED", label: "却下" },
  { value: "EXECUTED", label: "約定済" },
  { value: "FAILED", label: "失敗" },
];

const ORDER_COLUMNS: Column<OrderSummary>[] = [
  { key: "symbol", header: "銘柄", render: (item) => item.symbol, mono: true },
  { key: "side", header: "売買", render: (item) => item.side },
  { key: "qty", header: "数量", render: (item) => formatInteger(item.qty), mono: true },
  { key: "status", header: "状態", render: (item) => <StatusBadge status={item.status} /> },
  { key: "createdAt", header: "作成日時", render: (item) => formatDatetime(item.createdAt) },
];

export function OrdersPage() {
  const {
    data, selectedOrder, loading, detailLoading,
    error, params, setParams, refetch, fetchOrderDetail, loadMore,
  } = useOrders();
  const { killSwitchEnabled } = useAuth();
  const { showToast } = useToast();
  const { isOpen, config, confirm, handleConfirm, handleCancel } = useConfirmation();

  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [symbolFilter, setSymbolFilter] = useState("");

  function handleFilterApply() {
    setParams({
      ...params,
      status: (params.status || undefined) as OrderStatus | undefined,
      symbol: symbolFilter || undefined,
      from: dateFrom || undefined,
      to: dateTo || undefined,
      cursor: undefined,
    });
  }

  async function handleApprove() {
    if (!selectedOrder) return;
    if (killSwitchEnabled) {
      showToast("warning", MESSAGES["MSG-W-0031"]);
      return;
    }

    setActionLoading("approve");
    try {
      await apiClient<OperationResult>(API_ROUTES.ORDER_APPROVE(selectedOrder.orderId), {
        method: "POST",
        screenId: SCREEN_IDS.ORDERS,
        actionId: ACTION_IDS.ORDER_APPROVE,
      });
      showToast("success", MESSAGES["MSG-I-0031"]);
      await refetch();
      await fetchOrderDetail(selectedOrder.orderId);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0031"]);
      }
    } finally {
      setActionLoading(null);
    }
  }

  async function handleReject() {
    if (!selectedOrder) return;
    if (!rejectReason.trim()) {
      showToast("warning", MESSAGES.VALIDATION_REJECT_REASON);
      return;
    }

    const confirmed = await confirm({
      title: "注文を却下しますか？",
      message: `注文 ${selectedOrder.orderId} を却下します。`,
      confirmLabel: "却下",
      variant: "danger",
    });
    if (!confirmed) return;

    setActionLoading("reject");
    try {
      await apiClient<OperationResult>(API_ROUTES.ORDER_REJECT(selectedOrder.orderId), {
        method: "POST",
        body: { reason: rejectReason },
        screenId: SCREEN_IDS.ORDERS,
        actionId: ACTION_IDS.ORDER_REJECT,
      });
      showToast("success", MESSAGES["MSG-I-0032"]);
      setRejectReason("");
      await refetch();
      await fetchOrderDetail(selectedOrder.orderId);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0031"]);
      }
    } finally {
      setActionLoading(null);
    }
  }

  async function handleRetry() {
    if (!selectedOrder) return;
    setActionLoading("retry");
    try {
      await apiClient<CommandAccepted>(API_ROUTES.ORDER_RETRY(selectedOrder.orderId), {
        method: "POST",
        screenId: SCREEN_IDS.ORDERS,
        actionId: ACTION_IDS.ORDER_RETRY,
      });
      showToast("success", MESSAGES["MSG-I-0033"]);
      await refetch();
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0031"]);
      }
    } finally {
      setActionLoading(null);
    }
  }

  if (error) {
    return (
      <div className={styles.page}>
        <h1 className={styles.pageTitle}>注文管理</h1>
        <RetryBanner message={MESSAGES["MSG-E-0031"]} onRetry={refetch} loading={loading} />
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <h1 className={styles.pageTitle}>注文管理</h1>

      {killSwitchEnabled && (
        <RetryBanner message={MESSAGES["MSG-W-0031"]} onRetry={() => {}} />
      )}

      <div className={styles.filterSection}>
        <div className={styles.filterRow}>
          <div className={styles.filterField}>
            <SelectInput
              label="状態"
              options={ORDER_STATUS_OPTIONS}
              value={params.status ?? ""}
              onChange={(event) => setParams({ ...params, status: event.target.value as OrderStatus || undefined, cursor: undefined })}
            />
          </div>
          <div className={styles.filterField}>
            <TextInput
              label="銘柄"
              value={symbolFilter}
              onChange={(event) => setSymbolFilter(event.target.value)}
              placeholder="例: 7203"
            />
          </div>
          <DateRangePicker
            fromValue={dateFrom}
            toValue={dateTo}
            onFromChange={setDateFrom}
            onToChange={setDateTo}
          />
          <Button variant="primary" size="small" onClick={handleFilterApply}>
            検索
          </Button>
        </div>
      </div>

      <div className={`${styles.content} ${!selectedOrder ? styles.contentFullWidth : ""}`}>
        <div>
          {loading ? (
            <TableSkeleton rows={8} columns={5} />
          ) : !data?.items.length ? (
            <EmptyState message={MESSAGES.EMPTY_ORDERS} />
          ) : (
            <>
              <DataTable
                columns={ORDER_COLUMNS}
                data={data.items}
                keyExtractor={(item) => item.orderId}
                onRowClick={(item) => fetchOrderDetail(item.orderId)}
                selectedKey={selectedOrder?.orderId}
              />
              {data.nextCursor && (
                <div className={styles.loadMoreRow}>
                  <Button variant="ghost" size="small" onClick={loadMore}>
                    さらに読み込む
                  </Button>
                </div>
              )}
            </>
          )}
        </div>

        {selectedOrder && (
          <div className={styles.detailSection}>
            <DetailPanel
              title="注文詳細"
              rows={[
                { label: "注文ID", value: selectedOrder.orderId, mono: true },
                { label: "銘柄", value: selectedOrder.symbol, mono: true },
                { label: "売買区分", value: selectedOrder.side },
                { label: "数量", value: formatInteger(selectedOrder.qty), mono: true },
                { label: "状態", value: <StatusBadge status={selectedOrder.status} /> },
                { label: "理由コード", value: selectedOrder.reasonCode ?? "-", mono: true },
                { label: "traceId", value: selectedOrder.traceId ?? "-", mono: true },
                { label: "作成日時", value: formatDatetime(selectedOrder.createdAt) },
                ...(selectedOrder.updatedAt
                  ? [{ label: "更新日時", value: formatDatetime(selectedOrder.updatedAt) }]
                  : []),
              ]}
              actions={
                <>
                  {selectedOrder.status === "PROPOSED" && (
                    <>
                      <Button
                        variant="primary"
                        size="small"
                        onClick={handleApprove}
                        loading={actionLoading === "approve"}
                        disabled={!!actionLoading || killSwitchEnabled}
                      >
                        承認
                      </Button>
                      <Button
                        variant="danger"
                        size="small"
                        onClick={handleReject}
                        loading={actionLoading === "reject"}
                        disabled={!!actionLoading}
                      >
                        却下
                      </Button>
                    </>
                  )}
                  {selectedOrder.status === "FAILED" && (
                    <Button
                      variant="secondary"
                      size="small"
                      onClick={handleRetry}
                      loading={actionLoading === "retry"}
                      disabled={!!actionLoading}
                    >
                      再送
                    </Button>
                  )}
                </>
              }
            />
            {selectedOrder.status === "PROPOSED" && (
              <div className={styles.reasonInput}>
                <TextInput
                  label="却下理由"
                  value={rejectReason}
                  onChange={(event) => setRejectReason(event.target.value)}
                  placeholder="却下理由を入力"
                />
              </div>
            )}
          </div>
        )}
      </div>

      <ConfirmationModal
        isOpen={isOpen}
        config={config}
        onConfirm={handleConfirm}
        onCancel={handleCancel}
      />
    </div>
  );
}
