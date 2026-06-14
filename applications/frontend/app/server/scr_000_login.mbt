///| SCR-000 認証ページ (/login) — SSR page handler
///|
///| Server component: renders the login page with the login form Island.
///| The Island (`login_form`) is hydrated client-side after the page loads.
///|
///| Design:
///|  - R-01 Header: アプリ名 (SSR)
///|  - R-02 LoginFormIsland: email/password 入力フォーム (Island: app/client/login_form.mbt)
///|  - R-03 エラー領域: Island 内で管理
///|
///| Ref: documents/外部設計/screens/SCR-000_認証.md

///|
/// Server page handler for /login.
/// Embeds the login_form Island with the BFF base URL from the environment.
pub async fn login_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  let bff_base_url = get_bff_base_url()
  let form_props : @types.LoginFormProps = { bff_base_url, }

  // SSR placeholder matching the Island structure for progressive enhancement.
  // loader.js hydrates the Island on top of this placeholder.
  let ssr_placeholder = form(
    style="display:flex;flex-direction:column;gap:24px;",
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
          ),
        ],
      ),
      button(
        attrs=[
          ("type", @luna.attr_static("submit")),
          (
            "style",
            @luna.attr_static(
              "background:var(--color-cta,#22C55E);color:#fff;border:none;border-radius:6px;padding:12px 24px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;width:100%;",
            ),
          ),
        ],
        [text("ログイン")],
      ),
    ],
  )

  let page_content = div(
    style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:var(--color-background,#020617);",
    [
      div(
        style="background:var(--color-secondary,#1E293B);padding:64px 48px;border-radius:12px;box-shadow:0 20px 25px rgba(0,0,0,0.15);width:100%;max-width:400px;box-sizing:border-box;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.75rem;font-weight:700;text-align:center;margin:0 0 4px;",
            [text("alpha-mind")],
          ),
          p(
            style="color:var(--color-cta,#22C55E);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;text-align:center;margin:0 0 48px;letter-spacing:0.05em;",
            [text("AI 投資運用プラットフォーム")],
          ),
          @server_dom.client(@types.login_form(form_props), [ssr_placeholder]),
        ],
      ),
    ],
  )

  @server_dom.ServerNode::sync(page_content)
}

///|
/// Read the BFF base URL from the environment variable BFF_BASE_URL.
/// Falls back to http://localhost:8080 for local development.
fn get_bff_base_url() -> String {
  ffi_get_env("BFF_BASE_URL", "http://localhost:8080")
}

///|
extern "js" fn ffi_get_env(key : String, default_val : String) -> String =
  #| (key, default_val) => {
  #|   try {
  #|     return globalThis?.process?.env?.[key] ?? default_val;
  #|   } catch {
  #|     return default_val;
  #|   }
  #| }
