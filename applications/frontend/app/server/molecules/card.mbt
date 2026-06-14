///| Card molecule (surface container with optional header / footer).

///|

///| A surface panel used for dashboard cards and detail cards. Composes the

///| `@atoms.heading_atom` for the title and arbitrary child nodes for the body.

///| Uses the design-system surface background, `--radius-md` corners, `--shadow-md`

///| elevation and `--space-lg` padding. The `stat_card` variant is a compact

///| metric tile (label + monospaced value + optional delta) for dashboards.

///|

///| Ref: design-system/alpha-mind/MASTER.md (Cards, Spacing, Shadows)

///| Ref: documents/外部設計/screens/SCR-001_ダッシュボード.md

///|
/// Render a card.
///
/// - `title`: optional card heading (empty → header omitted).
/// - `actions`: optional nodes rendered at the right of the header (e.g. buttons).
/// - `body`: the card body content nodes.
/// - `footer`: optional nodes rendered below a separator at the card bottom.
/// - `extra_style`: caller-appended inline style on the card surface.
pub fn card(
  body : Array[@luna.Node[Unit, String]],
  title? : String = "",
  actions? : Array[@luna.Node[Unit, String]] = [],
  footer? : Array[@luna.Node[Unit, String]] = [],
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  let children : Array[@luna.Node[Unit, String]] = []
  if title != "" || actions.length() > 0 {
    let title_node = if title != "" {
      @atoms.heading_atom(title, level=H3)
    } else {
      span(style="display:none;", [])
    }
    let header = div(
      style="display:flex;align-items:center;justify-content:space-between;margin-bottom:var(--space-md,16px);" +
        gap_md,
      [
        title_node,
        div(style="display:flex;align-items:center;gap:8px;", actions),
      ],
    )
    children.push(header)
  }
  children.push(div(style="display:flex;flex-direction:column;" + gap_md, body))
  if footer.length() > 0 {
    let footer_node = div(
      style="display:flex;align-items:center;gap:8px;margin-top:var(--space-lg,24px);padding-top:var(--space-md,16px);border-top:1px solid " +
        color_border +
        ";",
      footer,
    )
    children.push(footer_node)
  }
  div(
    style=surface_bg +
      radius_md +
      shadow_md +
      pad_lg +
      "border:1px solid " +
      color_border +
      ";box-sizing:border-box;" +
      transition +
      extra_style,
    children,
  )
}

///|
/// Render a compact stat / metric tile (a dashboard-oriented Card variant).
///
/// - `label_text`: metric name (muted, above the value).
/// - `value`: the metric value, rendered in the monospace numeric face.
/// - `delta`: optional change indicator (e.g. "+1.2%"); coloured by `delta_kind`.
/// - `delta_kind`: tints the delta (`Neutral` / `Profit` / `Loss`).
/// - `extra_style`: caller-appended inline style on the card surface.
pub fn stat_card(
  label_text : String,
  value : String,
  delta? : String = "",
  delta_kind? : StatDelta = Neutral,
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  let delta_node = if delta != "" {
    let delta_color = match delta_kind {
      Neutral => color_text_muted
      Profit => color_cta
      Loss => color_danger
    }
    span(
      style="font-size:0.8125rem;font-weight:600;color:" +
        delta_color +
        ";" +
        font_mono,
      [text(delta)],
    )
  } else {
    span(style="display:none;", [])
  }
  div(
    style=surface_bg +
      radius_md +
      shadow_md +
      "padding:var(--space-md,16px);border:1px solid " +
      color_border +
      ";box-sizing:border-box;display:flex;flex-direction:column;gap:6px;" +
      transition +
      extra_style,
    [
      span(
        style="color:" +
          color_text_muted +
          ";font-size:0.75rem;font-weight:600;letter-spacing:0.04em;text-transform:uppercase;" +
          font_ui,
        [text(label_text)],
      ),
      div(style="display:flex;align-items:baseline;gap:8px;", [
        span(
          style="color:" +
            color_text +
            ";font-size:1.5rem;font-weight:700;" +
            font_mono,
          [text(value)],
        ),
        delta_node,
      ]),
    ],
  )
}

///|
/// Tint for a stat card delta indicator.
pub(all) enum StatDelta {
  Neutral
  Profit
  Loss
}
