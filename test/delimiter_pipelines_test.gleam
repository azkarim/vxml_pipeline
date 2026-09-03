import gleam/list
import vxml.{Attr, Line, T, V}
import vxml/blame
import vxml_pipeline as ds
import vxml_pipeline/core.{
  BackslashParenthesis, BeginEndAlign, DoubleDollar, SingleDollar,
}
import vxml_pipeline/delimiter_pipelines
import vxml_pipeline/split_replacement as sr

fn pipeline_ux_options() -> ds.PipelineUXOptions {
  ds.PipelineUXOptions(False, False, 0)
}

pub fn main() {
  markdown_link_pipeline_test()
  inline_math_splitting_test()
  inline_math_outside_test()
  asymmetric_inline_math_splitting_test()
  asymmetric_inline_math_with_escaped_dollar_test()
  display_math_splitting_test()
  asymmetric_display_math_splitting_test()
  boundary_aware_symmetric_delimiter_pipeline_test()
  asymmetric_delimiter_pipeline_test()
  permissive_symmetric_delimiter_pipeline_test()
  annotated_backtick_pipeline_test()
  delimiter_cleanup_pipeline_test()
  escaped_delimiter_splitting_test()
}

fn markdown_link_pipeline_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "[label](target)")]),
    ])
  let pipeline = delimiter_pipelines.markdown_link_pipeline([], [])
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
    delimiter_pipelines.inline_math_pipeline(
      [SingleDollar],
      SingleDollar,
      BackslashParenthesis,
      [],
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

fn inline_math_outside_test() {
  let input =
    V(blame.no_blame, "root", [], [
      V(blame.no_blame, "pre", [], [
        T(blame.no_blame, [Line(blame.no_blame, "$not math$")]),
      ]),
    ])
  let pipeline =
    delimiter_pipelines.inline_math_pipeline(
      [SingleDollar],
      SingleDollar,
      BackslashParenthesis,
      [],
      ["pre"],
    )
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  assert output == input
}

fn display_math_splitting_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before $$x$$ after")]),
    ])
  let pipeline =
    delimiter_pipelines.math_block_pipeline(
      [DoubleDollar],
      DoubleDollar,
      [],
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
    delimiter_pipelines.inline_math_pipeline(
      [BackslashParenthesis],
      SingleDollar,
      BackslashParenthesis,
      [],
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

fn asymmetric_inline_math_with_escaped_dollar_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before \\(\\$500\\) after")]),
    ])
  let pipeline =
    delimiter_pipelines.inline_math_pipeline(
      [BackslashParenthesis],
      SingleDollar,
      BackslashParenthesis,
      [],
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
      V(_, "Math", [], [T(_, [Line(_, "\\(\\$500\\)")])]),
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
    delimiter_pipelines.math_block_pipeline(
      [BeginEndAlign],
      DoubleDollar,
      [],
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

fn boundary_aware_symmetric_delimiter_pipeline_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before _text_ after")]),
    ])
  let pipeline =
    delimiter_pipelines.boundary_aware_symmetric_delimiter_pipeline(
      "_",
      "_",
      "i",
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
      V(_, "i", [], [T(_, [Line(_, "text")])]),
      T(_, [Line(_, " after")]),
    ],
  ) = output
}

fn asymmetric_delimiter_pipeline_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before <text> after")]),
    ])
  let pipeline =
    delimiter_pipelines.asymmetric_delimiter_pipeline(
      "<",
      ">",
      "<",
      ">",
      "mark",
      [],
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
      V(_, "mark", [], [T(_, [Line(_, "text")])]),
      T(_, [Line(_, " after")]),
    ],
  ) = output
}

fn permissive_symmetric_delimiter_pipeline_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [
        Line(blame.no_blame, "word_with_markup_inside_done"),
      ]),
    ])
  let pipeline =
    delimiter_pipelines.permissive_symmetric_delimiter_pipeline(
      "_",
      "_",
      "i",
      [],
      [],
    )
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [
      T(_, [Line(_, "word")]),
      V(_, "i", [], [T(_, [Line(_, "with")])]),
      T(_, [Line(_, "markup")]),
      V(_, "i", [], [T(_, [Line(_, "inside")])]),
      T(_, [Line(_, "done")]),
    ],
  ) = output
}

fn annotated_backtick_pipeline_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [Line(blame.no_blame, "before `marked`{red} after")]),
    ])
  let pipeline =
    delimiter_pipelines.annotated_backtick_pipeline("span", "class", [], [])
  let assert Ok(#(output, _, _)) =
    ds.run_pipeline(input, pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [
      T(_, [Line(_, "before ")]),
      V(_, "span", [Attr(_, "class", "red")], [T(_, [Line(_, "marked")])]),
      T(_, [Line(_, " after")]),
    ],
  ) = output
}

fn delimiter_cleanup_pipeline_test() {
  let input =
    V(blame.no_blame, "root", [], [
      T(blame.no_blame, [
        Line(blame.no_blame, "_one_*two*[three](target) tail _"),
      ]),
    ])
  let delimiter_pipeline =
    [
      delimiter_pipelines.permissive_symmetric_delimiter_pipeline(
        "\\*",
        "*",
        "b",
        [],
        [],
      ),
      delimiter_pipelines.markdown_link_pipeline([], []),
      delimiter_pipelines.permissive_symmetric_delimiter_pipeline(
        "_",
        "_",
        "i",
        [],
        [],
      ),
    ]
    |> list.flatten
  let assert Ok(#(before_cleanup, _, _)) =
    ds.run_pipeline(input, delimiter_pipeline, [], pipeline_ux_options())
  let assert V(
    _,
    "root",
    [],
    [
      T(_, [Line(_, "")]),
      V(_, "i", [], [T(_, [Line(_, "one")])]),
      T(_, [Line(_, "")]),
      V(_, "b", [], [T(_, [Line(_, "two")])]),
      T(_, [Line(_, "")]),
      V(_, "a", [Attr(_, "href", "target")], [T(_, [Line(_, "three")])]),
      T(_, [Line(_, " tail _")]),
    ],
  ) = before_cleanup

  let assert Ok(#(after_cleanup, _, _)) =
    ds.run_pipeline(
      before_cleanup,
      delimiter_pipelines.delimiter_cleanup_pipeline(),
      [],
      pipeline_ux_options(),
    )
  let assert V(
    _,
    "root",
    [],
    [
      V(_, "i", [], [T(_, [Line(_, "one")])]),
      V(_, "b", [], [T(_, [Line(_, "two")])]),
      V(_, "a", [Attr(_, "href", "target")], [T(_, [Line(_, "three")])]),
      T(_, [Line(_, " tail _")]),
    ],
  ) = after_cleanup
}

fn escaped_delimiter_splitting_test() {
  assert sr.remaining_unescaped_splits(["before\\", "after"], "\\$")
    == ["before\\$after"]
  assert sr.remaining_unescaped_splits(["before\\\\", "after"], "\\$")
    == ["before\\\\", "after"]
}
