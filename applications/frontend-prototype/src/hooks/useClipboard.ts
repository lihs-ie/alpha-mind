"use client";

import { useCallback } from "react";
import { useToast } from "./useToast";

export function useClipboard() {
  const { showToast } = useToast();

  const copy = useCallback(async (text: string, successMessage?: string) => {
    try {
      await navigator.clipboard.writeText(text);
      showToast("success", successMessage ?? "コピーしました。");
      return true;
    } catch {
      showToast("error", "コピーに失敗しました。");
      return false;
    }
  }, [showToast]);

  return { copy };
}
