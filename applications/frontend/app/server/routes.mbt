///| Route Definitions using SolRoutes
///|
///| This is the single source of truth for all routes.
///| Uses typed handlers instead of string-based component IDs.
///|
/// Application routes - defines all pages and API endpoints.
/// Page handlers (SCR-000..SCR-007) are added in their respective
/// presentation-layer issues (#75-82); the domain layer (#71) only
/// establishes the routing skeleton with a health endpoint.
pub fn routes() -> Array[@router.SolRoutes] {
  [
    @router.SolRoutes::WithMiddleware(
      middleware=[@mw.security_headers_relaxed(), @mw.logger()],
      children=[
        @router.SolRoutes::Get(
          path="/api/health",
          handler=@router.ApiHandler(api_health),
        ),
        // SCR-000: 認証ページ (public, no auth required)
        @router.SolRoutes::Page(
          path="/login",
          handler=@router.PageHandler(login_page),
          title="ログイン — alpha-mind",
          meta=[],
          revalidate=None,
          cache=None,
        ),
        // SCR-001: ダッシュボード (authenticated)
        @router.SolRoutes::Page(
          path="/dashboard",
          handler=@router.PageHandler(dashboard_page),
          title="ダッシュボード — alpha-mind",
          meta=[],
          revalidate=None,
          cache=None,
        ),
        // SCR-002: 戦略設定 (authenticated, admin)
        @router.SolRoutes::Page(
          path="/settings/strategy",
          handler=@router.PageHandler(strategy_page),
          title="戦略設定 — alpha-mind",
          meta=[],
          revalidate=None,
          cache=None,
        ),
        // SCR-003: 注文管理 (authenticated)
        @router.SolRoutes::Page(
          path="/orders",
          handler=@router.PageHandler(orders_page),
          title="注文管理 — alpha-mind",
          meta=[],
          revalidate=None,
          cache=None,
        ),
        // SCR-004: 監査ログ (authenticated)
        @router.SolRoutes::Page(
          path="/audit",
          handler=@router.PageHandler(audit_page),
          title="監査ログ — alpha-mind",
          meta=[],
          revalidate=None,
          cache=None,
        ),
        // SCR-005: モデル検証 (authenticated)
        @router.SolRoutes::Page(
          path="/models/validation",
          handler=@router.PageHandler(models_page),
          title="モデル検証 — alpha-mind",
          meta=[],
          revalidate=None,
          cache=None,
        ),
      ],
    ),
  ]
}

///|
/// API handler: health check
async fn api_health(_props : @router.PageProps) -> Json {
  { "status": "ok" }
}

///|
/// Root HTML template - customize the document structure.
/// Available placeholders:
/// - __LUNA_TITLE__   : Page title
/// - __LUNA_PRELOAD__ : Modulepreload tags
/// - __LUNA_HEAD__    : Custom head HTML (styles, meta, etc.)
/// - __LUNA_MAIN__    : Main content
const ROOT : String =
  #|<!DOCTYPE html>
  #|<html lang="ja">
  #|<head>
  #|  <meta charset="UTF-8">
  #|  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  #|  <title>__LUNA_TITLE__</title>
  #|  __LUNA_PRELOAD__
  #|  __LUNA_HEAD__
  #|</head>
  #|<body>
  #|  <div id="__sol__">__LUNA_MAIN__</div>
  #|</body>
  #|</html>

///|
/// Router configuration
pub fn config() -> @router.RouterConfig {
  @router.RouterConfig::default()
  .with_root_template(ROOT)
  .with_default_head(head())
  .with_loader_url("/static/loader.js")
}

///|
/// Create action registry for the application
pub fn action_registry() -> @action.ActionRegistry {
  @action.ActionRegistry::new(allowed_origins=["http://localhost:7777"])
}
