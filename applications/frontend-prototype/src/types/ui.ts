export type ToastType = "success" | "warning" | "error";

export interface ToastMessage {
  id: string;
  type: ToastType;
  message: string;
  duration?: number;
}

export interface ConfirmationConfig {
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel?: string;
  variant?: "danger" | "warning" | "default";
}

export type Theme = "light" | "dark";

export interface SidebarItem {
  label: string;
  href: string;
  icon: string;
  screenId: string;
}
