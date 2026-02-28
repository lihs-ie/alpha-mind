"use client";

import { useState } from "react";
import { useDashboardSummary } from "./useDashboardSummary";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/useToast";
import { useConfirmation } from "@/hooks/useConfirmation";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import { ACTION_IDS } from "@/constants/actionIds";
import { MESSAGES } from "@/constants/messages";
import { formatPnlSign, formatPercent, formatDatetime } from "@/lib/formatters";
import type { RuntimeOperationRequest, KillSwitchRequest, OperationResult, CommandAccepted } from "@/types/api";
import { ApiError } from "@/types/errors";
import { KpiCard } from "@/components/data-display/KpiCard";
import { StatusBadge } from "@/components/data-display/StatusBadge";
import { Button } from "@/components/actions/Button";
import { ToggleSwitch } from "@/components/form/ToggleSwitch";
import { ConfirmationModal } from "@/components/feedback/ConfirmationModal";
import { RetryBanner } from "@/components/feedback/RetryBanner";
import { CardSkeleton } from "@/components/skeleton/CardSkeleton";
import styles from "./DashboardPage.module.css";

export function DashboardPage() {
  const { data, loading, error, refetch } = useDashboardSummary();
  const { killSwitchEnabled, setKillSwitchEnabled } = useAuth();
  const { showToast } = useToast();
  const { isOpen, config, confirm, handleConfirm, handleCancel } = useConfirmation();
  const [operationLoading, setOperationLoading] = useState<string | null>(null);

  async function handleRuntimeOperation(action: "START" | "STOP") {
    setOperationLoading(action);
    try {
      await apiClient<OperationResult>(API_ROUTES.OPERATIONS_RUNTIME, {
        method: "POST",
        body: { action } satisfies RuntimeOperationRequest,
        screenId: SCREEN_IDS.DASHBOARD,
        actionId: action === "START" ? ACTION_IDS.RUNTIME_START : ACTION_IDS.RUNTIME_STOP,
      });
      showToast("success", action === "START" ? MESSAGES["MSG-I-0011"] : MESSAGES["MSG-I-0012"]);
      await refetch();
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0011"]);
      }
    } finally {
      setOperationLoading(null);
    }
  }

  async function handleKillSwitch(enabled: boolean) {
    const confirmed = await confirm({
      title: `kill switch を${enabled ? "有効" : "無効"}にしますか？`,
      message: enabled
        ? "有効にすると、すべての発注系操作が停止されます。"
        : "無効にすると、発注系操作が再開されます。",
      confirmLabel: enabled ? "有効にする" : "無効にする",
      variant: enabled ? "danger" : "default",
    });
    if (!confirmed) return;

    setOperationLoading("KILL_SWITCH");
    try {
      await apiClient<OperationResult>(API_ROUTES.OPERATIONS_KILL_SWITCH, {
        method: "POST",
        body: { enabled } satisfies KillSwitchRequest,
        screenId: SCREEN_IDS.DASHBOARD,
        actionId: ACTION_IDS.KILL_SWITCH_TOGGLE,
      });
      setKillSwitchEnabled(enabled);
      showToast("success", enabled ? MESSAGES["MSG-I-0013-ON"] : MESSAGES["MSG-I-0013-OFF"]);
      await refetch();
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0011"]);
      }
    } finally {
      setOperationLoading(null);
    }
  }

  async function handleManualCycle() {
    setOperationLoading("CYCLE");
    try {
      await apiClient<CommandAccepted>(API_ROUTES.COMMANDS_RUN_CYCLE, {
        method: "POST",
        body: { mode: "manual" },
        screenId: SCREEN_IDS.DASHBOARD,
        actionId: ACTION_IDS.MANUAL_CYCLE_RUN,
      });
      showToast("success", MESSAGES["MSG-I-0014"]);
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0011"]);
      }
    } finally {
      setOperationLoading(null);
    }
  }

  if (error) {
    return (
      <div className={styles.page}>
        <h1 className={styles.pageTitle}>ダッシュボード</h1>
        <RetryBanner message={MESSAGES["MSG-E-0011"]} onRetry={refetch} loading={loading} />
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <div className={styles.pageHeader}>
        <h1 className={styles.pageTitle}>ダッシュボード</h1>
      </div>

      {killSwitchEnabled && (
        <RetryBanner message={MESSAGES["MSG-W-0011"]} onRetry={() => handleKillSwitch(false)} />
      )}

      <div className={styles.kpiGrid}>
        {loading ? (
          <>
            <CardSkeleton />
            <CardSkeleton />
            <CardSkeleton />
            <CardSkeleton />
          </>
        ) : data ? (
          <>
            <KpiCard
              label="当日損益"
              value={formatPnlSign(data.pnlToday)}
              valueColor={data.pnlToday > 0 ? "profit" : data.pnlToday < 0 ? "loss" : "neutral"}
            />
            <KpiCard
              label="累積損益"
              value={formatPnlSign(data.pnlTotal)}
              valueColor={data.pnlTotal > 0 ? "profit" : data.pnlTotal < 0 ? "loss" : "neutral"}
            />
            <KpiCard
              label="最大ドローダウン"
              value={formatPercent(data.maxDrawdown)}
              valueColor="loss"
            />
            <KpiCard
              label="稼働状態"
              value={data.runtimeState === "RUNNING" ? "稼働中" : "停止"}
              subtitle={<StatusBadge status={data.runtimeState} />}
            />
          </>
        ) : null}
      </div>

      <div className={styles.operationPanel}>
        <h2 className={styles.operationTitle}>操作パネル</h2>
        <div className={styles.operationActions}>
          <Button
            variant="primary"
            size="small"
            onClick={() => handleRuntimeOperation("START")}
            loading={operationLoading === "START"}
            disabled={!!operationLoading || data?.runtimeState === "RUNNING"}
          >
            運用開始
          </Button>
          <Button
            variant="secondary"
            size="small"
            onClick={() => handleRuntimeOperation("STOP")}
            loading={operationLoading === "STOP"}
            disabled={!!operationLoading || data?.runtimeState === "STOPPED"}
          >
            運用停止
          </Button>
          <Button
            variant="secondary"
            size="small"
            onClick={handleManualCycle}
            loading={operationLoading === "CYCLE"}
            disabled={!!operationLoading || killSwitchEnabled}
          >
            手動サイクル実行
          </Button>
          <div className={styles.killSwitchSection}>
            <span className={styles.killSwitchLabel}>Kill Switch</span>
            <ToggleSwitch
              label="Kill Switch"
              checked={killSwitchEnabled}
              onChange={handleKillSwitch}
              disabled={operationLoading === "KILL_SWITCH"}
            />
          </div>
        </div>
      </div>

      {data && (
        <div className={styles.infoGrid}>
          <div className={styles.infoCard}>
            <h3 className={styles.infoTitle}>最新実行情報</h3>
            <div className={styles.infoRow}>
              <span className={styles.infoLabel}>最新シグナル時刻</span>
              <span className={styles.infoValue}>{formatDatetime(data.latestSignalAt)}</span>
            </div>
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
