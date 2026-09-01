import desugaring/authoring
import desugaring/core.{
  type ContextualVXMLCondition, type Desugarer, type DesugarerTransform,
  type DesugaringError, type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "prepend_counter_incrementing_attribute_if_fancy"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a counter-increment attribute when a
/// contextual condition is satisfied.
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
    // Counter name.
    String,
    // Contextual condition.
    ContextualVXMLCondition,
    // Whether to traverse matching descendants.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    attribute: Attr,
    condition: ContextualVXMLCondition,
    traffic_light: TrafficLight,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  InnerParam(
    param.0,
    Attr(desugarer_blame(44), "_", param.1 <> " ::++" <> param.1),
    param.2,
    param.3,
  )
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnFancyOneToOneNoErrorNodemap = fn(
    vxml,
    ancestors,
    previous_siblings_before_mapping,
    previous_siblings_after_mapping,
    following_siblings_before_mapping,
  ) {
    nodemap(
      vxml,
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
) -> #(VXML, TrafficLight) {
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
          V(..vxml, attrs: [inner.attribute, ..attrs]),
          inner.traffic_light,
        )
        False -> #(vxml, Continue)
      }
    }
    _ -> #(vxml, Continue)
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
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
