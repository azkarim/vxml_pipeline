import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string.{inspect as ins}
import vxml.{type Attr, type Line, type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "source_provenance_wrap_lines__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Wraps source-backed lines in configured spans containing
/// both the line and its source location, outside selected
/// subtrees.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Prefix prepended to each source-blame path. A relative
    // prefix is relative to the process that consumes the
    // location, normally from the project root.
    String,
    // Attributes for the span wrapping each source line.
    List(#(String, String)),
    // Attributes for the nested source-location span.
    List(#(String, String)),
  )

type InnerParam {
  InnerParam(
    source_path_prefix: String,
    line_span_attrs: List(Attr),
    location_span_attrs: List(Attr),
  )
}

const b = bl.Des([], name, 42)

const newline_t = T(b, [Line(b, ""), Line(b, "")])

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(
    source_path_prefix: param.0,
    line_span_attrs: core.string_pairs_to_attrs(param.1, b),
    location_span_attrs: core.string_pairs_to_attrs(param.2, b),
  ))
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToManyNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn nodemap(vxml: VXML, inner: InnerParam) -> List(VXML) {
  case vxml {
    T(_, lines) ->
      lines
      |> list.map(line_to_tooltip_span(_, inner))
      |> list.intersperse(newline_t)
    _ -> [vxml]
  }
}

fn line_to_tooltip_span(line: Line, inner: InnerParam) -> VXML {
  let location =
    inner.source_path_prefix
    <> case line.blame {
      bl.Src(..) -> {
        let assert bl.Src(_, path, line_no, char_no, _) = line.blame
        path <> ":" <> ins(line_no) <> ":" <> ins(char_no)
      }
      _ -> ""
    }

  case location == inner.source_path_prefix {
    True -> T(line.blame, [line])
    False ->
      V(line.blame, "span", inner.line_span_attrs, [
        T(line.blame, [Line(line.blame, line.content)]),
        V(line.blame, "span", inner.location_span_attrs, [
          T(line.blame, [Line(line.blame, location)]),
        ]),
      ])
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    // note 1: not sure if following test is correct
    // it was reverse-engineered from the desugarer's
    // output long after this desugarer had already
    // stopped being used (but it might be correct)
    //
    // note 2: 'test' is the filename assigned by the
    // assertive test runner, which is why
    // '../path/to/content/test' shows up in the expected
    // output
    testing.data_with_outside(
      param: #("../path/to/content/", [#("class", "t-3003-c")], [
        #("class", "t-3003"),
      ]),
      outside: ["Math", "MathBlock"],
      source: "
                <> root
                  <>
                    'some text'
                ",
      expected: "
                <> root
                  <> span
                    class=t-3003-c
                    <>
                      'some text'
                    <> span
                      class=t-3003
                      <>
                        '../path/to/content/tst.source:3:5'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
