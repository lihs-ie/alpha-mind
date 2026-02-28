"use client";

import {
  createContext,
  useCallback,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import type { User } from "@/types/api";
import type { AuthSession } from "@/types/domain";
import { getAccessToken, removeAccessToken, setAccessToken } from "@/lib/authToken";
import { ROUTES } from "@/constants/routes";

interface AuthContextValue {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  killSwitchEnabled: boolean;
  setKillSwitchEnabled: (enabled: boolean) => void;
  login: (session: AuthSession) => void;
  logout: () => void;
}

export const AuthContext = createContext<AuthContextValue>({
  user: null,
  isAuthenticated: false,
  isLoading: true,
  killSwitchEnabled: false,
  setKillSwitchEnabled: () => {},
  login: () => {},
  logout: () => {},
});

const USER_KEY = "alpha_mind_user";
const EXPIRES_KEY = "alpha_mind_expires";

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [killSwitchEnabled, setKillSwitchEnabled] = useState(false);
  const router = useRouter();

  useEffect(() => {
    const token = getAccessToken();
    const storedUser = sessionStorage.getItem(USER_KEY);
    const storedExpires = sessionStorage.getItem(EXPIRES_KEY);

    if (token && storedUser && storedExpires) {
      const expiresAt = Number(storedExpires);
      if (Date.now() < expiresAt) {
        setUser(JSON.parse(storedUser));
      } else {
        removeAccessToken();
        sessionStorage.removeItem(USER_KEY);
        sessionStorage.removeItem(EXPIRES_KEY);
      }
    }
    setIsLoading(false);
  }, []);

  const login = useCallback((session: AuthSession) => {
    setAccessToken(session.accessToken);
    sessionStorage.setItem(USER_KEY, JSON.stringify(session.user));
    sessionStorage.setItem(EXPIRES_KEY, String(session.expiresAt));
    setUser(session.user);
  }, []);

  const logout = useCallback(() => {
    removeAccessToken();
    sessionStorage.removeItem(USER_KEY);
    sessionStorage.removeItem(EXPIRES_KEY);
    setUser(null);
    router.push(ROUTES.LOGIN);
  }, [router]);

  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated: user !== null,
        isLoading,
        killSwitchEnabled,
        setKillSwitchEnabled,
        login,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
