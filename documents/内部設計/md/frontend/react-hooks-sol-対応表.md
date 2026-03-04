# React Hooks → Sol (MoonBit) 対応表

React Hooks を Sol (mizchi/sol + mizchi/luna + mizchi/signals) でどのように再現できるかを検証する。

Sol は Solid.js に着想を得た**細粒度リアクティビティ**パラダイムを採用しており、React の仮想 DOM 差分更新とは根本的にアーキテクチャが異なる。React は再レンダリングごとにコンポーネント関数を再実行するが、Sol ではコンポーネント関数は**1回だけ実行**され、Signal の変更が DOM の該当箇所を直接更新する。

## 対応サマリー

| # | React Hook | Sol 対応 | 再現度 |
|---|-----------|----------|--------|
| 1 | `useState` | `@signal.signal()` | A — ネイティブ対応 |
| 2 | `useReducer` | `@signal.signal()` + reducer 関数 | A — パターンで実現 |
| 3 | `useContext` | `@signal.create_context()` / `use_context()` | A — ネイティブ対応 |
| 4 | `useRef` | `@signal.signal()` (非リアクティブ用途) / FFI DOM 参照 | B — 部分的に実現 |
| 5 | `useImperativeHandle` | N/A（Island アーキテクチャでは不要） | D — 設計上不要 |
| 6 | `useEffect` | `@signal.effect()` + `on_cleanup()` | A — ネイティブ対応 |
| 7 | `useLayoutEffect` | `@signal.render_effect()` | A — ネイティブ対応 |
| 8 | `useInsertionEffect` | N/A（CSS-in-JS 非推奨） | D — 設計上不要 |
| 9 | `useEffectEvent` | `@signal.untracked()` でイベント参照 | B — パターンで実現 |
| 10 | `useMemo` | `@signal.computed()` / `@signal.memo()` | A — ネイティブ対応 |
| 11 | `useCallback` | 不要（関数は再生成されない） | — 概念自体が不要 |
| 12 | `useTransition` | N/A（細粒度更新のため不要） | C — 要カスタム実装 |
| 13 | `useDeferredValue` | N/A（細粒度更新のため不要） | C — 要カスタム実装 |
| 14 | `useDebugValue` | N/A（DevTools 未対応） | D — 未サポート |
| 15 | `useId` | サーバー側で生成 / カスタム実装 | B — パターンで実現 |
| 16 | `useSyncExternalStore` | `@signal.effect()` + `@signal.signal()` | A — パターンで実現 |
| 17 | `useActionState` | `@action` + Signal 手動管理 | B — パターンで実現 |
| 18 | `useOptimistic` | Signal + ロールバックパターン | B — パターンで実現 |
| 19 | `useFormStatus` | Signal 手動管理 | B — パターンで実現 |
| 20 | `use` (API) | `Async` VNode / Signal context | B — 部分的に実現 |

**再現度の凡例:**
- **A** — ネイティブ対応またはイディオム的に自然に再現可能
- **B** — パターンの組み合わせで実現可能（多少のボイラープレートあり）
- **C** — カスタム実装が必要（フレームワーク側にプリミティブなし）
- **D** — 設計上不要または未サポート

---

## 1. useState

### React

```tsx
const [count, setCount] = useState(0);
```

コンポーネントの再レンダリングごとに最新の値を返す。`setCount` で更新すると再レンダリングがトリガーされる。

### Sol

```moonbit
let count = @signal.signal(0)

// 値の取得（依存追跡あり）
count.get()

// 値の設定
count.set(42)

// 関数による更新（前の値を参照）
count.update(fn(n) { n + 1 })

// 依存追跡なしで値を取得
count.peek()
```

Sol の `signal` は React の `useState` に直接対応する。ただし重要な違いとして、React は `setCount` 後にコンポーネント全体を再実行するが、Sol では Signal を購読している DOM ノードのみが更新される。

### 使用例

```moonbit
pub fn counter(props : CounterProps) -> DomNode {
  let count = @signal.signal(props.initial_count)

  div(class="counter", [
    span(class="count-display", [text_of(count)]),
    div(class="buttons", [
      button(
        on=events().click(fn(_) { count.update(fn(n) { n - 1 }) }),
        [text("-")],
      ),
      button(
        on=events().click(fn(_) { count.update(fn(n) { n + 1 }) }),
        [text("+")],
      ),
    ]),
  ])
}
```

---

## 2. useReducer

### React

```tsx
const [state, dispatch] = useReducer(reducer, initialState);

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'increment': return { count: state.count + 1 };
    case 'decrement': return { count: state.count - 1 };
    default: return state;
  }
}
```

### Sol

Sol には `useReducer` に相当する組み込みプリミティブはないが、Signal + reducer 関数のパターンで同等の機能を実現できる。

```moonbit
pub(all) enum Action {
  Increment
  Decrement
  Reset(Int)
}

pub(all) struct State {
  count : Int
} derive(ToJson, FromJson)

fn reducer(state : State, action : Action) -> State {
  match action {
    Increment => { count: state.count + 1 }
    Decrement => { count: state.count - 1 }
    Reset(value) => { count: value }
  }
}

pub fn counter_with_reducer(props : CounterProps) -> DomNode {
  let state = @signal.signal(State::{ count: props.initial_count })

  // dispatch 関数
  let dispatch : (Action) -> Unit = fn(action) {
    state.update(fn(current) { reducer(current, action) })
  }

  div(class="counter", [
    span([text_of(@signal.computed(fn() { state.get().count.to_string() }))]),
    button(
      on=events().click(fn(_) { dispatch(Increment) }),
      [text("+")],
    ),
    button(
      on=events().click(fn(_) { dispatch(Decrement) }),
      [text("-")],
    ),
    button(
      on=events().click(fn(_) { dispatch(Reset(0)) }),
      [text("Reset")],
    ),
  ])
}
```

### 備考

MoonBit の `enum` による Action 型は TypeScript の union 型よりも型安全であり、パターンマッチで網羅性チェックが効く。

---

## 3. useContext

### React

```tsx
const ThemeContext = createContext('light');

// Provider
<ThemeContext.Provider value="dark">
  <Child />
</ThemeContext.Provider>

// Consumer
const theme = useContext(ThemeContext);
```

### Sol

```moonbit
// Context の作成
let theme_context : @signal.Context[String] = @signal.create_context("light")

// Provider（スコープ内で値を提供）
@signal.provide(theme_context, "dark", fn() {
  // この中の子コンポーネントから参照可能
  child_component()
})

// Consumer（値の取得）
let theme : String? = @signal.use_context(theme_context)
```

### 使用例

```moonbit
pub(all) struct ThemeConfig {
  primary_color : String
  background_color : String
  is_dark : Bool
} derive(ToJson, FromJson)

let theme_context : @signal.Context[ThemeConfig] = @signal.create_context(
  ThemeConfig::{
    primary_color: "#1a73e8",
    background_color: "#ffffff",
    is_dark: false,
  },
)

pub fn themed_app() -> DomNode {
  let theme = ThemeConfig::{
    primary_color: "#bb86fc",
    background_color: "#121212",
    is_dark: true,
  }
  @signal.provide(theme_context, theme, fn() {
    themed_card()
  })
}

fn themed_card() -> DomNode {
  let theme = @signal.use_context(theme_context)
  match theme {
    Some(t) =>
      div(
        style="background:" + t.background_color + ";color:" + t.primary_color,
        [text("Themed Card")],
      )
    None => div([text("No theme")])
  }
}
```

---

## 4. useRef

### React

```tsx
// DOM 参照
const inputRef = useRef<HTMLInputElement>(null);
<input ref={inputRef} />
inputRef.current?.focus();

// ミュータブル値の保持（再レンダリングなし）
const timerIdRef = useRef<number | null>(null);
```

### Sol

Sol には React の `ref` 属性に直接対応する機能はない。用途別に対応方法が異なる。

#### ミュータブル値の保持

```moonbit
// peek() を使えば依存追跡なしで Signal を読み取れる
// Signal 自体が再レンダリングをトリガーしない用途にも使える
let timer_id = @signal.signal(0)

// 依存追跡なしで読み書き
timer_id.set(123)
let id = timer_id.peek() // effect を発火しない
```

#### DOM 要素への参照

```moonbit
// FFI で DOM 要素を直接操作（MoonBit の JS FFI を使用）
extern "js" fn query_selector(selector : String) -> @js.Any =
  #|(s) => document.querySelector(s)

extern "js" fn focus_element(element : @js.Any) -> Unit =
  #|(el) => el && el.focus()

pub fn auto_focus_input() -> DomNode {
  // effect_once で初回マウント時に実行
  @signal.effect_once(fn() {
    let element = query_selector("#my-input")
    focus_element(element)
  })

  input(id="my-input", type_="text", [])
}
```

### 備考

Sol ではコンポーネント関数が1回しか実行されないため、ローカル変数（`let mut`）でもミュータブル値の保持は可能。ただし Signal 経由のほうがリアクティブシステムとの統合が容易。

---

## 5. useImperativeHandle

### React

```tsx
useImperativeHandle(ref, () => ({
  focus() { inputRef.current?.focus(); },
  scrollIntoView() { inputRef.current?.scrollIntoView(); },
}));
```

親コンポーネントに公開するメソッドをカスタマイズする。

### Sol

**設計上不要。** Sol の Island アーキテクチャでは、各 Island は独立した hydration 単位であり、親から子の内部メソッドを直接呼び出すパターンは推奨されない。

コンポーネント間の通信が必要な場合は、共有 Signal または Context を使用する。

```moonbit
// 共有 Signal による間接的な制御
let should_focus = @signal.signal(false)

// 親側
button(
  on=events().click(fn(_) { should_focus.set(true) }),
  [text("Focus Input")],
)

// 子側
@signal.effect(fn() {
  if should_focus.get() {
    focus_element(query_selector("#target-input"))
    should_focus.set(false)
  }
})
```

---

## 6. useEffect

### React

```tsx
useEffect(() => {
  const connection = createConnection(url);
  connection.connect();

  return () => {
    connection.disconnect(); // cleanup
  };
}, [url]); // url が変わるたびに再実行
```

### Sol

```moonbit
// 基本的な effect（依存は自動追跡）
@signal.effect(fn() {
  let current_url = url.get() // url Signal を自動追跡
  let connection = create_connection(current_url)
  connection.connect()

  // cleanup 登録
  @signal.on_cleanup(fn() {
    connection.disconnect()
  })
})
```

### React との違い

| 観点 | React `useEffect` | Sol `effect` |
|------|-------------------|--------------|
| 依存配列 | 手動指定 `[dep1, dep2]` | **自動追跡**（Signal の `.get()` 呼び出しを検出） |
| 実行タイミング | レンダリング後（非同期） | microtask キュー（非同期） |
| cleanup | 戻り値の関数 | `on_cleanup()` で登録 |
| 初回のみ実行 | `useEffect(() => {}, [])` | `effect_once(fn() { ... })` |

### バリエーション

```moonbit
// 初回のみ実行（React の useEffect(() => {}, []) 相当）
@signal.effect_once(fn() {
  println("Mounted")
})

// 条件付き実行
@signal.effect_when(
  fn() { is_enabled.get() },
  fn() {
    // is_enabled が true の間のみ実行
    start_polling()
    @signal.on_cleanup(fn() { stop_polling() })
  },
)

// 特定 Signal の変更を監視（依存配列を明示的に指定したい場合）
let dispose = @signal.on(url, fn(new_url) {
  println("URL changed to: " + new_url)
})
```

---

## 7. useLayoutEffect

### React

```tsx
useLayoutEffect(() => {
  const { height } = ref.current.getBoundingClientRect();
  setTooltipHeight(height);
}, []);
```

ブラウザのペイント前に同期的に実行される。DOM 測定に使用。

### Sol

```moonbit
// render_effect は同期的に実行される（ペイント前）
@signal.render_effect(fn() {
  let element = query_selector("#tooltip")
  let height = get_bounding_height(element)
  tooltip_height.set(height)
})
```

`render_effect` は `effect` と異なり、microtask キューを介さず同期的に実行されるため、DOM 測定やレイアウト計算に適している。

---

## 8. useInsertionEffect

### React

```tsx
useInsertionEffect(() => {
  const style = document.createElement('style');
  style.textContent = `.dynamic { color: ${color} }`;
  document.head.appendChild(style);
  return () => document.head.removeChild(style);
});
```

CSS-in-JS ライブラリ向け。DOM 変更前にスタイルを挿入する。

### Sol

**設計上不要。** Sol/Luna のスタイリングは CSS ファイル（CSS Modules または globals.css）で管理するため、動的 CSS 挿入のユースケースがない。このプロジェクトでは Tailwind CSS も使用しない。

どうしても必要な場合は FFI で `document.head` にスタイル要素を挿入できるが、推奨されない。

---

## 9. useEffectEvent

### React

```tsx
const onVisit = useEffectEvent((url) => {
  logVisit(url, numberOfItems); // numberOfItems を最新値で参照
});

useEffect(() => {
  onVisit(url); // url が変わるたびに実行
}, [url]);
```

Effect 内で最新の props/state を参照しつつ、それを依存に含めたくない場合に使用。

### Sol

```moonbit
// untracked で依存追跡を回避
@signal.effect(fn() {
  let current_url = url.get() // url のみ追跡

  // number_of_items は追跡しない（最新値は取得する）
  let items = @signal.untracked(fn() {
    number_of_items.get()
  })

  log_visit(current_url, items)
})
```

Sol の `untracked` は、Solid.js の同名関数と同様に、ブロック内の Signal 読み取りを依存追跡から除外する。

---

## 10. useMemo

### React

```tsx
const sortedItems = useMemo(
  () => items.sort((a, b) => a.name.localeCompare(b.name)),
  [items]
);
```

### Sol

```moonbit
let sorted_items = @signal.computed(fn() {
  let current_items = items.get() // items Signal を自動追跡
  current_items.sort_by(fn(a, b) { compare_strings(a.name, b.name) })
})

// 使用時
let result = sorted_items() // () -> T の呼び出し
```

`computed` は依存 Signal が変更されない限りキャッシュされた値を返す。React の `useMemo` と異なり、依存配列の手動指定は不要。

### 便利なユーティリティ

```moonbit
// 複数 Signal からの結合
let full_name = @signal.combine2(first_name, last_name, fn(f, l) {
  f + " " + l
})

// 前回の値を追跡
let previous_count = @signal.previous(count)
// previous_count() -> Int? (前回の値、初回は None)
```

---

## 11. useCallback

### React

```tsx
const handleClick = useCallback(() => {
  doSomething(a, b);
}, [a, b]);
```

関数の再生成を防ぎ、子コンポーネントの不要な再レンダリングを回避する。

### Sol

**概念自体が不要。** Sol ではコンポーネント関数が1回しか実行されないため、関数が再生成されることがない。React のように「再レンダリングのたびに新しいクロージャが作られる」問題が存在しない。

```moonbit
pub fn my_component() -> DomNode {
  let count = @signal.signal(0)

  // この関数は1回だけ作成される（コンポーネント関数は1回だけ実行される）
  let handle_click : (@js_dom.MouseEvent) -> Unit = fn(_) {
    count.update(fn(n) { n + 1 })
  }

  button(on=events().click(handle_click), [text("Click")])
}
```

---

## 12. useTransition

### React

```tsx
const [isPending, startTransition] = useTransition();

function handleClick() {
  startTransition(() => {
    setTab('heavy-tab'); // 低優先度の更新
  });
}
```

UI をブロックせずに状態を更新する。重い再レンダリングを低優先度としてマークする。

### Sol

Sol の細粒度リアクティビティでは、Signal 更新が該当 DOM ノードのみを更新するため、React のような「コンポーネントツリー全体の再レンダリング」が発生せず、`useTransition` のユースケースの多くは不要になる。

ただし、大量の DOM 更新を遅延させたい場合はカスタム実装が必要。

```moonbit
// 簡易的な遅延更新パターン
let is_pending = @signal.signal(false)
let deferred_tab = @signal.signal("default")

fn start_transition(update : () -> Unit) -> Unit {
  is_pending.set(true)
  // microtask で遅延実行
  set_timeout(
    fn() {
      update()
      is_pending.set(false)
    },
    0,
  )
}

// 使用
start_transition(fn() {
  deferred_tab.set("heavy-tab")
})
```

### 備考

Sol では DOM 更新が細粒度のため、React ほど Transition の恩恵は大きくない。大量のリストレンダリング等で必要になる場合は、仮想化（windowing）やチャンク分割で対応するのがより適切。

---

## 13. useDeferredValue

### React

```tsx
const deferredQuery = useDeferredValue(query);
```

値の更新を遅延させ、UI の応答性を維持する。

### Sol

`useTransition` と同様、細粒度更新のため多くの場合不要。必要な場合はカスタム実装。

```moonbit
// debounce パターンで遅延値を実現
fn deferred_signal(source : @signal.Signal[String], delay : Int) -> @signal.Signal[String] {
  let deferred = @signal.signal(source.peek())
  let timer_id = @signal.signal(0)

  @signal.effect(fn() {
    let value = source.get()
    let old_timer = timer_id.peek()
    if old_timer != 0 {
      clear_timeout(old_timer)
    }
    let new_timer = set_timeout(
      fn() { deferred.set(value) },
      delay,
    )
    timer_id.set(new_timer)
  })

  deferred
}

// 使用例
let query = @signal.signal("")
let deferred_query = deferred_signal(query, 300)
```

---

## 14. useDebugValue

### React

```tsx
useDebugValue(isOnline ? 'Online' : 'Offline');
```

React DevTools でカスタム Hook にラベルを表示する。

### Sol

**未サポート。** MoonBit/Sol 用の DevTools は現時点で存在しない。

デバッグには Signal のインスペクション API を使用できる。

```moonbit
// Signal の購読者数を確認
let subscriber_count = my_signal.subscriber_count()

// バッチ状態を確認
let is_batch = @signal.is_batching()
let batch_depth = @signal.get_batch_depth()

// デバッグ用 effect
@signal.effect(fn() {
  println("[DEBUG] count = " + count.get().to_string())
})
```

---

## 15. useId

### React

```tsx
const id = useId();
// id = ":r0:", ":r1:", etc.
<label htmlFor={id}>Name</label>
<input id={id} />
```

SSR と CSR で一致する一意な ID を生成する。

### Sol

Sol には組み込みの `useId` はない。SSR/CSR での ID 一致が必要な場合はカスタム実装。

```moonbit
// シンプルなカウンターベース ID 生成
let id_counter : @signal.Signal[Int] = @signal.signal(0)

fn generate_id(prefix : String) -> String {
  id_counter.update(fn(n) { n + 1 })
  prefix + "-" + id_counter.peek().to_string()
}

// 使用例
pub fn labeled_input(label_text : String) -> DomNode {
  let id = generate_id("input")

  div([
    label(for_=id, [text(label_text)]),
    input(id=id, type_="text", []),
  ])
}
```

### 備考

Sol の Island アーキテクチャでは、SSR 時のサーバーコンポーネントとクライアント Island が明確に分離されているため、React ほど SSR/CSR 間の ID 一致問題は発生しにくい。Island の `luna:id` 属性が hydration の同一性を保証する。

---

## 16. useSyncExternalStore

### React

```tsx
const snapshot = useSyncExternalStore(
  store.subscribe,
  store.getSnapshot,
  store.getServerSnapshot
);
```

外部ストアの値を React の状態として同期する。

### Sol

Signal 自体が外部ストアのラッパーとして機能する。

```moonbit
// 外部ストア（例: ブラウザの localStorage）を Signal と同期
fn sync_local_storage(key : String, initial : String) -> @signal.Signal[String] {
  let store = @signal.signal(get_local_storage(key).or(initial))

  // localStorage → Signal の同期
  add_storage_listener(fn(event) {
    if event.key == key {
      store.set(event.new_value)
    }
  })

  // Signal → localStorage の同期
  @signal.effect(fn() {
    let value = store.get()
    set_local_storage(key, value)
  })

  store
}

// 外部 WebSocket ストアの例
fn sync_websocket(url : String) -> @signal.Signal[String] {
  let message = @signal.signal("")

  @signal.effect_once(fn() {
    let ws = create_websocket(url)
    ws.on_message(fn(data) {
      message.set(data)
    })

    @signal.on_cleanup(fn() {
      ws.close()
    })
  })

  message
}
```

### 備考

Sol では Signal が一級のリアクティブプリミティブのため、外部ストアとの同期は `effect` + `signal` で自然に記述できる。React の `useSyncExternalStore` が解決する「tearing」問題（並行レンダリング中の不整合）は、Sol の同期的な細粒度更新モデルでは発生しない。

---

## 17. useActionState

### React

```tsx
const [state, formAction, isPending] = useActionState(
  async (previousState, formData) => {
    const result = await submitForm(formData);
    return result;
  },
  { message: '' }
);
```

フォーム Action の状態（結果、pending）を管理する。

### Sol

Sol の Server Actions (`@action`) と Signal を組み合わせて実現する。

```moonbit
pub(all) struct ActionState[T] {
  data : T
  error : String
  is_pending : Bool
} derive(ToJson, FromJson)

fn create_action_state[T](
  initial : T,
  action_url : String,
  build_payload : () -> @js.Any,
) -> (@signal.Signal[ActionState[T]], () -> Unit) {
  let state = @signal.signal(
    ActionState::{ data: initial, error: "", is_pending: false },
  )

  let submit : () -> Unit = fn() {
    state.update(fn(s) { { ..s, is_pending: true, error: "" } })

    let payload = build_payload()
    @action.invoke_action(action_url, payload, fn(response) {
      match response {
        @action.ActionResponse::Success(result) => {
          let data : T = decode_json(result)
          state.set(ActionState::{ data: data, error: "", is_pending: false })
        }
        @action.ActionResponse::Error(_, message) =>
          state.update(fn(s) { { ..s, error: message, is_pending: false } })
        @action.ActionResponse::NetworkError(message) =>
          state.update(fn(s) { { ..s, error: message, is_pending: false } })
        @action.ActionResponse::Redirect(url) => ffi_redirect(url)
      }
    })
  }

  (state, submit)
}

// 使用例
pub fn contact_form() -> DomNode {
  let name = @signal.signal("")
  let (state, submit) = create_action_state(
    { message: "" },
    "/_action/contact",
    fn() { to_json({ name: name.get() }) },
  )

  form(
    on=events().submit(fn(event) {
      event.preventDefault()
      submit()
    }),
    [
      input(
        on=events().input(fn(event) {
          name.set(get_input_value(event))
        }),
        [],
      ),
      button(
        dyn_class=fn() {
          if state.get().is_pending { "submitting" } else { "" }
        },
        [text("Submit")],
      ),
      @luna.show(
        fn() { state.get().error != "" },
        fn() { div(class="error", [text(state.get().error)]) },
      ),
    ],
  )
}
```

---

## 18. useOptimistic

### React

```tsx
const [optimisticMessages, addOptimistic] = useOptimistic(
  messages,
  (state, newMessage) => [...state, { text: newMessage, sending: true }]
);
```

非同期操作の完了を待たずに楽観的に UI を更新し、失敗時にロールバックする。

### Sol

Signal + ロールバックパターンで実現する。

```moonbit
fn create_optimistic[T](
  source : @signal.Signal[T],
  reducer : (T, T) -> T,
) -> (@signal.Signal[T], (T, async () -> T) -> Unit) {
  let optimistic_value = @signal.signal(source.peek())

  // source が変わったら optimistic も追従
  @signal.effect(fn() {
    optimistic_value.set(source.get())
  })

  let apply_optimistic : (T, async () -> T) -> Unit = fn(
    optimistic_update,
    async_action,
  ) {
    // 楽観的に即座に更新
    let previous = source.peek()
    optimistic_value.set(reducer(previous, optimistic_update))

    // 非同期操作を実行
    invoke_async(async_action, fn(result) {
      match result {
        Ok(new_value) => source.set(new_value)
        Err(_) => optimistic_value.set(previous) // ロールバック
      }
    })
  }

  (optimistic_value, apply_optimistic)
}
```

---

## 19. useFormStatus

### React

```tsx
function SubmitButton() {
  const { pending, data, method, action } = useFormStatus();
  return <button disabled={pending}>Submit</button>;
}
```

親の `<form>` の送信状態を子コンポーネントから取得する。

### Sol

Context + Signal で実現する。

```moonbit
pub(all) struct FormStatus {
  is_pending : Bool
  method : String
  action : String
} derive(ToJson, FromJson)

let form_status_context : @signal.Context[@signal.Signal[FormStatus]] =
  @signal.create_context(@signal.signal(FormStatus::{
    is_pending: false,
    method: "POST",
    action: "",
  }))

// Form ラッパー
pub fn managed_form(
  action : String,
  children : Array[DomNode],
) -> DomNode {
  let status = @signal.signal(FormStatus::{
    is_pending: false,
    method: "POST",
    action: action,
  })

  @signal.provide(form_status_context, status, fn() {
    form(
      on=events().submit(fn(event) {
        event.preventDefault()
        status.update(fn(s) { { ..s, is_pending: true } })
        // ... 送信処理 ...
      }),
      children,
    )
  })
}

// 子コンポーネントから参照
pub fn submit_button() -> DomNode {
  let status_signal = @signal.use_context(form_status_context)
  match status_signal {
    Some(status) =>
      button(
        dyn_class=fn() {
          if status.get().is_pending { "disabled" } else { "" }
        },
        [
          @luna.show(
            fn() { status.get().is_pending },
            fn() { text("Submitting...") },
          ),
          @luna.show(
            fn() { status.get().is_pending |> Bool::not },
            fn() { text("Submit") },
          ),
        ],
      )
    None => button([text("Submit")])
  }
}
```

---

## 20. use (React API)

### React

```tsx
// Promise の読み取り（Suspense と連携）
const data = use(fetchPromise);

// Context の読み取り（条件分岐内でも可）
if (showTheme) {
  const theme = use(ThemeContext);
}
```

`use` は厳密には Hook ではなく API。Promise と Context を読み取る。ループや条件分岐内でも呼び出せる点が Hook と異なる。

### Sol

#### Promise の読み取り → Async VNode

```moonbit
// Sol では Async VNode がサスペンスに相当する
pub fn async_data_component() -> DomNode {
  @luna.Node::Async(VAsync::{
    loader: async fn() {
      let data = fetch_data()
      div([text(data.title)])
    },
    fallback: Some(fn() {
      div(class="loading", [text("Loading...")])
    }),
  })
}
```

#### Context の読み取り → use_context

```moonbit
// Sol の use_context はどこからでも呼び出せる
// （React の useContext と異なり Hook ルールの制約がない）
fn conditional_theme() -> DomNode {
  let show_theme = @signal.signal(true)

  div([
    @luna.show(
      fn() { show_theme.get() },
      fn() {
        // 条件分岐内でも Context を取得可能
        let theme = @signal.use_context(theme_context)
        match theme {
          Some(t) => span(style="color:" + t.primary_color, [text("Themed")])
          None => span([text("Default")])
        }
      },
    ),
  ])
}
```

### 備考

Sol ではそもそも Hook のルール（トップレベルでのみ呼び出し可能）が存在しないため、`use` API が解決する「条件分岐内での Context 読み取り」は初めから可能。

---

## まとめ

### Sol の優位性

1. **依存配列の手動管理が不要** — Signal の自動追跡により `useEffect`, `useMemo` 等の依存配列指定ミスがなくなる
2. **useCallback が不要** — コンポーネント関数が1回しか実行されないため、関数の再生成問題が存在しない
3. **Hook ルールの制約がない** — ループや条件分岐内でも Signal / Context の読み書きが自由
4. **細粒度更新** — Virtual DOM の差分比較なしに、変更された DOM ノードのみを直接更新

### Sol で追加のパターンが必要なもの

1. **useReducer** — reducer パターンを自前で構築（MoonBit の enum + match で型安全に実現可能）
2. **useActionState / useFormStatus / useOptimistic** — Server Actions + Signal の組み合わせで実現
3. **useRef (DOM 参照)** — FFI 経由の DOM 操作が必要
4. **useTransition / useDeferredValue** — 細粒度更新のため多くの場合不要だが、必要時はカスタム実装

### React 固有で Sol に不要なもの

1. **useCallback** — 再レンダリングの概念がないため不要
2. **useInsertionEffect** — CSS-in-JS を使わないため不要
3. **useDebugValue** — DevTools が未対応
4. **useImperativeHandle** — Island アーキテクチャでは設計上不要

---

## 参考リンク

- [React Hooks 公式ドキュメント](https://react.dev/reference/react/hooks)
- [React DOM Hooks](https://react.dev/reference/react-dom/hooks)
- Sol フレームワーク: `references/sol.mbt/`
- Luna UI ライブラリ: `references/sol.mbt/.mooncakes/mizchi/luna/`
- Signals ライブラリ: `references/sol.mbt/.mooncakes/mizchi/signals/`
