import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "prepend_attribute__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends an attribute to matching elements outside
/// configured subtrees.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Target tag.
    String,
    // Attribute key.
    String,
    // Attribute value.
    String,
    // Whether to return early after finding a target.
    TrafficLight,
  )

type InnerParam =
  #(String, Attr, TrafficLight)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(param.0, Attr(desugarer_blame(43), param.1, param.2), param.3)
  |> Ok
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 -> #(
      V(..vxml, attrs: [inner.1, ..attrs]),
      inner.2,
    )
    _ -> #(vxml, Continue)
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: #("section", "new", "first", Continue),
      outside: ["protected"],
      source: "
                <> root
                  <> section
                  <> protected
                    <> section
                  <> section
                ",
      expected: "
                <> root
                  <> section
                    new=first
                  <> protected
                    <> section
                  <> section
                    new=first
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
