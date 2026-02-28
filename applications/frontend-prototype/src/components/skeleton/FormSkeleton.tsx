import styles from "./Skeleton.module.css";

interface FormSkeletonProps {
  fields?: number;
}

export function FormSkeleton({ fields = 4 }: FormSkeletonProps) {
  return (
    <div className={styles.formGroup}>
      {Array.from({ length: fields }).map((_, index) => (
        <div key={index}>
          <div className={`${styles.skeleton} ${styles.formLabel}`} style={{ marginBottom: 8 }} />
          <div className={`${styles.skeleton} ${styles.formInput}`} />
        </div>
      ))}
    </div>
  );
}
