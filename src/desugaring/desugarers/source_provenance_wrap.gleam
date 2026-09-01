import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Attr, type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "source_provenance_wrap"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Wraps selected source-backed elements alongside a span
/// containing their source location.
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
    // Tag of the wrapper element.
    String,
    // Attributes for the wrapper element.
    List(#(String, String)),
    // Attributes for the source-location span.
    List(#(String, String)),
    // Element names to wrap.
    List(String),
  )

type InnerParam {
  InnerParam(
    source_path_prefix: String,
    wrapper_tag: String,
    wrapper_attrs: List(Attr),
    span_attrs: List(Attr),
    target_tags: List(String),
  )
}

const b = bl.Des([], name, 53)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(
    source_path_prefix: param.0,
    wrapper_tag: param.1,
    wrapper_attrs: core.string_pairs_to_attrs(param.2, b),
    span_attrs: core.string_pairs_to_attrs(param.3, b),
    target_tags: param.4,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(blame, tag, _, _) ->
      case list.contains(inner.target_tags, tag), blame {
        True, bl.Src(..) -> {
          let span =
            V(b, "span", inner.span_attrs, [
              T(b, [
                Line(b, inner.source_path_prefix <> bl.blame_digest(blame)),
              ]),
            ])
          V(b, inner.wrapper_tag, inner.wrapper_attrs, [vxml, span])
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
        "div",
        [#("class", "source-location-container")],
        [#("class", "source-location")],
        ["Math"],
      ),
      source: "
                <> root
                  <> Math
                    <>
                      'a+b'
                ",
      expected: "
                <> root
                  <> div
                    class=source-location-container
                    <> Math
                      <>
                        'a+b'
                    <> span
                      class=source-location
                      <>
                        './wly/tst.source:2:3 ->'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
