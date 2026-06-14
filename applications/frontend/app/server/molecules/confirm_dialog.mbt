///| ConfirmDialog molecule (confirmation modal).

///|

///| A confirmation modal shown before destructive operations (承認 / 却下 /

///| kill switch 変更) per the common-screen spec. Renders a dim overlay plus a

///| centred dialog with `role="dialog"` + `aria-modal="true"` and an

///| `aria-labelledby` / `aria-describedby` association. The visible focus trap is

///| enforced at runtime by the client Island; this server molecule provides the

///| accessible structure, the cancel / confirm buttons (`@atoms.button_atom`) and

///| the dialog title (`@atoms.heading_atom`).

///|

///| Ref: documents/外部設計/screens/画面外部設計_共通.md §6.2 (確認モーダル: フォーカストラップ必須)

///|
/// The kind of confirmation, which colours the confirm button.
pub(all) enum ConfirmKind {
  /// Neutral / informational confirmation (CTA-coloured confirm button).
  Default
  /// Destructive confirmation (danger-coloured confirm button).
  Destructive
}

///|
/// Render a confirmation dialog.
///
/// - `dialog_id`: id of the dialog element (the Island toggles its visibility).
/// - `title`: dialog heading.
/// - `message`: explanatory body text.
/// - `confirm_label`: confirm button label (default "確認").
/// - `cancel_label`: cancel button label (default "キャンセル").
/// - `kind`: `Default` or `Destructive` (tints the confirm button).
/// - `open`: whether the dialog is initially visible (SSR default closed).
pub fn confirm_dialog(
  dialog_id : String,
  title : String,
  message : String,
  confirm_label? : String = "確認",
  cancel_label? : String = "キャンセル",
  kind? : ConfirmKind = Default,
  open? : Bool = false,
) -> @luna.Node[Unit, String] {
  let title_id = dialog_id + "-title"
  let desc_id = dialog_id + "-desc"
  let display = if open { "flex" } else { "none" }
  let confirm_variant : @atoms.ButtonVariant = match kind {
    Default => Primary
    Destructive => Danger
  }
  let dialog = div(
    id=dialog_id + "-panel",
    attrs=[
      ("role", @luna.attr_static("dialog")),
      ("aria-modal", @luna.attr_static("true")),
      ("aria-labelledby", @luna.attr_static(title_id)),
      ("aria-describedby", @luna.attr_static(desc_id)),
    ],
    style="background:#fff;color:#0F172A;" +
      radius_md +
      shadow_lg +
      "padding:var(--space-xl,32px);max-width:480px;width:90%;box-sizing:border-box;display:flex;flex-direction:column;gap:var(--space-md,16px);" +
      font_ui,
    [
      div(
        id=title_id,
        style="font-size:1.125rem;font-weight:700;color:#0F172A;",
        [text(title)],
      ),
      div(
        id=desc_id,
        style="font-size:0.875rem;line-height:1.5;color:#334155;",
        [text(message)],
      ),
      div(
        style="display:flex;justify-content:flex-end;gap:8px;margin-top:8px;",
        [
          @atoms.button_atom(cancel_label, variant=Secondary, size=Medium),
          @atoms.button_atom(
            confirm_label,
            variant=confirm_variant,
            size=Medium,
          ),
        ],
      ),
    ],
  )
  div(
    id=dialog_id,
    attrs=[
      (
        "data-dialog-open",
        @luna.attr_static(if open { "true" } else { "false" }),
      ),
    ],
    style="position:fixed;inset:0;z-index:var(--z-modal,40);display:" +
      display +
      ";align-items:center;justify-content:center;background:rgba(0,0,0,0.5);backdrop-filter:blur(4px);",
    [dialog],
  )
}
