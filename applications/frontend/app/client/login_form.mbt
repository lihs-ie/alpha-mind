///| Login Form Island Component (SCR-000)
///|
///| Interactive login form with email/password validation and BFF authentication.
///| This is a client component: it runs in the browser after hydration.
///|
///| Design rules:
///|  - No Tailwind CSS. Styles use inline style strings backed by design-system
///|    CSS variables (--color-*, --space-*, --shadow-*, --radius-*).
///|  - Validation: email required + format, password required.
///|  - On success: redirect to /dashboard.
///|  - On failure: show MSG-E-0001 error message.
///|  - Accessibility: aria-live region for errors, logical tab order.

///|
/// Props passed from the server (SSR initial state).
pub(all) struct LoginFormProps {
  bff_base_url : String
} derive(ToJson, FromJson)

///|
/// Login form Island component.
pub fn login_form(props : LoginFormProps) -> DomNode {
  let email = @signal.signal("")
  let password = @signal.signal("")
  let error_message = @signal.signal("")
  let button_text = @signal.signal("ログイン")

  let on_email_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    email.set(target.value)
    error_message.set("")
  }

  let on_password_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    password.set(target.value)
    error_message.set("")
  }

  let handle_submit : @element.FormHandler = fn(e) {
    e.preventDefault()
    let email_val = email.get()
    let password_val = password.get()
    // Client-side validation
    if email_val == "" {
      error_message.set("メールアドレスを入力してください")
      return
    }
    if not(ffi_validate_email(email_val)) {
      error_message.set("メールアドレス形式で入力してください")
      return
    }
    if password_val == "" {
      error_message.set("パスワードを入力してください")
      return
    }
    button_text.set("ログイン中...")
    error_message.set("")
    let base_url = props.bff_base_url
    let btn = button_text
    let err = error_message
    ffi_fetch_login(
      base_url,
      email_val,
      password_val,
      fn(success, message) {
        if success {
          ffi_redirect("/dashboard")
        } else {
          btn.set("ログイン")
          err.set(message)
        }
      },
    )
  }

  div(
    style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:var(--color-background,#020617);",
    [
      div(
        style="background:var(--color-secondary,#1E293B);padding:var(--space-3xl,64px) var(--space-2xl,48px);border-radius:12px;box-shadow:0 20px 25px rgba(0,0,0,0.15);width:100%;max-width:400px;box-sizing:border-box;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.75rem;font-weight:700;text-align:center;margin:0 0 4px;",
            [text("alpha-mind")],
          ),
          p(
            style="color:var(--color-cta,#22C55E);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;text-align:center;margin:0 0 48px;letter-spacing:0.05em;",
            [text("AI 投資運用プラットフォーム")],
          ),
          form(
            style="display:flex;flex-direction:column;gap:24px;",
            on=events().submit(handle_submit),
            [
              div(
                style="display:flex;flex-direction:column;gap:4px;",
                [
                  label(
                    for_="email",
                    style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                    [text("メールアドレス")],
                  ),
                  input(
                    type_="email",
                    id="email",
                    name="email",
                    placeholder="operator@example.com",
                    style="background:var(--color-primary,#0F172A);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 16px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;width:100%;box-sizing:border-box;",
                    on=events().input(on_email_input),
                  ),
                ],
              ),
              div(
                style="display:flex;flex-direction:column;gap:4px;",
                [
                  label(
                    for_="password",
                    style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                    [text("パスワード")],
                  ),
                  input(
                    type_="password",
                    id="password",
                    name="password",
                    placeholder="••••••••",
                    style="background:var(--color-primary,#0F172A);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 16px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;width:100%;box-sizing:border-box;",
                    on=events().input(on_password_input),
                  ),
                ],
              ),
              div(
                attrs=[
                  ("role", @element.AttrString("alert")),
                  ("aria-live", @element.AttrString("polite")),
                  (
                    "style",
                    @element.AttrString(
                      "min-height:1.25rem;color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;text-align:center;",
                    ),
                  ),
                ],
                [text_of(error_message)],
              ),
              button(
                attrs=[
                  ("type", @element.AttrString("submit")),
                  (
                    "style",
                    @element.AttrString(
                      "background:var(--color-cta,#22C55E);color:#fff;border:none;border-radius:6px;padding:12px 24px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;width:100%;",
                    ),
                  ),
                ],
                [text_of(button_text)],
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
/// Validate email format (must contain @ and a dot after @).
extern "js" fn ffi_validate_email(email : String) -> Bool =
  #| (email) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)

///|
/// Perform BFF POST /auth/login and invoke callback with (success, message).
extern "js" fn ffi_fetch_login(
  base_url : String,
  email : String,
  password : String,
  on_result : (Bool, String) -> Unit
) -> Unit =
  #| (base_url, email, password, on_result) => {
  #|   fetch(base_url + '/auth/login', {
  #|     method: 'POST',
  #|     headers: { 'Content-Type': 'application/json' },
  #|     body: JSON.stringify({ email, password }),
  #|   })
  #|   .then(res => res.json().then(body => ({ ok: res.ok, body })))
  #|   .then(({ ok, body }) => {
  #|     if (ok && body.accessToken) {
  #|       try { sessionStorage.setItem('__alpha_mind_token__', body.accessToken); } catch {}
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (body && body.detail) || '認証に失敗しました。入力内容を確認してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '認証に失敗しました。入力内容を確認してください。'));
  #| }

///|
extern "js" fn ffi_redirect(url : String) -> Unit =
  #| (url) => { window.location.href = url; }
