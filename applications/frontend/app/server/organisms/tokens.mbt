///| Design-system token aliases + layout tokens for Organisms.
///|
///| Re-exposes the shared `@atoms` design tokens (colour / typography / motion)
///| and adds the layout-scale tokens specific to page chrome: the fixed header
///| height (`--header-height`, 56px), the left navigation width (`--sidebar-width`,
///| 240px) and the z-index layering system (`--z-dropdown`/`--z-sticky`/
///| `--z-overlay`/`--z-modal`/`--z-toast`). Every value references a design-system
///| CSS variable with a sensible fallback so organisms work before globals.css is
///| present and stay themable once it is.
///|
///| Ref: design-system/alpha-mind/MASTER.md (Spacing, Shadows),
///|      CLAUDE.md (レイアウト: --header-height 56px / --sidebar-width 240px, Z-index)

///|
/// UI font stack (shared with atoms/molecules).
pub let font_ui : String = @atoms.font_ui

///|
/// Monospace stack for numeric / code display.
pub let font_mono : String = @atoms.font_mono

///|
/// Standard transition (150-300ms; no instant state changes).
pub let transition : String = @atoms.transition

///|
/// Primary text colour.
pub let color_text : String = @atoms.color_text

///|
/// Muted/secondary text colour.
pub let color_text_muted : String = @atoms.color_text_muted

///|
/// Surface (card) background.
pub let color_surface : String = @atoms.color_surface

///|
/// CTA / accent (positive) colour.
pub let color_cta : String = @atoms.color_cta

///|
/// Subtle border colour on dark surfaces.
pub let color_border : String = @atoms.color_border

///|
/// Loss / danger colour.
pub let color_danger : String = @atoms.color_danger

///|
/// Warning colour.
pub let color_warning : String = @atoms.color_warning

///|
/// Info colour.
pub let color_info : String = @atoms.color_info

///|
/// Page background, backed by --color-background.
pub let color_background : String = "var(--color-background,#020617)"

///|
/// Fixed header height, backed by --header-height (56px).
pub let header_height : String = "var(--header-height,56px)"

///|
/// Left navigation width, backed by --sidebar-width (240px).
pub let sidebar_width : String = "var(--sidebar-width,240px)"

///|
/// Sticky-layer z-index (fixed header / sidebar), backed by --z-sticky (20).
pub let z_sticky : String = "var(--z-sticky,20)"

///|
/// Overlay-layer z-index (dimmed backdrops), backed by --z-overlay (30).
pub let z_overlay : String = "var(--z-overlay,30)"

///|
/// Modal-layer z-index, backed by --z-modal (40).
pub let z_modal : String = "var(--z-modal,40)"

///|
/// Surface background style fragment, backed by --color-surface.
pub let surface_bg : String = "background:var(--color-surface,#1E293B);"

///|
/// Card / surface radius, backed by --radius-md.
pub let radius_md : String = "border-radius:var(--radius-md,12px);"

///|
/// Small radius, backed by --radius-sm.
pub let radius_sm : String = "border-radius:var(--radius-sm,6px);"

///|
/// Card elevation, backed by --shadow-md.
pub let shadow_md : String = "box-shadow:var(--shadow-md,0 4px 6px rgba(0,0,0,0.1));"
