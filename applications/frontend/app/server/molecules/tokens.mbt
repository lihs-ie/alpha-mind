///| Design-system token aliases for Molecules.

///|

///| Re-exposes the `@atoms` design tokens under short local names so molecule

///| code stays readable and stays consistent with the atom layer's colour /

///| typography / motion language. Spacing follows the design-system `--space-*`

///| scale (xs 4 / sm 8 / md 16 / lg 24 / xl 32) via CSS variables with px

///| fallbacks, and elevation follows `--shadow-*`.

///|

///| Ref: design-system/alpha-mind/MASTER.md (Spacing Variables, Shadow Depths)

///|
/// UI font stack (shared with atoms).
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
/// Card / surface background, backed by --color-surface.
pub let surface_bg : String = "background:var(--color-surface,#1E293B);"

///|
/// Card border-radius, backed by --radius-md.
pub let radius_md : String = "border-radius:var(--radius-md,12px);"

///|
/// Small border-radius, backed by --radius-sm.
pub let radius_sm : String = "border-radius:var(--radius-sm,6px);"

///|
/// Card elevation, backed by --shadow-md.
pub let shadow_md : String = "box-shadow:var(--shadow-md,0 4px 6px rgba(0,0,0,0.1));"

///|
/// Modal / dropdown elevation, backed by --shadow-lg.
pub let shadow_lg : String = "box-shadow:var(--shadow-lg,0 10px 15px rgba(0,0,0,0.1));"

///|
/// Standard internal padding, backed by --space-lg (24px).
pub let pad_lg : String = "padding:var(--space-lg,24px);"

///|
/// Medium gap, backed by --space-md (16px).
pub let gap_md : String = "gap:var(--space-md,16px);"
