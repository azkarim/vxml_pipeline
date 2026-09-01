import desugaring/tracking.{type SLine, type SelectionStatus, type Selector}
import gleam/string

fn line_selector(line: SLine, s: String) -> SelectionStatus {
  case string.contains(line.content, s) {
    True -> tracking.OG
    _ -> tracking.NotSelected
  }
}

pub fn selector(s: String) -> Selector {
  line_selector(_, s)
  |> tracking.line_selector_to_selector()
}
