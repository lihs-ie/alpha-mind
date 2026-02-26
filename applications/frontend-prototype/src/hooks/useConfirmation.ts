"use client";

import { useCallback, useState } from "react";
import type { ConfirmationConfig } from "@/types/ui";

interface UseConfirmationReturn {
  isOpen: boolean;
  config: ConfirmationConfig | null;
  confirm: (config: ConfirmationConfig) => Promise<boolean>;
  handleConfirm: () => void;
  handleCancel: () => void;
}

export function useConfirmation(): UseConfirmationReturn {
  const [isOpen, setIsOpen] = useState(false);
  const [config, setConfig] = useState<ConfirmationConfig | null>(null);
  const [resolver, setResolver] = useState<((value: boolean) => void) | null>(null);

  const confirm = useCallback((confirmationConfig: ConfirmationConfig): Promise<boolean> => {
    setConfig(confirmationConfig);
    setIsOpen(true);
    return new Promise<boolean>((resolve) => {
      setResolver(() => resolve);
    });
  }, []);

  const handleConfirm = useCallback(() => {
    setIsOpen(false);
    resolver?.(true);
    setResolver(null);
  }, [resolver]);

  const handleCancel = useCallback(() => {
    setIsOpen(false);
    resolver?.(false);
    setResolver(null);
  }, [resolver]);

  return { isOpen, config, confirm, handleConfirm, handleCancel };
}
