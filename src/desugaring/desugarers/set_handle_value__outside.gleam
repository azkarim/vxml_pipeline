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

pub const name = "set_handle_value__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends handle values outside configured subtrees,
/// with configurable traversal.
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

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNodemap = nodemap(_, inner, outside)
  nodemap
  |> n2t.early_return_one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
  outside: List(String),
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case vxml {
    V(_, tag, attrs, _) ->
      case list.contains(outside, tag) {
        True -> Ok(#(vxml, GoBack))
        False ->
          case tag == inner.0 {
            True -> {
              use attrs <- result.try(list.try_map(attrs, map_attr(_, inner)))
              Ok(#(V(..vxml, attrs: attrs), inner.2))
            }
            False -> Ok(#(vxml, Continue))
          }
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

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
