import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "prepend_attribute_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends an attribute when a matching element satisfies
/// the configured condition.
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
    // Condition applied to the target.
    fn(VXML) -> Bool,
    // Attribute key.
    String,
    // Attribute value.
    String,
    // Whether to return early after finding a target.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    condition: fn(VXML) -> Bool,
    attribute: Attr,
    traffic_light: TrafficLight,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(
    param.0,
    param.1,
    Attr(desugarer_blame(44), param.2, param.3),
    param.4,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.target_tag -> {
      case inner.condition(vxml) {
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
  [
    testing.data(
      param: #(
        "section",
        core.v_has_key_val(_, "enabled", "yes"),
        "new",
        "first",
        Continue,
      ),
      source: "
                <> root
                  <> section
                    enabled=yes
                    old=second
                  <> section
                    enabled=no
                  <> aside
                    enabled=yes
                ",
      expected: "
                <> root
                  <> section
                    new=first
                    enabled=yes
                    old=second
                  <> section
                    enabled=no
                  <> aside
                    enabled=yes
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
