"use client";

import { useState } from "react";
import { useAuditLogs } from "./useAuditLogs";
import { useClipboard } from "@/hooks/useClipboard";
import { formatDatetime } from "@/lib/formatters";
import { MESSAGES } from "@/constants/messages";
import type { AuditSummary } from "@/types/api";
import { DataTable, type Column } from "@/components/data-display/DataTable";
import { DetailPanel } from "@/components/data-display/DetailPanel";
import { StatusBadge } from "@/components/data-display/StatusBadge";
import { TextInput } from "@/components/form/TextInput";
import { DateRangePicker } from "@/components/form/DateRangePicker";
import { Button } from "@/components/actions/Button";
import { EmptyState } from "@/components/feedback/EmptyState";
import { RetryBanner } from "@/components/feedback/RetryBanner";
import { TableSkeleton } from "@/components/skeleton/TableSkeleton";
import styles from "./AuditPage.module.css";

export function AuditPage() {
  const {
    data, selectedLog, loading,
    error, params, setParams, refetch, fetchLogDetail, loadMore,
  } = useAuditLogs();
  const { copy } = useClipboard();

  const [traceIdFilter, setTraceIdFilter] = useState("");
  const [eventTypeFilter, setEventTypeFilter] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");

  function handleSearch() {
    setParams({
      traceId: traceIdFilter || undefined,
      eventType: eventTypeFilter || undefined,
      from: dateFrom || undefined,
      to: dateTo || undefined,
      cursor: undefined,
    });
  }

  function handleCsvDownload() {
    if (!data?.items.length) return;
    const headers = ["発生時刻", "イベント種別", "サービス", "結果", "traceId"];
    const rows = data.items.map((item) => [
      item.occurredAt,
      item.eventType,
      item.service,
      item.result,
      item.traceId,
    ]);
    const csv = [headers.join(","), ...rows.map((row) => row.join(","))].join("\n");
    const blob = new Blob(["\ufeff" + csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `audit_logs_${new Date().toISOString().slice(0, 10)}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  const columns: Column<AuditSummary>[] = [
    { key: "occurredAt", header: "発生時刻", render: (item) => formatDatetime(item.occurredAt) },
    { key: "eventType", header: "イベント種別", render: (item) => item.eventType },
    { key: "service", header: "サービス", render: (item) => item.service },
    { key: "result", header: "結果", render: (item) => <StatusBadge status={item.result} /> },
    {
      key: "traceId",
      header: "traceId",
      mono: true,
      render: (item) => (
        <div className={styles.traceIdCell}>
          <span>{item.traceId.slice(0, 12)}...</span>
          <button
            className={styles.copyButton}
            onClick={(event) => {
              event.stopPropagation();
              copy(item.traceId, MESSAGES["MSG-I-0041"]);
            }}
            aria-label="traceIdをコピー"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M15.666 3.888A2.25 2.25 0 0013.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 01-.75.75H9.75a.75.75 0 01-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 01-2.25 2.25H6.75A2.25 2.25 0 014.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 011.927-.184" />
            </svg>
          </button>
        </div>
      ),
    },
  ];

  if (error) {
    return (
      <div className={styles.page}>
        <h1 className={styles.pageTitle}>監査ログ</h1>
        <RetryBanner message={MESSAGES["MSG-E-0041"]} onRetry={refetch} loading={loading} />
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <div className={styles.pageHeader}>
        <h1 className={styles.pageTitle}>監査ログ</h1>
        <Button variant="secondary" size="small" onClick={handleCsvDownload} disabled={!data?.items.length}>
          CSV ダウンロード
        </Button>
      </div>

      <div className={styles.filterSection}>
        <div className={styles.filterRow}>
          <div className={styles.filterField}>
            <TextInput
              label="traceId"
              value={traceIdFilter}
              onChange={(event) => setTraceIdFilter(event.target.value)}
              placeholder="traceId"
            />
          </div>
          <div className={styles.filterField}>
            <TextInput
              label="イベント種別"
              value={eventTypeFilter}
              onChange={(event) => setEventTypeFilter(event.target.value)}
              placeholder="イベント種別"
            />
          </div>
          <DateRangePicker
            fromValue={dateFrom}
            toValue={dateTo}
            onFromChange={setDateFrom}
            onToChange={setDateTo}
          />
          <Button variant="primary" size="small" onClick={handleSearch}>
            検索
          </Button>
        </div>
      </div>

      <div className={`${styles.content} ${!selectedLog ? styles.contentFullWidth : ""}`}>
        <div>
          {loading ? (
            <TableSkeleton rows={8} columns={5} />
          ) : !data?.items.length ? (
            <EmptyState message={MESSAGES.EMPTY_AUDIT_LOGS} />
          ) : (
            <>
              <DataTable
                columns={columns}
                data={data.items}
                keyExtractor={(item) => item.logId}
                onRowClick={(item) => fetchLogDetail(item.logId)}
                selectedKey={selectedLog?.logId}
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

        {selectedLog && (
          <div className={styles.detailSection}>
            <DetailPanel
              title="ログ詳細"
              rows={[
                { label: "ログID", value: selectedLog.logId, mono: true },
                { label: "発生時刻", value: formatDatetime(selectedLog.occurredAt) },
                { label: "イベント種別", value: selectedLog.eventType },
                { label: "サービス", value: selectedLog.service },
                { label: "結果", value: <StatusBadge status={selectedLog.result} /> },
                { label: "traceId", value: selectedLog.traceId, mono: true },
                ...(selectedLog.reason ? [{ label: "理由", value: selectedLog.reason }] : []),
              ]}
            />
            {selectedLog.payload && (
              <div style={{ marginTop: 12 }}>
                <h4 style={{ fontSize: "0.875rem", fontWeight: 600, marginBottom: 8, color: "var(--color-text-primary)" }}>
                  Payload
                </h4>
                <pre className={styles.payloadBlock}>
                  {JSON.stringify(selectedLog.payload, null, 2)}
                </pre>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
