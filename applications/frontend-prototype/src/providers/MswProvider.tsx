"use client";

import { useEffect, useState, type ReactNode } from "react";

export function MswProvider({ children }: { children: ReactNode }) {
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    if (process.env.NODE_ENV !== "development") {
      setIsReady(true);
      return;
    }

    import("@/mocks/init").then(({ initMocks }) =>
      initMocks().then(() => setIsReady(true))
    );
  }, []);

  if (!isReady) {
    return null;
  }

  return <>{children}</>;
}
