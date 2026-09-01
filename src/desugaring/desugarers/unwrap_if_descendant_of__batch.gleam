import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}

pub const name = "unwrap_if_descendant_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Unwraps configured elements beneath configured ancestors.
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
    a: List(VXML),
    _: List(VXML),
    _: List(VXML),
    _: List(VXML),
  ) {
    nodemap(vxml, a, inner)
  }
  nodemap
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(node: VXML, ancestors: List(VXML), inner: InnerParam) -> List(VXML) {
  case node {
    V(_, tag, _, children) ->
      case core.use_list_pair_as_dict(inner, tag) {
        Error(Nil) -> [node]
        Ok(forbidden) -> {
          let ancestor_names = list.map(ancestors, core.v_get_tag)
          case list.any(ancestor_names, list.contains(forbidden, _)) {
            True -> children
            False -> [node]
          }
        }
      }
    _ -> [node]
  }
}

type Param =
  List(
    #(
      // Tag to unwrap.
      String,
      // Ancestor tags that permit unwrapping.
      List(String),
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
