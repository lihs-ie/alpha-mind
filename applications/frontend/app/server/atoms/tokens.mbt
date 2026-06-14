///| Design-system tokens for Atoms.
///|
///| Centralizes the CSS-variable-backed values used across atoms so the colour,
///| typography and motion language stays consistent. Every value references a
///| design-system CSS variable with a dark-default fallback (OLED dark style),
///| so atoms are dark-mode friendly out of the box and themable via globals.css
///| overrides once a stylesheet exists.
///|
///| Ref: design-system/alpha-mind/MASTER.md (colours, typography, shadows, spacing)

///|
/// UI font stack (IBM Plex Sans per design system; Inter/Noto Sans JP as the
/// CLAUDE.md UI guidance — both honoured via the family list).
pub let font_ui : String = "font-family:'IBM Plex Sans','Inter','Noto Sans JP',sans-serif;"

///|
/// Monospace stack for numeric / code display (CLAUDE.md: 数値=JetBrains Mono).
pub let font_mono : String = "font-family:'JetBrains Mono','IBM Plex Sans',monospace;"

///|
/// Standard transition (150-300ms range — design-system requires no instant
/// state changes).
pub let transition : String = "transition:all 200ms ease;"

///|
/// Primary text colour.
pub let color_text : String = "var(--color-text,#F8FAFC)"

///|
/// Muted/secondary text colour.
pub let color_text_muted : String = "rgba(248,250,252,0.6)"

///|
/// Surface (card) background.
pub let color_surface : String = "var(--color-secondary,#1E293B)"

///|
/// CTA / accent (positive) colour.
pub let color_cta : String = "var(--color-cta,#22C55E)"

///|
/// Subtle border colour on dark surfaces.
pub let color_border : String = "rgba(248,250,252,0.15)"

///|
/// Loss / danger colour.
pub let color_danger : String = "#F87171"

///|
/// Warning colour.
pub let color_warning : String = "#EAB308"

///|
/// Info colour.
pub let color_info : String = "#818CF8"
