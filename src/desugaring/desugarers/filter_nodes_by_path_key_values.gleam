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
import vxml/blame as bl

pub const name = "filter_nodes_by_path_key_values"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Within each configured source path, retains subtrees
/// selected by an exact attribute key-value match.
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
      // Source path restricting the filter.
      String,
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
    _ -> delete_outside_subtrees(matches_a_path_key_value(_, inner)).transform
  }
}

fn matches_a_path_key_value(vxml: VXML, inner: InnerParam) -> Bool {
  case vxml {
    T(..) -> False
    V(_, _, [], _) -> False
    V(blame, _, attrs, _) ->
      list.any(inner, fn(path_key_value) {
        !bl.path_contains(blame, path_key_value.0)
        || list.any(attrs, fn(attr) {
          path_key_value.1 == attr.key && path_key_value.2 == attr.val
        })
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
