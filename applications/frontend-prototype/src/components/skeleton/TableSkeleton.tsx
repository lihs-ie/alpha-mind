import styles from "./Skeleton.module.css";

interface TableSkeletonProps {
  rows?: number;
  columns?: number;
}

export function TableSkeleton({ rows = 5, columns = 4 }: TableSkeletonProps) {
  return (
    <div className={styles.tableContainer}>
      <div className={styles.tableHeader}>
        {Array.from({ length: columns }).map((_, index) => (
          <div key={index} className={`${styles.skeleton} ${styles.tableHeaderCell}`} />
        ))}
      </div>
      {Array.from({ length: rows }).map((_, rowIndex) => (
        <div key={rowIndex} className={styles.tableRow}>
          {Array.from({ length: columns }).map((_, colIndex) => (
            <div key={colIndex} className={`${styles.skeleton} ${styles.tableCell}`} />
          ))}
        </div>
      ))}
    </div>
  );
}
