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

pub const name = "filter_nodes_by_path_key_values_while_saving"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Applies path-scoped attribute filtering while retaining
/// subtrees with configured saved tags.
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
    // Path, attribute-key, and attribute-value selectors.
    List(#(String, String, String)),
    // Tags whose subtrees are always retained.
    List(String),
  )

type InnerParam {
  InnerParam(
    path_key_values: List(#(String, String, String)),
    saved: List(String),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  case inner.path_key_values {
    [] -> n2t.identity_transform
    _ ->
      delete_outside_subtrees(matches_a_path_key_value_or_a_tag(_, inner)).transform
  }
}

fn matches_a_path_key_value_or_a_tag(vxml: VXML, inner: InnerParam) -> Bool {
  case vxml {
    T(..) -> False
    V(blame, tag, attrs, _) ->
      list.contains(inner.saved, tag)
      || list.any(inner.path_key_values, fn(path_key_value) {
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
