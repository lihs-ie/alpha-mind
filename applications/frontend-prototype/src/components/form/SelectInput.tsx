import type { SelectHTMLAttributes } from "react";
import styles from "./SelectInput.module.css";

interface SelectOption {
  value: string;
  label: string;
}

interface SelectInputProps extends SelectHTMLAttributes<HTMLSelectElement> {
  label: string;
  options: SelectOption[];
  error?: string;
  placeholder?: string;
}

export function SelectInput({
  label,
  options,
  error,
  placeholder,
  id,
  required,
  className,
  ...props
}: SelectInputProps) {
  const selectId = id ?? label.toLowerCase().replace(/\s+/g, "-");

  return (
    <div className={`${styles.field} ${className ?? ""}`}>
      <label htmlFor={selectId} className={styles.label}>
        {label}
        {required && <span className={styles.required}>*</span>}
      </label>
      <select
        id={selectId}
        className={`${styles.select} ${error ? styles.selectError : ""}`}
        aria-invalid={!!error}
        required={required}
        {...props}
      >
        {placeholder && <option value="">{placeholder}</option>}
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      {error && (
        <span className={styles.errorMessage} role="alert">
          {error}
        </span>
      )}
    </div>
  );
}
