import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

pub const name = "wrap_children_up_to"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps children preceding the first stop element in a
/// new element of the supplied wrapper tag.
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
    // Parent tag.
    String,
    // Stop tag.
    String,
    // Wrapper tag.
    String,
    // Traversal behavior after wrapping.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    parent_tag: String,
    stop_tag: String,
    wrapper_tag: String,
    traffic_light: TrafficLight,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, param.3))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = fn(vxml) {
    nodemap(vxml, inner)
  }
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(blame, tag, _, children) if tag == inner.parent_tag -> {
      let #(before, after) =
        children_up_to_not_including(children, inner.stop_tag, [])
      let children = [V(blame, inner.wrapper_tag, [], before), ..after]
      #(V(..vxml, children: children), inner.traffic_light)
    }
    _ -> #(vxml, Continue)
  }
}

fn children_up_to_not_including(
  children: List(VXML),
  stop_tag: String,
  acc: List(VXML),
) -> #(List(VXML), List(VXML)) {
  case children {
    [] -> #([], [])
    [first, ..rest] ->
      case first {
        V(_, tag, _, _) if tag == stop_tag -> #(acc, children)
        _ -> {
          let #(acc, rest) = children_up_to_not_including(rest, stop_tag, acc)
          #([first, ..acc], rest)
        }
      }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}

import desugaring/authoring
