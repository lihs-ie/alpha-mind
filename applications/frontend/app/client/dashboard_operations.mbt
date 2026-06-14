///| Dashboard Operations Island Component (SCR-001)
///|
///| Interactive emergency operations panel.
///| Handles runtime start/stop and kill switch toggle.
///| This is a client component: it runs in the browser after hydration.
///|
///| Operations:
///|  - A-0011 運用開始: POST /operations/runtime { action: "START" }
///|  - A-0012 運用停止: POST /operations/runtime { action: "STOP" }
///|  - A-0013 kill switch切替: POST /operations/kill-switch { enabled: <bool>, actionReasonCode, comment }
///|  - A-0014 手動サイクル実行: POST /commands/run-cycle (when kill switch is disabled)
///|
///| Ref: documents/外部設計/screens/SCR-001_ダッシュボード.md
///| Ref: documents/外部設計/state/状態遷移設計.md

///|
/// Props passed from the server (SSR initial state).
pub(all) struct DashboardOperationsProps {
  bff_base_url : String
  initial_runtime_state : String
  initial_kill_switch_enabled : Bool
} derive(ToJson, FromJson)

///|
/// Dashboard operations Island component.
pub fn dashboard_operations(props : DashboardOperationsProps) -> DomNode {
  let runtime_state = @signal.signal(props.initial_runtime_state)
  let kill_switch_enabled = @signal.signal(props.initial_kill_switch_enabled)
  let status_message = @signal.signal("")
  let status_is_error = @signal.signal(false)
  let status_is_warning = @signal.signal(false)
  let is_loading = @signal.signal(false)

  // Kill switch confirmation modal state
  let show_kill_switch_modal = @signal.signal(false)
  let kill_switch_reason_code = @signal.signal("")
  let kill_switch_comment = @signal.signal("")
  let kill_switch_validation_error = @signal.signal("")

  // ── Runtime start/stop ──────────────────────────────────────────────────────

  let handle_runtime_toggle : @element.MouseHandler = fn(_e) {
    if is_loading.get() {
      return
    }
    let current_state = runtime_state.get()
    let action = if current_state == "RUNNING" { "STOP" } else { "START" }
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let rt = runtime_state
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    let is_warn = status_is_warning
    ffi_post_runtime(
      base_url,
      action,
      fn(success, new_state, error_message) {
        loading.set(false)
        if success {
          rt.set(new_state)
          let info_msg = if new_state == "RUNNING" {
            "✓ 運用を開始しました。"
          } else {
            "✓ 運用を停止しました。"
          }
          is_err.set(false)
          is_warn.set(false)
          msg.set(info_msg)
        } else {
          is_err.set(true)
          is_warn.set(false)
          msg.set("✗ " + error_message)
        }
      },
    )
  }

  // ── Kill switch ─────────────────────────────────────────────────────────────

  let handle_kill_switch_open_modal : @element.MouseHandler = fn(_e) {
    if is_loading.get() {
      return
    }
    kill_switch_reason_code.set("")
    kill_switch_comment.set("")
    kill_switch_validation_error.set("")
    show_kill_switch_modal.set(true)
  }

  let handle_kill_switch_cancel : @element.MouseHandler = fn(_e) {
    show_kill_switch_modal.set(false)
  }

  let handle_reason_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    kill_switch_reason_code.set(target.value)
    kill_switch_validation_error.set("")
  }

  let handle_comment_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    let value = target.value
    if ffi_string_length(value) > 120 {
      kill_switch_validation_error.set(
        "コメントは120文字以内で入力してください",
      )
    } else {
      kill_switch_validation_error.set("")
      kill_switch_comment.set(value)
    }
  }

  let handle_kill_switch_confirm : @element.MouseHandler = fn(_e) {
    let reason = kill_switch_reason_code.get()
    if reason == "" {
      kill_switch_validation_error.set("操作理由コードを選択してください")
      return
    }
    let comment = kill_switch_comment.get()
    if ffi_string_length(comment) > 120 {
      kill_switch_validation_error.set(
        "コメントは120文字以内で入力してください",
      )
      return
    }
    let current_enabled = kill_switch_enabled.get()
    let next_enabled = not(current_enabled)
    show_kill_switch_modal.set(false)
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let ks = kill_switch_enabled
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    let is_warn = status_is_warning
    ffi_post_kill_switch(
      base_url,
      next_enabled,
      reason,
      comment,
      fn(success, error_message) {
        loading.set(false)
        if success {
          ks.set(next_enabled)
          let result_msg = if next_enabled {
            "⚠ Kill switch を有効にしました。"
          } else {
            "✓ Kill switch を無効にしました。"
          }
          is_err.set(false)
          is_warn.set(next_enabled)
          msg.set(result_msg)
        } else {
          is_err.set(true)
          is_warn.set(false)
          msg.set("✗ " + error_message)
        }
      },
    )
  }

  // ── Manual cycle ────────────────────────────────────────────────────────────

  let handle_run_cycle : @element.MouseHandler = fn(_e) {
    if is_loading.get() || kill_switch_enabled.get() {
      return
    }
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    let is_warn = status_is_warning
    ffi_post_run_cycle(
      base_url,
      fn(success, error_message) {
        loading.set(false)
        if success {
          is_err.set(false)
          is_warn.set(false)
          msg.set("✓ サイクル実行を受け付けました。")
        } else {
          is_err.set(true)
          is_warn.set(false)
          msg.set("✗ " + error_message)
        }
      },
    )
  }

  // ── Render ───────────────────────────────────────────────────────────────────

  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // Status message area (aria-live for a11y)
      div(
        attrs=[
          ("role", @element.AttrString("alert")),
          ("aria-live", @element.AttrString("polite")),
        ],
        dyn_attrs=[
          (
            "style",
            @element.Dynamic(
              fn() {
                let message = status_message.get()
                let is_err = status_is_error.get()
                let is_warn = status_is_warning.get()
                if message == "" {
                  "display:none;"
                } else if is_err {
                  "padding:10px 16px;border-radius:6px;background:rgba(248,113,113,0.12);border:1px solid rgba(248,113,113,0.3);color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
                } else if is_warn {
                  "padding:10px 16px;border-radius:6px;background:rgba(234,179,8,0.12);border:1px solid rgba(234,179,8,0.3);color:#EAB308;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
                } else {
                  "padding:10px 16px;border-radius:6px;background:rgba(34,197,94,0.12);border:1px solid rgba(34,197,94,0.3);color:#22C55E;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
                }
              },
            ),
          ),
        ],
        [text_of(status_message)],
      ),
      // Operations panel
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;display:flex;flex-direction:column;gap:16px;",
        [
          // Runtime start/stop button
          button(
            dyn_style=fn() {
              let base = "border:none;border-radius:6px;padding:12px 24px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;width:100%;max-width:240px;color:#fff;"
              let color_part = if runtime_state.get() == "RUNNING" {
                "background:#F87171;"
              } else {
                "background:#22C55E;"
              }
              let opacity_part = if is_loading.get() {
                "opacity:0.6;"
              } else {
                ""
              }
              base + color_part + opacity_part
            },
            on=events().click(handle_runtime_toggle),
            [
              text_dyn(
                @signal.computed(fn() {
                  if is_loading.get() {
                    "処理中..."
                  } else if runtime_state.get() == "RUNNING" {
                    "運用停止"
                  } else {
                    "運用開始"
                  }
                }),
              ),
            ],
          ),
          // Kill switch toggle button
          button(
            dyn_style=fn() {
              let base = "border-radius:6px;padding:12px 24px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;width:100%;max-width:240px;"
              let state_part = if kill_switch_enabled.get() {
                "background:rgba(234,179,8,0.25);color:#EAB308;border:1px solid rgba(234,179,8,0.5);"
              } else {
                "background:rgba(234,179,8,0.1);color:#EAB308;border:1px solid rgba(234,179,8,0.3);"
              }
              let opacity_part = if is_loading.get() {
                "opacity:0.6;"
              } else {
                ""
              }
              base + state_part + opacity_part
            },
            on=events().click(handle_kill_switch_open_modal),
            [
              text_dyn(
                @signal.computed(fn() {
                  if kill_switch_enabled.get() {
                    "Kill Switch: 有効 (無効化する)"
                  } else {
                    "Kill Switch: 無効 (有効化する)"
                  }
                }),
              ),
            ],
          ),
          // Manual cycle button (disabled when kill switch is enabled)
          button(
            dyn_style=fn() {
              let disabled = kill_switch_enabled.get() || is_loading.get()
              let base = "background:rgba(99,102,241,0.15);color:#818CF8;border:1px solid rgba(99,102,241,0.3);border-radius:6px;padding:12px 24px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;width:100%;max-width:240px;"
              if disabled {
                base + "opacity:0.4;cursor:not-allowed;"
              } else {
                base + "cursor:pointer;"
              }
            },
            on=events().click(handle_run_cycle),
            [text("手動サイクル実行")],
          ),
        ],
      ),
      // Kill switch confirmation modal
      div(
        dyn_style=fn() {
          if show_kill_switch_modal.get() {
            "position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;z-index:40;"
          } else {
            "display:none;"
          }
        },
        attrs=[
          ("role", @element.AttrString("dialog")),
          ("aria-modal", @element.AttrString("true")),
          ("aria-label", @element.AttrString("Kill Switch 確認")),
        ],
        [
          div(
            style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.12);border-radius:12px;padding:32px;width:100%;max-width:440px;box-sizing:border-box;display:flex;flex-direction:column;gap:20px;",
            [
              // Modal title
              p(
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.125rem;font-weight:700;margin:0;",
                [
                  text_dyn(
                    @signal.computed(fn() {
                      if kill_switch_enabled.get() {
                        "Kill Switch を無効化しますか？"
                      } else {
                        "Kill Switch を有効化しますか？"
                      }
                    }),
                  ),
                ],
              ),
              // Modal subtitle
              p(
                style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0;",
                [
                  text(
                    "操作理由コードを選択し、確認後に実行してください。",
                  ),
                ],
              ),
              // Reason code input
              div(
                style="display:flex;flex-direction:column;gap:6px;",
                [
                  label(
                    for_="kill-switch-reason",
                    style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                    [text("操作理由コード *")],
                  ),
                  input(
                    type_="text",
                    id="kill-switch-reason",
                    name="kill-switch-reason",
                    placeholder="理由コードを入力 (例: RISK_CONTROL)",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;width:100%;box-sizing:border-box;",
                    on=events().input(handle_reason_input),
                  ),
                ],
              ),
              // Comment input
              div(
                style="display:flex;flex-direction:column;gap:6px;",
                [
                  label(
                    for_="kill-switch-comment",
                    style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                    [text("コメント（任意、120文字以内）")],
                  ),
                  input(
                    type_="text",
                    id="kill-switch-comment",
                    name="kill-switch-comment",
                    placeholder="操作理由を入力...",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;width:100%;box-sizing:border-box;",
                    on=events().input(handle_comment_input),
                  ),
                  // Validation error
                  div(
                    attrs=[("role", @element.AttrString("alert"))],
                    dyn_style=fn() {
                      let err = kill_switch_validation_error.get()
                      if err == "" {
                        "display:none;"
                      } else {
                        "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
                      }
                    },
                    [text_of(kill_switch_validation_error)],
                  ),
                ],
              ),
              // Modal actions
              div(
                style="display:flex;gap:12px;justify-content:flex-end;",
                [
                  button(
                    style="background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.12);border-radius:6px;padding:10px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;",
                    on=events().click(handle_kill_switch_cancel),
                    [text("キャンセル")],
                  ),
                  button(
                    style="background:#EAB308;color:#000;border:none;border-radius:6px;padding:10px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
                    on=events().click(handle_kill_switch_confirm),
                    [text("実行する")],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
/// POST /operations/runtime to BFF.
extern "js" fn ffi_post_runtime(
  base_url : String,
  action : String,
  on_result : (Bool, String, String) -> Unit
) -> Unit =
  #| (base_url, action, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   fetch(base_url + '/operations/runtime', {
  #|     method: 'POST',
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     body: JSON.stringify({ action }),
  #|   })
  #|   .then(res => res.json().then(body => ({ ok: res.ok, body })))
  #|   .then(({ ok, body }) => {
  #|     if (ok && body.success) {
  #|       const newState = action === 'START' ? 'RUNNING' : 'STOPPED';
  #|       on_result(true, newState, '');
  #|     } else {
  #|       const msg = (body && body.detail) || '状態更新に失敗しました。再試行してください。';
  #|       on_result(false, '', msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '', '状態更新に失敗しました。再試行してください。'));
  #| }

///|
/// POST /operations/kill-switch to BFF.
extern "js" fn ffi_post_kill_switch(
  base_url : String,
  enabled : Bool,
  action_reason_code : String,
  comment : String,
  on_result : (Bool, String) -> Unit
) -> Unit =
  #| (base_url, enabled, action_reason_code, comment, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const body = { enabled };
  #|   if (action_reason_code) body.actionReasonCode = action_reason_code;
  #|   if (comment) body.comment = comment;
  #|   fetch(base_url + '/operations/kill-switch', {
  #|     method: 'POST',
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     body: JSON.stringify(body),
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data.success) {
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (data && data.detail) || '状態更新に失敗しました。再試行してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '状態更新に失敗しました。再試行してください。'));
  #| }

///|
/// POST /commands/run-cycle to BFF.
extern "js" fn ffi_post_run_cycle(
  base_url : String,
  on_result : (Bool, String) -> Unit
) -> Unit =
  #| (base_url, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   fetch(base_url + '/commands/run-cycle', {
  #|     method: 'POST',
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     body: JSON.stringify({}),
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok) {
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (data && data.detail) || 'サイクル実行に失敗しました。再試行してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, 'サイクル実行に失敗しました。再試行してください。'));
  #| }

///|
extern "js" fn ffi_string_length(value : String) -> Int =
  #| (value) => value.length
