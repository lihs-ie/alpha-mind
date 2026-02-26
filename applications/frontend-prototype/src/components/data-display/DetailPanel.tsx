import type { ReactNode } from "react";
import styles from "./DetailPanel.module.css";

interface DetailRow {
  label: string;
  value: ReactNode;
  mono?: boolean;
}

interface DetailPanelProps {
  title: string;
  rows: DetailRow[];
  actions?: ReactNode;
  headerAction?: ReactNode;
}

export function DetailPanel({ title, rows, actions, headerAction }: DetailPanelProps) {
  return (
    <div className={styles.panel}>
      <div className={styles.header}>
        <h3 className={styles.title}>{title}</h3>
        {headerAction}
      </div>
      <div className={styles.rows}>
        {rows.map((row) => (
          <div key={row.label} className={styles.row}>
            <span className={styles.rowLabel}>{row.label}</span>
            <span className={`${styles.rowValue} ${row.mono ? styles.mono : ""}`}>
              {row.value}
            </span>
          </div>
        ))}
      </div>
      {actions && (
        <>
          <hr className={styles.divider} />
          <div className={styles.actions}>{actions}</div>
        </>
      )}
    </div>
  );
}
