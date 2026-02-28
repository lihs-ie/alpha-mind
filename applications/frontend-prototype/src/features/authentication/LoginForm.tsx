"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";
import { useToast } from "@/hooks/useToast";
import { apiClient } from "@/lib/apiClient";
import { isValidEmail } from "@/lib/validators";
import { API_ROUTES, ROUTES } from "@/constants/routes";
import { MESSAGES } from "@/constants/messages";
import { SCREEN_IDS } from "@/constants/screenIds";
import { ACTION_IDS } from "@/constants/actionIds";
import type { LoginRequest, LoginResponse } from "@/types/api";
import { ApiError } from "@/types/errors";
import { TextInput } from "@/components/form/TextInput";
import { Button } from "@/components/actions/Button";
import styles from "./LoginForm.module.css";

export function LoginForm() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [errors, setErrors] = useState<{ email?: string; password?: string }>({});
  const [serverError, setServerError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const { login } = useAuth();
  const { showToast } = useToast();
  const router = useRouter();

  function validate(): boolean {
    const newErrors: { email?: string; password?: string } = {};
    if (!email.trim()) {
      newErrors.email = MESSAGES.VALIDATION_EMAIL_REQUIRED;
    } else if (!isValidEmail(email)) {
      newErrors.email = MESSAGES.VALIDATION_EMAIL_FORMAT;
    }
    if (!password) {
      newErrors.password = MESSAGES.VALIDATION_PASSWORD_REQUIRED;
    }
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setServerError(null);

    if (!validate()) return;

    setLoading(true);
    try {
      const response = await apiClient<LoginResponse>(API_ROUTES.AUTH_LOGIN, {
        method: "POST",
        body: { email, password } satisfies LoginRequest,
        screenId: SCREEN_IDS.LOGIN,
        actionId: ACTION_IDS.LOGIN,
      });

      login({
        accessToken: response.accessToken,
        expiresAt: Date.now() + response.expiresIn * 1000,
        user: response.user,
      });

      router.push(ROUTES.DASHBOARD);
    } catch (error) {
      if (error instanceof ApiError) {
        setServerError(MESSAGES["MSG-E-0001"]);
      } else {
        showToast("error", MESSAGES.ERROR_NETWORK);
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className={styles.page}>
      <div className={styles.card}>
        <div className={styles.brand}>
          <svg className={styles.logo} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 3v11.25A2.25 2.25 0 006 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0118 16.5h-2.25m-7.5 0h7.5m-7.5 0l-1 3m8.5-3l1 3m0 0l.5 1.5m-.5-1.5h-9.5m0 0l-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6" />
          </svg>
          <span className={styles.appName}>alpha-mind</span>
        </div>
        <h1 className={styles.title}>ログイン</h1>

        {serverError && (
          <div className={styles.errorBanner} role="alert">
            <svg className={styles.errorIcon} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
            </svg>
            {serverError}
          </div>
        )}

        <form className={styles.form} onSubmit={handleSubmit} noValidate>
          <TextInput
            label="メールアドレス"
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            error={errors.email}
            placeholder="user@example.com"
            autoComplete="email"
            required
          />
          <TextInput
            label="パスワード"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            error={errors.password}
            placeholder="パスワードを入力"
            autoComplete="current-password"
            required
          />
          <div className={styles.submitButton}>
            <Button type="submit" fullWidth loading={loading}>
              ログイン
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
}
