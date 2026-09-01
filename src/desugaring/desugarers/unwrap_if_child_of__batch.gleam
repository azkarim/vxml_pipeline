import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "unwrap_if_child_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Unwraps configured elements when they have configured parents.
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
  let nodemap: n2t.FancyOneToManyNoErrorNodemap = fn(node, ancestors, _, _, _) {
    nodemap(node, ancestors, inner)
  }
  nodemap
  |> n2t.fancy_one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, ancestors: List(VXML), inner: InnerParam) -> List(VXML) {
  case vxml {
    T(_, _) -> [vxml]
    V(_, tag, _, children) -> {
      case core.use_list_pair_as_dict(inner, tag) {
        Error(Nil) -> [vxml]
        Ok(parent_tags) -> {
          case list.first(ancestors) {
            Error(Nil) -> [vxml]
            Ok(parent) -> {
              let assert V(_, actual_parent_tag, _, _) = parent
              case list.contains(parent_tags, actual_parent_tag) {
                False -> [vxml]
                True -> children
              }
            }
          }
        }
      }
    }
  }
}

type Param =
  List(
    #(
      // Tag to unwrap.
      String,
      // Parent tags that permit unwrapping.
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
