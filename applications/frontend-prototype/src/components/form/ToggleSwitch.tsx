import styles from "./ToggleSwitch.module.css";

interface ToggleSwitchProps {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
}

export function ToggleSwitch({ label, checked, onChange, disabled }: ToggleSwitchProps) {
  return (
    <div className={styles.container}>
      <button
        role="switch"
        aria-checked={checked}
        aria-label={label}
        className={`${styles.track} ${checked ? styles.trackEnabled : ""}`}
        onClick={() => !disabled && onChange(!checked)}
        disabled={disabled}
      >
        <span className={`${styles.thumb} ${checked ? styles.thumbEnabled : ""}`} />
      </button>
      <span className={styles.label}>{label}</span>
    </div>
  );
}
