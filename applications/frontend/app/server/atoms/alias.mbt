///| Element DSL imports for Atoms (Atomic Design — smallest reusable SSR primitives).
///|
///| Atoms are server-rendered VNode (`@luna.Node[Unit, String]`) primitives.
///| They carry no event handlers (those live in client Islands); pages and
///| Islands compose these atoms. Styling uses inline `style` strings backed by
///| design-system CSS variables (--color-*, --space-*, --shadow-*, --radius-*).
///| No Tailwind.
using @server_dom {
  div,
  span,
  button,
  input,
  label,
  h1,
  h2,
  h3,
  p,
  svg,
  svg_path,
  svg_circle,
  text,
}
