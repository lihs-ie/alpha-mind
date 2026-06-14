///| Modal organism (general overlay dialog: confirm or detail display).
///|
///| A general-purpose modal shell covering both the confirmation use (承認 / 却下
///| / kill switch 変更) and the detail-display use (e.g. an audit-log record's
///| payload). It renders a dimmed backdrop at the overlay z-layer and a centred
///| panel at the modal z-layer, with `role="dialog"` + `aria-modal="true"` and the
///| `aria-labelledby` / `aria-describedby` associations. The title uses
///| `@atoms.heading_atom`; arbitrary `body` nodes fill the content; the footer
///| renders the supplied action buttons. The focus trap is enforced at runtime by
///| the client Island; this organism provides the accessible structure and the
///| SSR (closed-by-default) snapshot.
///|
///| Ref: documents/外部設計/screens/画面外部設計_共通.md §6.2 (確認モーダル: フォーカストラップ必須),
///|      design-system/alpha-mind/MASTER.md (Modals), CLAUDE.md (Z-index: --z-overlay/--z-modal)

///|
/// Render a general modal dialog.
///
/// - `dialog_id`: id of the modal root (the Island toggles its visibility).
/// - `title`: the dialog heading.
/// - `body`: the dialog content nodes.
/// - `actions`: footer action buttons (e.g. cancel / confirm); empty → no footer.
/// - `open`: whether the modal is initially visible (SSR default closed).
/// - `extra_style`: caller-appended inline style on the modal panel.
pub fn modal(
  dialog_id : String,
  title : String,
  body : Array[@luna.Node[Unit, String]],
  actions~ : Array[@luna.Node[Unit, String]] = [],
  open~ : Bool = false,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let title_id = dialog_id + "-title"
  let desc_id = dialog_id + "-body"
  let display = if open { "flex" } else { "none" }
  let panel_children : Array[@luna.Node[Unit, String]] = [
    @atoms.heading_atom(title, level=H3, extra_style="color:#0F172A;"),
    div(
      id=desc_id,
      style="font-size:0.875rem;line-height:1.5;color:#334155;display:flex;flex-direction:column;gap:var(--space-md,16px);",
      body,
    ),
  ]
  if actions.length() > 0 {
    panel_children.push(
      div(
        style="display:flex;justify-content:flex-end;gap:8px;margin-top:8px;",
        actions,
      ),
    )
  }
  // The heading carries the labelledby id via a wrapper so SSR HTML exposes it.
  let panel = div(
    id=dialog_id + "-panel",
    attrs=[
      ("role", @luna.attr_static("dialog")),
      ("aria-modal", @luna.attr_static("true")),
      ("aria-labelledby", @luna.attr_static(title_id)),
      ("aria-describedby", @luna.attr_static(desc_id)),
    ],
    style="background:#fff;color:#0F172A;" +
      radius_md +
      "box-shadow:var(--shadow-xl,0 20px 25px rgba(0,0,0,0.15));padding:var(--space-xl,32px);max-width:560px;width:90%;max-height:85vh;overflow-y:auto;box-sizing:border-box;display:flex;flex-direction:column;gap:var(--space-md,16px);" +
      font_ui +
      extra_style,
    [
      // A hidden labelledby anchor mirroring the title text.
      span(
        id=title_id,
        style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);",
        [text(title)],
      ),
      ..panel_children,
    ],
  )
  div(
    id=dialog_id,
    attrs=[
      ("data-modal-open", @luna.attr_static(if open { "true" } else { "false" })),
    ],
    style="position:fixed;inset:0;z-index:" +
      z_modal +
      ";display:" +
      display +
      ";align-items:center;justify-content:center;background:rgba(0,0,0,0.5);backdrop-filter:blur(4px);",
    [panel],
  )
}

///|
/// Build the standard confirm/cancel footer actions for a modal.
///
/// - `confirm_label`: confirm button label (default "確認").
/// - `cancel_label`: cancel button label (default "キャンセル").
/// - `destructive`: tints the confirm button danger when true.
pub fn modal_confirm_actions(
  confirm_label~ : String = "確認",
  cancel_label~ : String = "キャンセル",
  destructive~ : Bool = false,
) -> Array[@luna.Node[Unit, String]] {
  let confirm_variant : @atoms.ButtonVariant = if destructive {
    Danger
  } else {
    Primary
  }
  [
    span(
      attrs=[("data-action", @luna.attr_static("cancel"))],
      style="display:inline-flex;",
      [@atoms.button_atom(cancel_label, variant=Secondary, size=Medium)],
    ),
    span(
      attrs=[("data-action", @luna.attr_static("confirm"))],
      style="display:inline-flex;",
      [@atoms.button_atom(confirm_label, variant=confirm_variant, size=Medium)],
    ),
  ]
}
