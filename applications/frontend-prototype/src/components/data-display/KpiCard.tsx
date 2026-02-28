import type { ReactNode } from "react";
import styles from "./KpiCard.module.css";

type ValueColor = "profit" | "loss" | "neutral";

interface KpiCardProps {
  label: string;
  value: string;
  valueColor?: ValueColor;
  subtitle?: ReactNode;
  icon?: ReactNode;
}

export function KpiCard({ label, value, valueColor = "neutral", subtitle, icon }: KpiCardProps) {
  return (
    <div className={styles.card}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <span className={styles.label}>{label}</span>
        {icon}
      </div>
      <span className={`${styles.value} ${styles[valueColor]}`}>{value}</span>
      {subtitle && <span className={styles.subtitle}>{subtitle}</span>}
    </div>
  );
}
