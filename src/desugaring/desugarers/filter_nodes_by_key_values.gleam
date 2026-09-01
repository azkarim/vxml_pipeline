import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/desugarers/delete_outside_subtrees.{
  constructor as delete_outside_subtrees,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "filter_nodes_by_key_values"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Retains subtrees and ancestor paths selected by any exact
/// attribute key-value match.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Attribute key.
      String,
      // Attribute value.
      String,
    ),
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  case inner {
    [] -> n2t.identity_transform
    _ -> delete_outside_subtrees(matches_a_pair(_, inner)).transform
  }
}

fn matches_a_pair(vxml: VXML, inner: InnerParam) -> Bool {
  case vxml {
    T(..) -> False
    V(_, _, attrs, _) ->
      list.any(attrs, fn(attr) {
        list.any(inner, fn(kv) { kv.0 == attr.key && kv.1 == attr.val })
      })
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
