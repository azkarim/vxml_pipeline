import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Attr, type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "source_provenance_append_span"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends a configured span containing the source location
/// to selected elements that retain source blame.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Prefix prepended to the source-blame path. A relative
    // prefix is relative to the process that consumes the
    // location, normally from the project root.
    String,
    // Attributes for the appended span.
    List(#(String, String)),
    // Element names to which the span is appended.
    List(String),
  )

type InnerParam {
  InnerParam(
    source_path_prefix: String,
    span_attrs: List(Attr),
    target_tags: List(String),
  )
}

const b = bl.Des([], name, 47)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(
    source_path_prefix: param.0,
    span_attrs: core.string_pairs_to_attrs(param.1, b),
    target_tags: param.2,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(blame, tag, _, children) ->
      case list.contains(inner.target_tags, tag), blame {
        True, bl.Src(..) -> {
          let span =
            V(b, "span", inner.span_attrs, [
              T(b, [
                Line(b, inner.source_path_prefix <> bl.blame_digest(blame)),
              ]),
            ])
          V(..vxml, children: list.append(children, [span]))
        }
        _, _ -> vxml
      }
    _ -> vxml
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #(
        "./wly/",
        [#("class", "source-location"), #("title", "Open source")],
        ["MathBlock"],
      ),
      source: "
                <> root
                  <> MathBlock
                    <>
                      '$$'
                      'hello'
                      '$$'
                ",
      expected: "
                <> root
                  <> MathBlock
                    <>
                      '$$'
                      'hello'
                      '$$'
                    <> span
                      class=source-location
                      title=Open source
                      <>
                        './wly/tst.source:2:3 ->'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
