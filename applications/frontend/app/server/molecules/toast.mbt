///| Toast / Notification + RetryBanner molecules.

///|

///| `toast` renders a single notification (成功 / 警告 / 失敗) anchored top-right

///| per the common-screen spec, auto-dismissed after 5s by the client Island

///| (the timing is surfaced via `data-auto-dismiss-ms`). Success uses

///| `role="status"` (polite), warning / error use `role="alert"` (assertive).

///| `toast_region` is the fixed top-right live-region container that an Island

///| populates. `retry_banner` renders the API-failure banner with a retry action.

///| All convey meaning by an icon + text, never colour alone (§9 a11y).

///|

///| Ref: documents/外部設計/screens/画面外部設計_共通.md §6.2 (グローバルトースト: 5秒後に自動消去), §9 (a11y)

///|
/// Toast severity.
pub(all) enum ToastKind {
  Success
  Warning
  Error
}

///|
/// Render a single toast notification.
///
/// - `message`: the notification text.
/// - `kind`: severity (`Success` / `Warning` / `Error`).
/// - `auto_dismiss_ms`: auto-dismiss delay in ms surfaced to the Island (default 5000).
/// - `extra_style`: caller-appended inline style on the toast.
pub fn toast(
  message : String,
  kind? : ToastKind = Success,
  auto_dismiss_ms? : Int = 5000,
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  let (icon_name, accent, live_role) : (@atoms.IconName, String, String) = match
    kind {
    Success => (Check, color_cta, "status")
    Warning => (Warning, color_warning, "alert")
    Error => (Close, color_danger, "alert")
  }
  let icon = @atoms.icon_atom(icon_name, size="18", color=accent)
  div(
    attrs=[
      ("role", @luna.attr_static(live_role)),
      ("data-toast-kind", @luna.attr_static(toast_kind_label(kind))),
      ("data-auto-dismiss-ms", @luna.attr_static(auto_dismiss_ms.to_string())),
    ],
    style=surface_bg +
      radius_sm +
      shadow_lg +
      "display:flex;align-items:center;gap:8px;padding:12px 16px;border:1px solid " +
      accent +
      ";border-left:3px solid " +
      accent +
      ";color:" +
      color_text +
      ";font-size:0.875rem;min-width:240px;max-width:360px;box-sizing:border-box;" +
      font_ui +
      transition +
      extra_style,
    [icon, span(style="flex:1 1 auto;", [text(message)])],
  )
}

///|
/// Render the fixed top-right toast live-region container.
/// The Island appends / removes `toast` children here.
///
/// - `toasts`: initial toasts to render (usually empty at SSR time).
pub fn toast_region(
  toasts? : Array[@luna.Node[Unit, String]] = [],
) -> @luna.Node[Unit, String] {
  div(
    id="toast-region",
    attrs=[
      ("role", @luna.attr_static("region")),
      ("aria-label", @luna.attr_static("通知")),
      ("aria-live", @luna.attr_static("polite")),
    ],
    style="position:fixed;top:var(--space-md,16px);right:var(--space-md,16px);z-index:var(--z-toast,50);display:flex;flex-direction:column;gap:8px;",
    toasts,
  )
}

///|
/// Render the API-failure retry banner shown in the `error` state.
///
/// - `message`: the failure description.
/// - `retry_label`: retry button label (default "再試行").
/// - `extra_style`: caller-appended inline style on the banner.
pub fn retry_banner(
  message : String,
  retry_label? : String = "再試行",
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  div(
    attrs=[("role", @luna.attr_static("alert"))],
    style=radius_sm +
      "display:flex;align-items:center;justify-content:space-between;gap:var(--space-md,16px);padding:12px 16px;background:rgba(248,113,113,0.12);border:1px solid " +
      color_danger +
      ";color:" +
      color_danger +
      ";font-size:0.875rem;box-sizing:border-box;" +
      font_ui +
      extra_style,
    [
      div(style="display:flex;align-items:center;gap:8px;", [
        @atoms.icon_atom(Warning, size="18", color=color_danger),
        span([text(message)]),
      ]),
      @atoms.button_atom(retry_label, variant=Danger, size=Small),
    ],
  )
}

///|
/// Stable label for a toast kind (used for `data-toast-kind` and tests).
pub fn toast_kind_label(kind : ToastKind) -> String {
  match kind {
    Success => "success"
    Warning => "warning"
    Error => "error"
  }
}
