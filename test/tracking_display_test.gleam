import gleam/list
import vxml.{V}
import vxml/blame
import vxml_pipeline/selectors
import vxml_pipeline/tracking

fn margin(columns: Int) {
  blame.BlameTableMarginColumnsMinMax(columns, columns)
}

fn line_at(lines: List(String), index: Int) {
  lines |> list.drop(index) |> list.first
}

pub fn main() {
  let lines =
    V(blame.NoBlame(["note"]), "Book", [], [])
    |> tracking.vxml_to_s_lines
    |> selectors.all()()

  assert tracking.s_lines_verbatim_lines(lines, False) == ["<> Book"]

  let without_blame =
    tracking.s_lines_table_lines_with(
      lines,
      "",
      False,
      0,
      margin(0),
      margin(10),
    )
  assert line_at(without_blame, 3) == Ok("[note]    █<> Book")

  let without_comments =
    tracking.s_lines_table_lines_with(
      lines,
      "",
      False,
      0,
      margin(10),
      margin(0),
    )
  assert line_at(without_comments, 3) == Ok("│         █<> Book")

  let without_margins =
    tracking.s_lines_table_lines_with(lines, "", False, 0, margin(0), margin(0))
  assert line_at(without_margins, 1) == Ok("│doc")
  assert line_at(without_margins, 3) == Ok("│<> Book")

  let separated_selection = [
    tracking.VSLine(blame.no_blame, 0, "<> A", tracking.OG, "A"),
    tracking.VSLine(blame.no_blame, 0, "<> B", tracking.NotSelected, "B"),
    tracking.VSLine(blame.no_blame, 0, "<> C", tracking.OG, "C"),
  ]
  assert tracking.s_lines_verbatim_lines(separated_selection, False)
    == [
      "<> A",
      "...",
      "<> C",
    ]
  assert tracking.s_lines_verbatim_lines_with_options(
      separated_selection,
      False,
      False,
    )
    == ["<> A", "<> C"]

  let elder_text_sibling = [
    tracking.TSLine(blame.no_blame, 2, "<>", tracking.NotSelected),
    tracking.LSLine(blame.no_blame, 4, "\"first line\"", tracking.NotSelected),
    tracking.LSLine(blame.no_blame, 4, "\"second line\"", tracking.NotSelected),
    tracking.VSLine(blame.no_blame, 2, "<> Target", tracking.OG, "Target"),
  ]
  let elder_text_sibling =
    tracking.extend_selection_to_ancestors(
      elder_text_sibling,
      True,
      False,
      False,
    )
  assert elder_text_sibling
    == [
      tracking.TSLine(blame.no_blame, 2, "<>", tracking.Bystander),
      tracking.LSLine(blame.no_blame, 4, "\"first line\"", tracking.Bystander),
      tracking.LSLine(blame.no_blame, 4, "\"second line\"", tracking.Bystander),
      tracking.VSLine(blame.no_blame, 2, "<> Target", tracking.OG, "Target"),
    ]

  let relative_window_source =
    ["A", "B", "C", "D", "E", "F", "G", "H"]
    |> list.map(fn(tag) {
      tracking.VSLine(
        blame.no_blame,
        0,
        "<> " <> tag,
        tracking.NotSelected,
        tag,
      )
    })
  let select_a =
    tracking.line_selector_to_selector(fn(line) {
      case line {
        tracking.VSLine(tag: "A", ..) -> tracking.OG
        _ -> tracking.NotSelected
      }
    })
  assert relative_window_source
    |> tracking.select_relative_window(select_a, 5, 30)()
    |> tracking.s_lines_verbatim_lines_with_options(False, False)
    == ["<> F", "<> G", "<> H"]
}
