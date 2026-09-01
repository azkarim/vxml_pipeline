import desugaring/tracking.{type SLine, type SelectionStatus, type Selector}

fn line_selector(_line: SLine) -> SelectionStatus {
  tracking.OG
}

pub fn selector() -> Selector {
  line_selector
  |> tracking.line_selector_to_selector()
}
