import styles from "./Skeleton.module.css";

export function CardSkeleton() {
  return (
    <div className={styles.card}>
      <div className={`${styles.skeleton} ${styles.cardLabel}`} />
      <div className={`${styles.skeleton} ${styles.cardValue}`} />
      <div className={`${styles.skeleton} ${styles.cardSubtitle}`} />
    </div>
  );
}
