"use client";

import { useEffect } from "react";
import type { ConfirmationConfig } from "@/types/ui";
import { useFocusTrap } from "@/hooks/useFocusTrap";
import { Button } from "@/components/actions/Button";
import styles from "./ConfirmationModal.module.css";

interface ConfirmationModalProps {
  isOpen: boolean;
  config: ConfirmationConfig | null;
  onConfirm: () => void;
  onCancel: () => void;
}

export function ConfirmationModal({
  isOpen,
  config,
  onConfirm,
  onCancel,
}: ConfirmationModalProps) {
  const focusTrapRef = useFocusTrap(isOpen);

  useEffect(() => {
    if (!isOpen) return;
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onCancel();
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [isOpen, onCancel]);

  if (!isOpen || !config) return null;

  const confirmVariant = config.variant === "danger" ? "danger" : "primary";

  return (
    <div className={styles.overlay} onClick={onCancel} role="dialog" aria-modal="true">
      <div
        ref={focusTrapRef}
        className={styles.dialog}
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className={styles.title}>{config.title}</h2>
        <p className={styles.message}>{config.message}</p>
        <div className={styles.actions}>
          <Button variant="ghost" onClick={onCancel}>
            {config.cancelLabel ?? "キャンセル"}
          </Button>
          <Button variant={confirmVariant} onClick={onConfirm}>
            {config.confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  );
}
