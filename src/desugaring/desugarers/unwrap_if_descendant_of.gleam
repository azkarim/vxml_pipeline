import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}

pub const name = "unwrap_if_descendant_of"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Unwraps a target element beneath configured ancestors.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToManyNoErrorNodemap = fn(
    vxml: VXML,
    ancestors: List(VXML),
    _: List(VXML),
    _: List(VXML),
    _: List(VXML),
  ) {
    nodemap(vxml, ancestors, inner)
  }
  nodemap
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(node: VXML, ancestors: List(VXML), inner: InnerParam) -> List(VXML) {
  case node {
    V(_, tag, _, children) if tag == inner.0 ->
      case
        list.any(inner.1, fn(b) {
          list.any(ancestors, fn(a) { core.is_v_and_tag_equals(a, b) })
        })
      {
        True -> children
        False -> [node]
      }
    _ -> [node]
  }
}

type Param =
  #(
    // Tag to unwrap.
    String,
    // Ancestor tags that permit unwrapping.
    List(String),
  )

type InnerParam =
  Param

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
