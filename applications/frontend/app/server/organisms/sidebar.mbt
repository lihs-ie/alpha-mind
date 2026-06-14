///| Sidebar organism (fixed left primary navigation).
///|
///| The left-fixed navigation required by the common-screen spec (§6.1:
///| ナビゲーション — 左サイド固定). It is exactly `--sidebar-width` wide, starts
///| below the fixed header and sits at the sticky z-layer. It renders the
///| primary-navigation items (`navigation.mbt`) as an accessible list of links,
///| highlighting the item whose path matches the current route (`aria-current=
///| "page"` + CTA-tinted background). Server component: links are plain anchors so
///| navigation works without JS.
///|
///| Ref: documents/外部設計/screens/画面外部設計_共通.md §6.1 (ナビゲーション),
///|      CLAUDE.md (--sidebar-width, --header-height, Z-index)

///|
/// Render the fixed left sidebar navigation.
///
/// - `current_path`: the active route path; the matching nav item is highlighted
///   and marked `aria-current="page"`.
/// - `items`: navigation items to render (default: the canonical primary nav).
/// - `extra_style`: caller-appended inline style on the aside element.
pub fn sidebar(
  current_path~ : String,
  items~ : Array[NavItem] = primary_nav_items(),
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let links = items.map(fn(item) { nav_link(item, current_path) })
  let list = ul(
    attrs=[("role", @luna.attr_static("list"))],
    style="list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:4px;",
    links,
  )
  let nav_node = nav(
    attrs=[("aria-label", @luna.attr_static("メインナビゲーション"))],
    style="padding:var(--space-md,16px) var(--space-sm,8px);",
    [list],
  )
  aside(
    attrs=[("aria-label", @luna.attr_static("サイドバー"))],
    style="position:fixed;top:" +
      header_height +
      ";left:0;bottom:0;width:" +
      sidebar_width +
      ";z-index:" +
      z_sticky +
      ";overflow-y:auto;box-sizing:border-box;" +
      surface_bg +
      "border-right:1px solid " +
      color_border +
      ";" +
      transition +
      extra_style,
    [nav_node],
  )
}

///|
/// Render a single navigation link, highlighted when active.
fn nav_link(
  item : NavItem,
  current_path : String,
) -> @luna.Node[Unit, String] {
  let active = item.path == current_path
  let active_style = if active {
    "background:rgba(34,197,94,0.12);color:" +
    color_cta +
    ";border-left:3px solid " +
    color_cta +
    ";"
  } else {
    "color:" + color_text_muted + ";border-left:3px solid transparent;"
  }
  let mut link_attrs : Array[(String, @luna.Attr[Unit, String])] = [
    ("data-active", @luna.attr_static(if active { "true" } else { "false" })),
  ]
  if active {
    link_attrs = link_attrs +
      [("aria-current", @luna.attr_static("page"))]
  }
  let link = a(
    href=item.path,
    attrs=link_attrs,
    style="display:block;padding:10px 12px;border-radius:var(--radius-sm,6px);font-size:0.875rem;font-weight:500;text-decoration:none;cursor:pointer;" +
      font_ui +
      transition +
      active_style,
    [text(item.label)],
  )
  li([link])
}
