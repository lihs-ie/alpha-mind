"use client";

import { useEffect, useState } from "react";
import type { ToastMessage } from "@/types/ui";
import styles from "./Toast.module.css";

interface ToastProps {
  toast: ToastMessage;
  onClose: (id: string) => void;
}

export function Toast({ toast, onClose }: ToastProps) {
  const [exiting, setExiting] = useState(false);

  useEffect(() => {
    const duration = toast.duration ?? 5000;
    const timer = setTimeout(() => setExiting(true), duration);
    return () => clearTimeout(timer);
  }, [toast.duration]);

  useEffect(() => {
    if (!exiting) return;
    const timer = setTimeout(() => onClose(toast.id), 300);
    return () => clearTimeout(timer);
  }, [exiting, onClose, toast.id]);

  const iconPath = {
    success: "M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
    warning: "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z",
    error: "M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
  };

  return (
    <div
      className={`${styles.container} ${styles[toast.type]} ${exiting ? styles.exiting : ""}`}
      role="alert"
    >
      <svg
        className={styles.icon}
        fill="none"
        viewBox="0 0 24 24"
        strokeWidth={1.5}
        stroke="currentColor"
      >
        <path strokeLinecap="round" strokeLinejoin="round" d={iconPath[toast.type]} />
      </svg>
      <span className={styles.message}>{toast.message}</span>
      <button
        className={styles.closeButton}
        onClick={() => setExiting(true)}
        aria-label="閉じる"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
}
