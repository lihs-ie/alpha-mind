import styles from "./DateRangePicker.module.css";

interface DateRangePickerProps {
  fromValue: string;
  toValue: string;
  onFromChange: (value: string) => void;
  onToChange: (value: string) => void;
  error?: string;
}

export function DateRangePicker({
  fromValue,
  toValue,
  onFromChange,
  onToChange,
  error,
}: DateRangePickerProps) {
  return (
    <div>
      <div className={styles.container}>
        <div className={styles.field}>
          <label htmlFor="date-from" className={styles.label}>
            開始日
          </label>
          <input
            id="date-from"
            type="datetime-local"
            className={styles.input}
            value={fromValue}
            onChange={(event) => onFromChange(event.target.value)}
          />
        </div>
        <span className={styles.separator}>~</span>
        <div className={styles.field}>
          <label htmlFor="date-to" className={styles.label}>
            終了日
          </label>
          <input
            id="date-to"
            type="datetime-local"
            className={styles.input}
            value={toValue}
            onChange={(event) => onToChange(event.target.value)}
          />
        </div>
      </div>
      {error && <p className={styles.error} role="alert">{error}</p>}
    </div>
  );
}
