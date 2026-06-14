///| PageLayout organism (header + sidebar + main content shell).
///|
///| The authenticated application shell: composes the `app_header` and `sidebar`
///| organisms around a `<main>` content region. The main region is offset by
///| `--header-height` (top) and `--sidebar-width` (left) so it never sits behind
///| the fixed chrome (design-system anti-pattern: content hidden behind fixed
///| navbars). Pages pass their own page-specific content as `body`. An optional
///| `page_title` renders an `<h1>` at the top of the main region. The whole shell
///| stretches to the full viewport with the page background.
///|
///| Ref: documents/外部設計/screens/画面外部設計_共通.md §6.1 (レイアウト),
///|      design-system/alpha-mind/MASTER.md (no content hidden behind fixed navbars),
///|      CLAUDE.md (--header-height, --sidebar-width)

///|
/// Render the authenticated page shell (header + sidebar + main).
///
/// - `current_path`: active route path; passed to the sidebar for the active
///   highlight.
/// - `body`: the page-specific content nodes rendered inside `<main>`.
/// - `page_title`: optional page heading rendered as an `<h1>` above the body
///   (empty → omitted; the page renders its own heading).
/// - `app_name`: brand text for the header (default "alpha-mind").
/// - `user_name`: signed-in user's display name for the header (empty → omitted).
/// - `user_role`: the user's role label for the header badge (empty → omitted).
/// - `current_time`: optional clock text for the header.
/// - `nav_items`: navigation items for the sidebar (default: the canonical
///   primary nav).
pub fn page_layout(
  current_path~ : String,
  body~ : Array[@luna.Node[Unit, String]],
  page_title~ : String = "",
  app_name~ : String = "alpha-mind",
  user_name~ : String = "",
  user_role~ : String = "",
  current_time~ : String = "",
  nav_items~ : Array[NavItem] = primary_nav_items(),
) -> @luna.Node[Unit, String] {
  let header = app_header(
    app_name~,
    user_name~,
    user_role~,
    current_time~,
  )
  let side = sidebar(current_path~, items=nav_items)
  let main_children : Array[@luna.Node[Unit, String]] = []
  if page_title != "" {
    main_children.push(
      @atoms.heading_atom(
        page_title,
        level=H1,
        extra_style="margin-bottom:var(--space-lg,24px);",
      ),
    )
  }
  for node in body {
    main_children.push(node)
  }
  let main = main_(
    attrs=[("role", @luna.attr_static("main"))],
    style="margin-top:" +
      header_height +
      ";margin-left:" +
      sidebar_width +
      ";min-height:calc(100vh - " +
      header_height +
      ");padding:var(--space-lg,24px) var(--space-xl,32px);box-sizing:border-box;" +
      font_ui,
    main_children,
  )
  div(
    style="min-height:100vh;background:" +
      color_background +
      ";color:" +
      color_text +
      ";" +
      font_ui,
    [header, side, main],
  )
}
