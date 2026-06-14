///| AppHeader organism (fixed top application header).
///|
///| The fixed top bar required by the common-screen spec (§6.1: ヘッダー固定 —
///| アプリ名、現在時刻、ユーザーメニュー). It spans the full width, sits at the
///| sticky z-layer and is exactly `--header-height` tall. It shows the app name on
///| the left and, on the right, an optional clock slot and the signed-in user's
///| name with their role badge (`@atoms.badge_atom`). Server component: any user
///| menu interactions are wired by a client Island; this organism renders the
///| accessible structure.
///|
///| Ref: documents/外部設計/screens/画面外部設計_共通.md §6.1 (ヘッダー),
///|      CLAUDE.md (--header-height, Z-index)

///|
/// Render the fixed application header.
///
/// - `app_name`: brand text on the left (default "alpha-mind").
/// - `user_name`: signed-in user's display name (empty → user area omitted).
/// - `user_role`: the user's role label rendered as a badge (e.g. "admin" /
///   "viewer"); empty → no role badge.
/// - `current_time`: optional clock text rendered in the monospace face
///   (empty → omitted). The live ticking is an Island concern; SSR shows the
///   server-rendered snapshot.
/// - `extra_style`: caller-appended inline style on the header element.
pub fn app_header(
  app_name~ : String = "alpha-mind",
  user_name~ : String = "",
  user_role~ : String = "",
  current_time~ : String = "",
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let brand = span(
    style="color:" +
      color_text +
      ";font-size:1.0625rem;font-weight:700;letter-spacing:0.01em;" +
      font_ui,
    [text(app_name)],
  )
  let right_children : Array[@luna.Node[Unit, String]] = []
  if current_time != "" {
    right_children.push(
      span(
        attrs=[("data-role", @luna.attr_static("clock"))],
        style="color:" +
          color_text_muted +
          ";font-size:0.8125rem;" +
          font_mono,
        [text(current_time)],
      ),
    )
  }
  if user_name != "" {
    let user_children : Array[@luna.Node[Unit, String]] = [
      span(
        style="color:" + color_text + ";font-size:0.875rem;" + font_ui,
        [text(user_name)],
      ),
    ]
    if user_role != "" {
      user_children.push(@atoms.badge_atom(user_role, variant=Info))
    }
    right_children.push(
      div(
        attrs=[
          ("data-role", @luna.attr_static("user-menu")),
          ("aria-label", @luna.attr_static("ユーザーメニュー")),
        ],
        style="display:flex;align-items:center;gap:8px;cursor:pointer;" +
          transition,
        user_children,
      ),
    )
  }
  let right = div(
    style="display:flex;align-items:center;gap:var(--space-lg,24px);",
    right_children,
  )
  header_(
    attrs=[("role", @luna.attr_static("banner"))],
    style="position:fixed;top:0;left:0;right:0;height:" +
      header_height +
      ";z-index:" +
      z_sticky +
      ";display:flex;align-items:center;justify-content:space-between;padding:0 var(--space-lg,24px);box-sizing:border-box;" +
      surface_bg +
      "border-bottom:1px solid " +
      color_border +
      ";" +
      transition +
      extra_style,
    [brand, right],
  )
}
