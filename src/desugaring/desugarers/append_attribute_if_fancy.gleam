import desugaring/authoring
import desugaring/core.{
  type ContextualVXMLCondition, type Desugarer, type DesugarerTransform,
  type DesugaringError, type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "append_attribute_if_fancy"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends an attribute to matching elements when they
/// satisfy the supplied contextual condition.
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
    // Target tag.
    String,
    // Contextual condition applied to matching elements.
    ContextualVXMLCondition,
    // Attribute key.
    String,
    // Attribute value.
    String,
    // Traversal behavior after appending.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    condition: ContextualVXMLCondition,
    attrs: List(Attr),
    traffic_light: TrafficLight,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  InnerParam(
    param.0,
    param.1,
    [Attr(authoring.blame(name, 54), param.2, param.3)],
    param.4,
  )
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnFancyOneToOneNoErrorNodemap = fn(
    node,
    ancestors,
    previous_siblings_before_mapping,
    previous_siblings_after_mapping,
    following_siblings_before_mapping,
  ) {
    nodemap(
      node,
      ancestors,
      previous_siblings_before_mapping,
      previous_siblings_after_mapping,
      following_siblings_before_mapping,
      inner,
    )
  }
  nodemap
  |> n2t.early_return_fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  inner: InnerParam,
) -> #(VXML, core.TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.target_tag -> {
      case
        inner.condition(
          vxml,
          ancestors,
          previous_siblings_before_mapping,
          previous_siblings_after_mapping,
          following_siblings_before_mapping,
        )
      {
        True -> #(
          V(..vxml, attrs: list.append(attrs, inner.attrs)),
          inner.traffic_light,
        )
        False -> #(vxml, Continue)
      }
    }
    _ -> #(vxml, Continue)
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
