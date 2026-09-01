import desugaring/selectors
import desugaring/tracking
import gleam/list
import vxml.{V}
import vxml/blame

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
}
