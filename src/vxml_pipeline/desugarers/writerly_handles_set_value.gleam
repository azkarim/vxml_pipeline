import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp, Match}
import gleam/result
import vxml.{type Attr, type VXML, Attr, V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "writerly_handles_set_value"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends a value to the handle attribute of matching
/// elements, with configurable traversal.
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
    // Target tag.
    String,
    // Handle value to append.
    String,
    // Whether to traverse matching descendants.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    value: String,
    traffic_light: TrafficLight,
    handle_regexp: Regexp,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(handle_regexp) =
    regexp.from_string(
      "^(" <> handle_syntax.decorated_name_pattern <> ")(?: <<(.*)>>)?$",
    )
  Ok(InnerParam(param.0, param.1, param.2, handle_regexp))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.target_tag -> {
      use attrs <- result.try(list.try_map(attrs, map_attr(_, inner)))
      Ok(#(V(..vxml, attrs: attrs), inner.traffic_light))
    }
    _ -> Ok(#(vxml, Continue))
  }
}

fn map_attr(attr: Attr, inner: InnerParam) -> Result(Attr, DesugaringError) {
  case attr.key {
    "handle" ->
      case regexp.scan(inner.handle_regexp, attr.val) {
        [Match(_, [Some(_)]), ..] ->
          Ok(
            Attr(
              ..attr,
              val: attr.val <> " " <> handle_syntax.encode_value(inner.value),
            ),
          )
        [Match(_, [Some(_), _]), ..] -> Ok(attr)
        _ -> Error(malformed_handle_error(attr))
      }
    _ -> Ok(attr)
  }
}

fn malformed_handle_error(attr: Attr) -> DesugaringError {
  DesugaringError(
    attr.blame,
    "handle attr must have form <name> or <name> <<value>>; found: “"
      <> attr.val
      <> "”",
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("Chapter", "::øøChapterCounter", GoBack),
      source: "
                  <> root
                    <> Chapter
                      handle=complexity-theory#page
                      <>
                        'Chapter content'
                    <> Chapter
                      handle=algorithms:intro <<some-existing-value>>
                      <>
                        'More content'
                    <> OtherElement
                      handle=should-not-change
                      <>
                        'Should not change'
                ",
      expected: "
                  <> root
                    <> Chapter
                      handle=complexity-theory#page <<::øøChapterCounter>>
                      <>
                        'Chapter content'
                    <> Chapter
                      handle=algorithms:intro <<some-existing-value>>
                      <>
                        'More content'
                    <> OtherElement
                      handle=should-not-change
                      <>
                        'Should not change'
                ",
    ),
    testing.data(
      param: #("Sub", "::øøChapterCounter.::øøSubCounter", GoBack),
      source: "
                  <> root
                    <> Sub
                      handle=theorem:proof
                      <>
                        'Sub content'
                    <> Sub
                      handle=lemma:basic <<already-has-value>>
                      <>
                        'More sub content'
                    <> Chapter
                      handle=should-not-change
                      <>
                        'Chapter content'
                ",
      expected: "
                  <> root
                    <> Sub
                      handle=theorem:proof <<::øøChapterCounter.::øøSubCounter>>
                      <>
                        'Sub content'
                    <> Sub
                      handle=lemma:basic <<already-has-value>>
                      <>
                        'More sub content'
                    <> Chapter
                      handle=should-not-change
                      <>
                        'Chapter content'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
