import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/pair
import vxml.{type Attr, type VXML, T, V}

pub const name = "unwrap_tags_if_attributes_match"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Unwraps configured elements when all specified attrs match.
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
  let nodemap: n2t.OneToManyNodemap = nodemap(_, inner)
  n2t.one_to_many_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(
  node: VXML,
  inner: InnerParam,
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) -> Ok([node])
    V(_, tag, attrs, children) -> {
      case list.find(inner, fn(pair) { pair |> pair.first == tag }) {
        Error(Nil) -> Ok([node])
        Ok(#(_, attrs_to_match)) -> {
          case matches_all_key_val_pairs(attrs, attrs_to_match) {
            False -> Ok([node])
            True -> Ok(children)
            // bye-bye
          }
        }
      }
    }
  }
}

fn matches_all_key_val_pairs(
  attrs: List(Attr),
  key_value_pairs: List(#(String, String)),
) -> Bool {
  list.all(key_value_pairs, fn(key_value) {
    let #(key, value) = key_value
    list.any(attrs, fn(attr) { attr.key == key && attr.val == value })
  })
}

type Param =
  List(
    #(
      // Tag to unwrap.
      String,
      // Required key-value attrs.
      List(#(String, String)),
    ),
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
