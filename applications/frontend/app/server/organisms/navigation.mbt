///| Navigation model shared by the AppHeader and Sidebar organisms.
///|
///| A `NavItem` is one primary-navigation destination (label + route path). The
///| canonical primary navigation (`primary_nav_items`) lists the authenticated
///| screens (SCR-001..SCR-007) in their menu order, matching the route paths
///| declared in `app/server/routes.mbt`. The Sidebar highlights the item whose
///| `path` matches the current route.
///|
///| Ref: documents/外部設計/screens/画面外部設計_共通.md §6.1 (ナビゲーション: 左サイド固定),
///|      app/server/routes.mbt (route paths), CLAUDE.md (画面一覧)

///|
/// A single primary-navigation destination.
pub(all) struct NavItem {
  /// Visible menu label.
  label : String
  /// Route path this item navigates to (matched against the current path for
  /// the active highlight).
  path : String
}

///|
/// The canonical primary navigation in menu order.
///
/// Mirrors the authenticated routes declared in `app/server/routes.mbt`
/// (/dashboard, /settings/strategy, /orders, /audit, /models/validation,
/// /insights, /hypotheses). Kept as a function (not a top-level `let`) so each
/// call returns a fresh array the caller may not mutate accidentally.
pub fn primary_nav_items() -> Array[NavItem] {
  [
    { label: "ダッシュボード", path: "/dashboard" },
    { label: "戦略設定", path: "/settings/strategy" },
    { label: "注文管理", path: "/orders" },
    { label: "監査ログ", path: "/audit" },
    { label: "モデル検証", path: "/models/validation" },
    { label: "インサイト管理", path: "/insights" },
    { label: "仮説ラボ", path: "/hypotheses" },
  ]
}
