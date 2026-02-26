"use client";

import { useState } from "react";
import { useModelValidation } from "./useModelValidation";
import { useToast } from "@/hooks/useToast";
import { useConfirmation } from "@/hooks/useConfirmation";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import { ACTION_IDS } from "@/constants/actionIds";
import { MESSAGES } from "@/constants/messages";
import { formatDecimal, formatPercent, formatDatetime } from "@/lib/formatters";
import type { OperationResult, ModelStatus } from "@/types/api";
import { ApiError } from "@/types/errors";
import { StatusBadge } from "@/components/data-display/StatusBadge";
import { SelectInput } from "@/components/form/SelectInput";
import { TextInput } from "@/components/form/TextInput";
import { Button } from "@/components/actions/Button";
import { ConfirmationModal } from "@/components/feedback/ConfirmationModal";
import { EmptyState } from "@/components/feedback/EmptyState";
import { RetryBanner } from "@/components/feedback/RetryBanner";
import { CardSkeleton } from "@/components/skeleton/CardSkeleton";
import styles from "./ModelValidationPage.module.css";

const STATUS_OPTIONS = [
  { value: "", label: "すべて" },
  { value: "candidate", label: "候補" },
  { value: "approved", label: "承認済" },
  { value: "rejected", label: "却下" },
];

export function ModelValidationPage() {
  const {
    data, selectedModel, comparisonModel, loading,
    error, statusFilter, setStatusFilter,
    refetch, fetchModelDetail, fetchComparisonModel, clearComparison,
  } = useModelValidation();
  const { showToast } = useToast();
  const { isOpen, config, confirm, handleConfirm, handleCancel } = useConfirmation();

  const [decisionReason, setDecisionReason] = useState("");
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  async function handleApprove() {
    if (!selectedModel) return;
    if (!decisionReason.trim()) {
      showToast("warning", MESSAGES.VALIDATION_PROMOTE_REASON);
      return;
    }

    setActionLoading("approve");
    try {
      await apiClient<OperationResult>(API_ROUTES.MODEL_APPROVE(selectedModel.modelVersion), {
        method: "POST",
        body: { reason: decisionReason },
        screenId: SCREEN_IDS.MODEL_VALIDATION,
        actionId: ACTION_IDS.MODEL_APPROVE,
      });
      showToast("success", MESSAGES["MSG-I-0051"]);
      setDecisionReason("");
      await refetch();
      await fetchModelDetail(selectedModel.modelVersion);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0051"]);
      }
    } finally {
      setActionLoading(null);
    }
  }

  async function handleReject() {
    if (!selectedModel) return;
    if (!decisionReason.trim()) {
      showToast("warning", MESSAGES.VALIDATION_REVERT_REASON);
      return;
    }

    const confirmed = await confirm({
      title: "モデルを差し戻しますか？",
      message: `モデル ${selectedModel.modelVersion} を差し戻します。`,
      confirmLabel: "差し戻し",
      variant: "danger",
    });
    if (!confirmed) return;

    setActionLoading("reject");
    try {
      await apiClient<OperationResult>(API_ROUTES.MODEL_REJECT(selectedModel.modelVersion), {
        method: "POST",
        body: { reason: decisionReason },
        screenId: SCREEN_IDS.MODEL_VALIDATION,
        actionId: ACTION_IDS.MODEL_REJECT,
      });
      showToast("success", MESSAGES["MSG-I-0052"]);
      setDecisionReason("");
      await refetch();
      await fetchModelDetail(selectedModel.modelVersion);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0051"]);
      }
    } finally {
      setActionLoading(null);
    }
  }

  if (error) {
    return (
      <div className={styles.page}>
        <h1 className={styles.pageTitle}>モデル検証</h1>
        <RetryBanner message={MESSAGES["MSG-E-0051"]} onRetry={refetch} loading={loading} />
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <h1 className={styles.pageTitle}>モデル検証</h1>

      <div className={styles.filterRow}>
        <div className={styles.filterField}>
          <SelectInput
            label="状態"
            options={STATUS_OPTIONS}
            value={statusFilter ?? ""}
            onChange={(event) => setStatusFilter((event.target.value || undefined) as ModelStatus | undefined)}
          />
        </div>
      </div>

      {loading ? (
        <div style={{ display: "grid", gridTemplateColumns: "300px 1fr", gap: 16 }}>
          <CardSkeleton />
          <CardSkeleton />
        </div>
      ) : !data?.items.length ? (
        <EmptyState message={MESSAGES.EMPTY_MODELS} />
      ) : (
        <div className={styles.content}>
          <div className={styles.modelList}>
            <div className={styles.modelListHeader}>モデル一覧</div>
            {data.items.map((model) => (
              <div
                key={model.modelVersion}
                className={`${styles.modelItem} ${selectedModel?.modelVersion === model.modelVersion ? styles.modelItemActive : ""}`}
                onClick={() => fetchModelDetail(model.modelVersion)}
                tabIndex={0}
                onKeyDown={(event) => {
                  if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    fetchModelDetail(model.modelVersion);
                  }
                }}
              >
                <div className={styles.modelItemInfo}>
                  <span className={styles.modelVersion}>{model.modelVersion}</span>
                  <span className={styles.modelDate}>{formatDatetime(model.createdAt)}</span>
                </div>
                <StatusBadge status={model.status} />
              </div>
            ))}
          </div>

          <div className={styles.detailArea}>
            {selectedModel && (
              <>
                <div className={styles.metricsComparison}>
                  <table className={styles.comparisonTable}>
                    <thead>
                      <tr>
                        <th>指標</th>
                        <th>{selectedModel.modelVersion}</th>
                        {comparisonModel && <th>{comparisonModel.modelVersion}</th>}
                      </tr>
                    </thead>
                    <tbody>
                      <tr>
                        <td>OOS リターン</td>
                        <td>{formatPercent(selectedModel.metrics.oosReturn)}</td>
                        {comparisonModel && <td>{formatPercent(comparisonModel.metrics.oosReturn)}</td>}
                      </tr>
                      <tr>
                        <td>Sharpe</td>
                        <td>{formatDecimal(selectedModel.metrics.sharpe)}</td>
                        {comparisonModel && <td>{formatDecimal(comparisonModel.metrics.sharpe)}</td>}
                      </tr>
                      <tr>
                        <td>最大 DD</td>
                        <td>{formatPercent(selectedModel.metrics.maxDrawdown)}</td>
                        {comparisonModel && <td>{formatPercent(comparisonModel.metrics.maxDrawdown)}</td>}
                      </tr>
                      <tr>
                        <td>回転率</td>
                        <td>{formatPercent(selectedModel.metrics.turnover)}</td>
                        {comparisonModel && <td>{formatPercent(comparisonModel.metrics.turnover)}</td>}
                      </tr>
                      <tr>
                        <td>PBO</td>
                        <td>{formatPercent(selectedModel.metrics.pbo)}</td>
                        {comparisonModel && <td>{formatPercent(comparisonModel.metrics.pbo)}</td>}
                      </tr>
                      <tr>
                        <td>DSR</td>
                        <td>{formatDecimal(selectedModel.metrics.dsr)}</td>
                        {comparisonModel && <td>{formatDecimal(comparisonModel.metrics.dsr)}</td>}
                      </tr>
                    </tbody>
                  </table>
                </div>

                <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                  {data.items
                    .filter((model) => model.modelVersion !== selectedModel.modelVersion)
                    .slice(0, 5)
                    .map((model) => (
                      <label key={model.modelVersion} className={styles.compareCheckbox}>
                        <input
                          type="checkbox"
                          checked={comparisonModel?.modelVersion === model.modelVersion}
                          onChange={(event) => {
                            if (event.target.checked) {
                              fetchComparisonModel(model.modelVersion);
                            } else {
                              clearComparison();
                            }
                          }}
                        />
                        {model.modelVersion} と比較
                      </label>
                    ))}
                </div>

                {selectedModel.status === "candidate" && (
                  <div className={styles.decisionSection}>
                    <h3 className={styles.decisionTitle}>判定操作</h3>
                    <TextInput
                      label="理由"
                      value={decisionReason}
                      onChange={(event) => setDecisionReason(event.target.value)}
                      placeholder="昇格/差し戻し理由を入力"
                      required
                    />
                    <div className={styles.decisionActions}>
                      <Button
                        variant="primary"
                        size="small"
                        onClick={handleApprove}
                        loading={actionLoading === "approve"}
                        disabled={!!actionLoading}
                      >
                        昇格
                      </Button>
                      <Button
                        variant="danger"
                        size="small"
                        onClick={handleReject}
                        loading={actionLoading === "reject"}
                        disabled={!!actionLoading}
                      >
                        差し戻し
                      </Button>
                    </div>
                  </div>
                )}
              </>
            )}

            {!selectedModel && (
              <EmptyState message="モデルを選択してください" />
            )}
          </div>
        </div>
      )}

      <ConfirmationModal
        isOpen={isOpen}
        config={config}
        onConfirm={handleConfirm}
        onCancel={handleCancel}
      />
    </div>
  );
}
