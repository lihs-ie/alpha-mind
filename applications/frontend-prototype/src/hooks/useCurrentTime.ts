"use client";

import { useEffect, useState } from "react";

export function useCurrentTime(intervalMs = 1000) {
  const [currentTime, setCurrentTime] = useState(new Date());

  useEffect(() => {
    const timer = setInterval(() => setCurrentTime(new Date()), intervalMs);
    return () => clearInterval(timer);
  }, [intervalMs]);

  return currentTime;
}
