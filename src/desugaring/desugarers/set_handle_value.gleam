import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/result
import gleam/string
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "set_handle_value"

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

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
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
    V(_, tag, attrs, _) if tag == inner.0 -> {
      use attrs <- result.try(list.try_map(attrs, map_attr(_, inner)))
      Ok(#(V(..vxml, attrs: attrs), inner.2))
    }
    _ -> Ok(#(vxml, Continue))
  }
}

fn map_attr(attr: Attr, inner: InnerParam) -> Result(Attr, DesugaringError) {
  case attr.key {
    "handle" ->
      case attr.val |> string.split_once(" ") {
        Ok(#(_, handle_value)) ->
          case string.trim(handle_value) == "" {
            True -> Error(malformed_handle_error(attr))
            False -> Ok(attr)
          }
        Error(_) -> Ok(Attr(..attr, val: attr.val <> " " <> inner.1))
      }
    _ -> Ok(attr)
  }
}

fn malformed_handle_error(attr: Attr) -> DesugaringError {
  DesugaringError(attr.blame, "handle contains a space but no value follows it")
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
                      handle=algorithms:intro some-existing-value
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
                      handle=complexity-theory#page ::øøChapterCounter
                      <>
                        'Chapter content'
                    <> Chapter
                      handle=algorithms:intro some-existing-value
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
                      handle=lemma:basic already-has-value
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
                      handle=theorem:proof ::øøChapterCounter.::øøSubCounter
                      <>
                        'Sub content'
                    <> Sub
                      handle=lemma:basic already-has-value
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
