import type { InputHTMLAttributes } from "react";
import styles from "./TextInput.module.css";

interface NumberInputProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "type"> {
  label: string;
  error?: string;
  unit?: string;
}

export function NumberInput({ label, error, unit, id, required, className, ...props }: NumberInputProps) {
  const inputId = id ?? label.toLowerCase().replace(/\s+/g, "-");

  return (
    <div className={`${styles.field} ${className ?? ""}`}>
      <label htmlFor={inputId} className={styles.label}>
        {label}
        {unit && <span style={{ fontWeight: 400, color: "var(--color-text-muted)", marginLeft: 4, fontSize: "0.75rem" }}>({unit})</span>}
        {required && <span className={styles.required}>*</span>}
      </label>
      <input
        id={inputId}
        type="number"
        className={`${styles.input} ${error ? styles.inputError : ""}`}
        aria-invalid={!!error}
        aria-describedby={error ? `${inputId}-error` : undefined}
        required={required}
        style={{ fontFamily: "var(--font-mono)" }}
        {...props}
      />
      {error && (
        <span id={`${inputId}-error`} className={styles.errorMessage} role="alert">
          {error}
        </span>
      )}
    </div>
  );
}
