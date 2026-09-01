import desugaring as ds
import desugaring/core.{
  BackslashParenthesis, BeginEndAlign, DoubleDollar, SingleDollar,
}
import desugaring/delimited_syntax
import desugaring/split_replacement as sr
import vxml.{Attr, Line, T, V}
import vxml/blame

fn pipeline_ux_options() -> ds.PipelineUXOptions {
  ds.PipelineUXOptions(False, False, 0)
}

pub fn main() {
  markdown_link_pipeline_test()
  inline_math_splitting_test()
  asymmetric_inline_math_splitting_test()
  display_math_splitting_test()
  asymmetric_display_math_splitting_test()
  symmetric_delimiter_splitting_test()
  escaped_delimiter_splitting_test()
}

fn markdown_link_pipeline_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "[label](target)")]),
    ])
  let pipeline = delimited_syntax.markdown_link_pipeline([], [])
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [T(_, [Line(_, "")]), V(_, "a", attrs, children), T(_, [Line(_, "")])],
  ) = output
  let assert [Attr(_, "href", "target")] = attrs
  let assert [T(_, [Line(_, "label")])] = children
}

fn inline_math_splitting_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before $x$ after")]),
    ])
  let pipeline =
    delimited_syntax.create_math_elements(
      [SingleDollar],
      SingleDollar,
      BackslashParenthesis,
      [],
    )
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [
      T(_, [Line(_, "before ")]),
      V(_, "Math", [], [T(_, [Line(_, "$x$")])]),
      T(_, [Line(_, " after")]),
    ],
  ) = output
}

fn display_math_splitting_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before $$x$$ after")]),
    ])
  let pipeline =
    delimited_syntax.create_mathblock_elements([DoubleDollar], DoubleDollar, [])
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [
      T(_, [Line(_, "before ")]),
      V(
        _,
        "MathBlock",
        [],
        [T(_, [Line(_, "$$"), Line(_, "x"), Line(_, "$$")])],
      ),
      T(_, [Line(_, " after")]),
    ],
  ) = output
}

fn asymmetric_inline_math_splitting_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before \\(x\\) after")]),
    ])
  let pipeline =
    delimited_syntax.create_math_elements(
      [BackslashParenthesis],
      SingleDollar,
      BackslashParenthesis,
      [],
    )
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [
      T(_, [Line(_, "before ")]),
      V(_, "Math", [], [T(_, [Line(_, "$\\(x\\)$")])]),
      T(_, [Line(_, " after")]),
    ],
  ) = output
}

fn asymmetric_display_math_splitting_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [
        Line(blame.no_blame, "before \\begin{align}x\\end{align} after"),
      ]),
    ])
  let pipeline =
    delimited_syntax.create_mathblock_elements(
      [BeginEndAlign],
      DoubleDollar,
      [],
    )
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [
      T(_, [Line(_, "before ")]),
      V(
        _,
        "MathBlock",
        [],
        [
          T(
            _,
            [
              Line(_, "$$"),
              Line(_, "\\begin{align}x\\end{align}"),
              Line(_, "$$"),
            ],
          ),
        ],
      ),
      T(_, [Line(_, " after")]),
    ],
  ) = output
}

fn symmetric_delimiter_splitting_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before _text_ after")]),
    ])
  let pipeline =
    delimited_syntax.symmetric_delimiter_pipeline("_", "_", "i", [])
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [
      T(_, [Line(_, "before ")]),
      V(_, "i", [], [T(_, [Line(_, "text")])]),
      T(_, [Line(_, " after")]),
    ],
  ) = output
}

fn escaped_delimiter_splitting_test() {
  assert sr.remaining_unescaped_splits(["before\\", "after"], "\\$")
    == ["before\\$after"]
  assert sr.remaining_unescaped_splits(["before\\\\", "after"], "\\$")
    == ["before\\\\", "after"]
}
