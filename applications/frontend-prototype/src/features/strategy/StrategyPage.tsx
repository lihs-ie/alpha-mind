"use client";

import { useEffect, useState } from "react";
import { useStrategySettings } from "./useStrategySettings";
import { useToast } from "@/hooks/useToast";
import { useConfirmation } from "@/hooks/useConfirmation";
import { apiClient } from "@/lib/apiClient";
import { API_ROUTES } from "@/constants/routes";
import { SCREEN_IDS } from "@/constants/screenIds";
import { ACTION_IDS } from "@/constants/actionIds";
import { MESSAGES } from "@/constants/messages";
import { isInRange, isInIntegerRange } from "@/lib/validators";
import type { StrategySettings, StrategySettingsUpdate, OperationResult } from "@/types/api";
import { ApiError } from "@/types/errors";
import { SelectInput } from "@/components/form/SelectInput";
import { NumberInput } from "@/components/form/NumberInput";
import { TextInput } from "@/components/form/TextInput";
import { Button } from "@/components/actions/Button";
import { ConfirmationModal } from "@/components/feedback/ConfirmationModal";
import { RetryBanner } from "@/components/feedback/RetryBanner";
import { FormSkeleton } from "@/components/skeleton/FormSkeleton";
import styles from "./StrategyPage.module.css";

const DEFAULT_SETTINGS: StrategySettings = {
  market: "JP",
  rebalanceFrequency: "daily",
  symbols: [],
  dailyLossLimit: 5,
  positionConcentrationLimit: 20,
  dailyOrderLimit: 50,
};

export function StrategyPage() {
  const { data, loading, error, refetch } = useStrategySettings();
  const { showToast } = useToast();
  const { isOpen, config, confirm, handleConfirm, handleCancel } = useConfirmation();

  const [form, setForm] = useState<StrategySettings>(DEFAULT_SETTINGS);
  const [newSymbol, setNewSymbol] = useState("");
  const [saving, setSaving] = useState(false);
  const [validationErrors, setValidationErrors] = useState<Record<string, string>>({});

  useEffect(() => {
    if (data) setForm(data);
  }, [data]);

  function validate(): boolean {
    const errors: Record<string, string> = {};
    if (!form.rebalanceFrequency) errors.rebalanceFrequency = MESSAGES.VALIDATION_FREQUENCY_REQUIRED;
    if (form.symbols.length === 0) errors.symbols = MESSAGES.VALIDATION_SYMBOLS_REQUIRED;
    if (!isInRange(form.dailyLossLimit, 0, 20)) errors.dailyLossLimit = MESSAGES.VALIDATION_DAILY_LOSS_LIMIT;
    if (!isInRange(form.positionConcentrationLimit, 0, 50)) errors.positionConcentrationLimit = MESSAGES.VALIDATION_POSITION_LIMIT;
    if (!isInIntegerRange(form.dailyOrderLimit, 1, 100)) errors.dailyOrderLimit = MESSAGES.VALIDATION_ORDER_LIMIT;
    setValidationErrors(errors);
    return Object.keys(errors).length === 0;
  }

  async function handleSave() {
    if (!validate()) return;

    setSaving(true);
    try {
      await apiClient<OperationResult>(API_ROUTES.SETTINGS_STRATEGY, {
        method: "PUT",
        body: form satisfies StrategySettingsUpdate,
        screenId: SCREEN_IDS.STRATEGY_SETTINGS,
        actionId: ACTION_IDS.STRATEGY_SAVE,
      });
      showToast("success", MESSAGES["MSG-I-0021"]);
      await refetch();
    } catch (thrown) {
      if (thrown instanceof ApiError) {
        showToast("error", MESSAGES["MSG-E-0021"]);
      }
    } finally {
      setSaving(false);
    }
  }

  async function handleReset() {
    const confirmed = await confirm({
      title: "初期値に戻しますか？",
      message: "入力中の変更が破棄され、初期値に戻ります。",
      confirmLabel: "初期値に戻す",
      variant: "warning",
    });
    if (confirmed) {
      setForm(data ?? DEFAULT_SETTINGS);
      setValidationErrors({});
    }
  }

  function handleAddSymbol() {
    const symbol = newSymbol.trim().toUpperCase();
    if (!symbol) return;
    if (form.symbols.includes(symbol)) return;
    setForm((previous) => ({ ...previous, symbols: [...previous.symbols, symbol] }));
    setNewSymbol("");
  }

  function handleRemoveSymbol(symbol: string) {
    setForm((previous) => ({
      ...previous,
      symbols: previous.symbols.filter((existingSymbol) => existingSymbol !== symbol),
    }));
  }

  if (error) {
    return (
      <div className={styles.page}>
        <h1 className={styles.pageTitle}>戦略設定</h1>
        <RetryBanner message={MESSAGES["MSG-E-0021"]} onRetry={refetch} loading={loading} />
      </div>
    );
  }

  if (loading) {
    return (
      <div className={styles.page}>
        <h1 className={styles.pageTitle}>戦略設定</h1>
        <div className={styles.section}>
          <FormSkeleton fields={5} />
        </div>
      </div>
    );
  }

  return (
    <div className={styles.page}>
      <h1 className={styles.pageTitle}>戦略設定</h1>

      <div className={styles.section}>
        <h2 className={styles.sectionTitle}>基本設定</h2>
        <div className={styles.fieldGrid}>
          <SelectInput
            label="対象市場"
            options={[{ value: "JP", label: "日本 (JP)" }]}
            value={form.market}
            disabled
          />
          <SelectInput
            label="売買頻度"
            options={[
              { value: "daily", label: "日次" },
              { value: "weekly", label: "週次" },
            ]}
            value={form.rebalanceFrequency}
            onChange={(event) => setForm((previous) => ({ ...previous, rebalanceFrequency: event.target.value as "daily" | "weekly" }))}
            error={validationErrors.rebalanceFrequency}
            required
          />
        </div>
      </div>

      <div className={styles.section}>
        <h2 className={styles.sectionTitle}>ユニバース設定</h2>
        <div className={styles.symbolSection}>
          <div className={styles.symbolInputRow}>
            <div className={styles.symbolInput}>
              <TextInput
                label="銘柄コード"
                value={newSymbol}
                onChange={(event) => setNewSymbol(event.target.value)}
                placeholder="例: 7203"
                onKeyDown={(event) => {
                  if (event.key === "Enter") {
                    event.preventDefault();
                    handleAddSymbol();
                  }
                }}
              />
            </div>
            <Button
              variant="secondary"
              size="medium"
              onClick={handleAddSymbol}
              style={{ alignSelf: "flex-end" }}
            >
              追加
            </Button>
          </div>
          {validationErrors.symbols && (
            <span style={{ fontSize: "0.75rem", color: "var(--color-loss)" }} role="alert">
              {validationErrors.symbols}
            </span>
          )}
          <div className={styles.symbolList}>
            {form.symbols.map((symbol) => (
              <span key={symbol} className={styles.symbolChip}>
                {symbol}
                <button
                  className={styles.symbolRemoveButton}
                  onClick={() => handleRemoveSymbol(symbol)}
                  aria-label={`${symbol}を削除`}
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </span>
            ))}
          </div>
        </div>
      </div>

      <div className={styles.section}>
        <h2 className={styles.sectionTitle}>リスク設定</h2>
        <div className={styles.fieldGrid}>
          <NumberInput
            label="1日損失上限"
            unit="%"
            value={form.dailyLossLimit}
            onChange={(event) => setForm((previous) => ({ ...previous, dailyLossLimit: Number(event.target.value) }))}
            min={0}
            max={20}
            step={0.1}
            error={validationErrors.dailyLossLimit}
            required
          />
          <NumberInput
            label="1銘柄集中上限"
            unit="%"
            value={form.positionConcentrationLimit}
            onChange={(event) => setForm((previous) => ({ ...previous, positionConcentrationLimit: Number(event.target.value) }))}
            min={0}
            max={50}
            step={0.1}
            error={validationErrors.positionConcentrationLimit}
            required
          />
          <NumberInput
            label="1日注文上限件数"
            value={form.dailyOrderLimit}
            onChange={(event) => setForm((previous) => ({ ...previous, dailyOrderLimit: Number(event.target.value) }))}
            min={1}
            max={100}
            step={1}
            error={validationErrors.dailyOrderLimit}
            required
          />
        </div>
      </div>

      <div className={styles.actions}>
        <Button variant="ghost" onClick={handleReset}>
          初期値に戻す
        </Button>
        <Button variant="primary" onClick={handleSave} loading={saving}>
          保存
        </Button>
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
