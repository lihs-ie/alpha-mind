import styles from "./StatusBadge.module.css";

type StatusVariant =
  | "proposed" | "approved" | "rejected" | "executed" | "failed"
  | "running" | "stopped"
  | "success"
  | "candidate";

interface StatusBadgeProps {
  status: string;
  label?: string;
}

const STATUS_MAP: Record<string, { variant: StatusVariant; label: string }> = {
  PROPOSED: { variant: "proposed", label: "提案中" },
  APPROVED: { variant: "approved", label: "承認済" },
  REJECTED: { variant: "rejected", label: "却下" },
  EXECUTED: { variant: "executed", label: "約定済" },
  FAILED: { variant: "failed", label: "失敗" },
  RUNNING: { variant: "running", label: "稼働中" },
  STOPPED: { variant: "stopped", label: "停止" },
  success: { variant: "success", label: "成功" },
  failed: { variant: "failed", label: "失敗" },
  candidate: { variant: "candidate", label: "候補" },
  approved: { variant: "approved", label: "承認済" },
  rejected: { variant: "rejected", label: "却下" },
};

export function StatusBadge({ status, label }: StatusBadgeProps) {
  const mapped = STATUS_MAP[status];
  const variant = mapped?.variant ?? "proposed";
  const displayLabel = label ?? mapped?.label ?? status;

  return (
    <span className={`${styles.badge} ${styles[variant]}`}>
      <span className={styles.dot} />
      {displayLabel}
    </span>
  );
}
