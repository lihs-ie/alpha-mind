export const MESSAGES = {
  // SCR-000 認証
  "MSG-E-0001": "認証に失敗しました。入力内容を確認してください。",

  // SCR-001 ダッシュボード
  "MSG-I-0011": "運用を開始しました。",
  "MSG-I-0012": "運用を停止しました。",
  "MSG-I-0013-ON": "kill switchを有効にしました。",
  "MSG-I-0013-OFF": "kill switchを無効にしました。",
  "MSG-I-0014": "手動サイクル実行を受け付けました。",
  "MSG-W-0011": "kill switchが有効です。発注系操作は停止中です。",
  "MSG-E-0011": "状態更新に失敗しました。再試行してください。",

  // SCR-002 戦略設定
  "MSG-I-0021": "戦略設定を保存しました。",
  "MSG-E-0021": "戦略設定の保存に失敗しました。",

  // SCR-003 注文管理
  "MSG-I-0031": "注文を承認しました。",
  "MSG-I-0032": "注文を却下しました。",
  "MSG-I-0033": "注文の再送を受け付けました。",
  "MSG-W-0031": "kill switch有効中のため承認できません。",
  "MSG-E-0031": "注文更新に失敗しました。",

  // SCR-004 監査ログ
  "MSG-I-0041": "traceIdをコピーしました。",
  "MSG-E-0041": "監査ログの取得に失敗しました。",

  // SCR-005 モデル検証
  "MSG-I-0051": "モデルを昇格しました。",
  "MSG-I-0052": "モデルを差し戻しました。",
  "MSG-E-0051": "モデル状態の更新に失敗しました。",

  // 共通
  VALIDATION_REQUIRED: "この項目は必須です。",
  VALIDATION_EMAIL_FORMAT: "メールアドレス形式で入力してください。",
  VALIDATION_PASSWORD_REQUIRED: "パスワードを入力してください。",
  VALIDATION_EMAIL_REQUIRED: "メールアドレスを入力してください。",
  VALIDATION_FREQUENCY_REQUIRED: "売買頻度を選択してください。",
  VALIDATION_SYMBOLS_REQUIRED: "銘柄を1件以上設定してください。",
  VALIDATION_DAILY_LOSS_LIMIT: "0より大きく20以下で入力してください。",
  VALIDATION_POSITION_LIMIT: "0より大きく50以下で入力してください。",
  VALIDATION_ORDER_LIMIT: "1以上100以下で入力してください。",
  VALIDATION_DATE_RANGE: "期間の指定が不正です。",
  VALIDATION_REJECT_REASON: "却下理由を入力してください。",
  VALIDATION_TRACE_ID_FORMAT: "traceId形式が不正です。",
  VALIDATION_PROMOTE_REASON: "昇格理由を入力してください。",
  VALIDATION_REVERT_REASON: "差し戻し理由を入力してください。",
  VALIDATION_COMPARE_MAX: "比較は2件までです。",
  ERROR_NETWORK: "ネットワークエラーが発生しました。",
  ERROR_UNKNOWN: "予期しないエラーが発生しました。",
  CONFIRM_CANCEL: "キャンセル",
  CONFIRM_OK: "実行",
  EMPTY_ORDERS: "該当する注文がありません。",
  EMPTY_AUDIT_LOGS: "該当する監査ログがありません。",
  EMPTY_MODELS: "該当するモデルがありません。",
} as const;

export type MessageKey = keyof typeof MESSAGES;
