///| ReadModelProjection aggregate — BFF response projected to screen-specific view models.
///| INV-FE-004: no raw BFF DTO types held in this aggregate.

/// Screens that have a projection (SCR-002 settings screen is excluded — no projection needed).
pub(all) enum ProjectionScreen {
  Scr001
  Scr003
  Scr004
  Scr005
  Scr006
  Scr007
} derive(Eq, Show)

/// Status of the read model projection.
pub(all) enum ProjectionStatus {
  Initial
  Loading
  Ready
  Empty
  Error
  Disabled
} derive(Eq, Show)

/// Status of an individual projected item.
pub(all) enum ProjectionItemStatus {
  Created
  Rendered
  Stale
} derive(Eq, Show)

/// ViewItem entity — a displayable item in the projection.
pub struct ViewItem {
  identifier : String
} derive(Eq, Show)

/// ProjectionItem entity — tracks per-item rendering state.
pub struct ProjectionItem {
  identifier : String
  status : ProjectionItemStatus
} derive(Eq, Show)

/// Value object: summary data for the screen projection.
pub struct ViewSummary {
  title : String
  description : String?
} derive(Eq, Show)

/// Value object: pagination information.
pub struct Pagination {
  cursor : String?
  limit : Int
  hasNext : Bool
} derive(Eq, Show)

/// Value object: query criteria for projection retrieval.
pub struct QueryCriteria {
  from : String?
  to : String?
  status : String?
  cursor : String?
  limit : Int?
} derive(Eq, Show)

/// Value object: problem detail from BFF API (RFC 9457 compatible).
pub struct ApiProblem {
  status : Int
  reasonCode : @command.ReasonCode
  message : String
} derive(Show)

/// ReadModelProjection aggregate root.
/// INV-FE-004: fields contain only domain-defined view model types (no raw DTOs).
pub struct ReadModelProjection {
  identifier : String
  screen : ProjectionScreen
  status : ProjectionStatus
  items : Array[ViewItem]
  summary : ViewSummary?
  pagination : Pagination?
  updatedAt : String
} derive(Show)

/// Factory: create a ViewItem with the given identifier.
pub fn new_view_item(identifier : String) -> ViewItem {
  { identifier }
}

/// Factory: create a QueryCriteria with the given parameters.
pub fn new_query_criteria(
  from : String?,
  to : String?,
  status : String?,
  cursor : String?,
  limit : Int?
) -> QueryCriteria {
  { from, to, status, cursor, limit }
}

/// Factory: create a new ReadModelProjection in Initial state.
pub fn new_projection(
  identifier : String,
  screen : ProjectionScreen,
  updated_at : String
) -> ReadModelProjection {
  {
    identifier,
    screen,
    status: ProjectionStatus::Initial,
    items: [],
    summary: None,
    pagination: None,
    updatedAt: updated_at,
  }
}

/// Transition: begin loading the projection.
pub fn start_loading(
  projection : ReadModelProjection,
  updated_at : String
) -> ReadModelProjection {
  { ..projection, status: ProjectionStatus::Loading, updatedAt: updated_at }
}

/// Transition: apply refreshed items (→ Ready or Empty).
pub fn refresh_projection(
  projection : ReadModelProjection,
  items : Array[ViewItem],
  summary : ViewSummary?,
  pagination : Pagination?,
  updated_at : String
) -> ReadModelProjection {
  let new_status = if items.length() == 0 && summary == None {
    ProjectionStatus::Empty
  } else {
    ProjectionStatus::Ready
  }
  {
    ..projection,
    status: new_status,
    items,
    summary,
    pagination,
    updatedAt: updated_at,
  }
}

/// Transition: mark projection as failed.
pub fn fail_projection(
  projection : ReadModelProjection,
  updated_at : String
) -> ReadModelProjection {
  { ..projection, status: ProjectionStatus::Error, updatedAt: updated_at }
}

/// Transition: mark a ProjectionItem as rendered.
pub fn render_item(item : ProjectionItem) -> ProjectionItem {
  { ..item, status: ProjectionItemStatus::Rendered }
}

/// Transition: mark a ProjectionItem as stale.
pub fn mark_stale(item : ProjectionItem) -> ProjectionItem {
  { ..item, status: ProjectionItemStatus::Stale }
}
