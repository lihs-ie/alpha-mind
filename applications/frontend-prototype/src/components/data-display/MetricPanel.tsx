import styles from "./MetricPanel.module.css";

interface Metric {
  label: string;
  value: string;
}

interface MetricPanelProps {
  title: string;
  metrics: Metric[];
}

export function MetricPanel({ title, metrics }: MetricPanelProps) {
  return (
    <div className={styles.panel}>
      <h3 className={styles.title}>{title}</h3>
      <div className={styles.grid}>
        {metrics.map((metric) => (
          <div key={metric.label} className={styles.metric}>
            <span className={styles.metricLabel}>{metric.label}</span>
            <span className={styles.metricValue}>{metric.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
