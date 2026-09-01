import desugaring/line_wrapping
import gleam/list
import vxml.{type Line, Line}
import vxml/blame

fn line_contents(lines: List(Line)) -> List(String) {
  lines
  |> list.map(fn(line) { line.content })
}

fn rewrap(
  source_contents: List(String),
  occupied_width: Int,
  max_width: Int,
) -> #(List(String), Int) {
  let lines =
    source_contents
    |> list.map(fn(content) { Line(blame.no_blame, content) })
  let #(lines, final_width) =
    line_wrapping.rewrap_lines(lines, occupied_width, max_width)
  #(line_contents(lines), final_width)
}

pub fn main() {
  // A line whose rendered width exactly reaches the limit
  // does not wrap.
  assert rewrap(["a b"], 0, 3) == #(["a b"], 3)

  // Text comfortably below the limit remains on one line.
  assert rewrap(["alpha beta"], 0, 20) == #(["alpha beta"], 10)

  // Wrapping occurs at a word boundary when another word
  // clearly cannot fit.
  assert rewrap(["aa bb cc"], 0, 7) == #(["aa bb", "cc"], 2)

  // An indivisible word is allowed to exceed the limit.
  assert rewrap(["abcdefgh"], 0, 4) == #(["abcdefgh"], 8)

  // Occupied width from preceding inline content contributes
  // to the returned width when no new line is introduced.
  assert rewrap(["aa bb"], 3, 9) == #(["aa bb"], 8)

  // Original line boundaries are reflowed as spaces, and
  // repeated spaces represented by empty tokens are retained.
  assert rewrap(["one", "two"], 0, 20) == #(["one two"], 7)
  assert rewrap(["a  b"], 0, 20) == #(["a  b"], 4)

  // Each generated line carries the blame of its first
  // included source token.
  let source_blame = blame.Src([], "source.wly", 1, 1, blame.Movable)
  let assert #([Line(first_blame, "aa"), Line(second_blame, "bb")], 2) =
    line_wrapping.rewrap_lines([Line(source_blame, "aa bb")], 0, 2)
  assert first_blame == source_blame
  assert second_blame == blame.Src([], "source.wly", 1, 4, blame.Movable)

  // Reflowing original lines together retains the blame of
  // the first content placed on the generated line.
  let later_blame = blame.Src([], "source.wly", 2, 1, blame.Movable)
  let assert #([Line(combined_blame, "one two")], 7) =
    line_wrapping.rewrap_lines(
      [Line(source_blame, "one"), Line(later_blame, "two")],
      0,
      20,
    )
  assert combined_blame == source_blame

  // An empty text payload leaves the preceding occupied
  // width unchanged.
  assert line_wrapping.rewrap_lines([], 3, 20) == #([], 3)
}
