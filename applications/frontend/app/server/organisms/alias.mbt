///| Element DSL imports for Organisms (Atomic Design — composite SSR sections).
///|
///| Organisms are the largest reusable SSR units: full page chrome (AppHeader,
///| Sidebar, PageLayout), data sections (DataTable, OrderTable, AuditLogTable),
///| forms (FormSection), the operations StatusPanel and the Modal shell. They are
///| built by composing `@atoms` primitives and `@molecules` units, never by
///| re-implementing them. Like the lower layers they are pure server-rendered
///| VNodes (`@luna.Node[Unit, String]`): no event handlers (those live in client
///| Islands). Styling uses inline `style` strings backed by the design-system CSS
///| variables (--color-*, --space-*, --shadow-*, --radius-*, --header-height,
///| --sidebar-width, --z-*). No Tailwind.
///|
///| Ref: design-system/alpha-mind/MASTER.md, Issue #85 (Organisms)
using @server_dom {
  div,
  span,
  a,
  nav,
  aside,
  header_,
  main_,
  ul,
  li,
  text,
}
