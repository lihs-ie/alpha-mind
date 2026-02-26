"use client";

import {
  createContext,
  useCallback,
  useState,
  type ReactNode,
} from "react";
import type { ToastMessage, ToastType } from "@/types/ui";
import { Toast } from "@/components/feedback/Toast";

interface ToastContextValue {
  showToast: (type: ToastType, message: string) => void;
}

export const ToastContext = createContext<ToastContextValue>({
  showToast: () => {},
});

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  const removeToast = useCallback((id: string) => {
    setToasts((previous) => previous.filter((toast) => toast.id !== id));
  }, []);

  const showToast = useCallback((type: ToastType, message: string) => {
    const id = `toast_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;
    const toast: ToastMessage = { id, type, message, duration: 5000 };
    setToasts((previous) => [...previous, toast]);
  }, []);

  return (
    <ToastContext.Provider value={{ showToast }}>
      {children}
      <div
        style={{
          position: "fixed",
          top: 16,
          right: 16,
          zIndex: "var(--z-toast)" as string,
          display: "flex",
          flexDirection: "column",
          gap: 8,
          pointerEvents: "none",
        }}
      >
        {toasts.map((toast) => (
          <Toast key={toast.id} toast={toast} onClose={removeToast} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}
