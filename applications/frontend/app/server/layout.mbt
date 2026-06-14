///| Server Layout Component
///|
///| Provides the basic HTML head wiring for all pages.
///| This is a server component - no event handlers.

///|
/// Luna loader script (required for island hydration).
let loader_script : String = "<script type=\"module\" src=\"/static/loader.js\"></script>"

///|
/// Default head HTML. Must always include `loader_script` so island
/// hydration works once client components are added (#83-85).
pub fn head() -> String {
  loader_script
}
