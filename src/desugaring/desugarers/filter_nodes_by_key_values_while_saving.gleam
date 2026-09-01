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

pub const name = "filter_nodes_by_key_values_while_saving"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Retains subtrees selected by exact attribute matches or
/// saved tags, plus the ancestor paths leading to them.
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
    // Attribute key-value pairs selecting subtrees.
    List(#(String, String)),
    // Tags whose subtrees are always retained.
    List(String),
  )

type InnerParam {
  InnerParam(key_values: List(#(String, String)), saved: List(String))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  case inner.key_values {
    [] -> n2t.identity_transform
    _ -> delete_outside_subtrees(should_keep(_, inner)).transform
  }
}

fn should_keep(vxml: VXML, inner: InnerParam) -> Bool {
  case vxml {
    T(..) -> False
    V(_, tag, attrs, _) ->
      list.contains(inner.saved, tag)
      || list.any(attrs, fn(attr) {
        list.any(inner.key_values, fn(kv) {
          kv.0 == attr.key && kv.1 == attr.val
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
