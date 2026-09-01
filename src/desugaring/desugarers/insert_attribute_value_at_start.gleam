import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/option.{None, Some}
import on
import vxml.{type VXML, V}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, param.3))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(#(VXML, TrafficLight), DesugaringError) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.target_tag -> {
      use maybe <- on.ok(core.attrs_unique_key_or_none(
        attrs,
        inner.attribute_key,
      ))
      case maybe {
        None -> Ok(#(vxml, Continue))
        Some(attr) ->
          Ok(#(
            vxml |> core.v_start_insert_text(attr.val <> inner.connector),
            inner.traffic_light,
          ))
      }
    }
    _ -> Ok(#(vxml, Continue))
  }
}

type Param =
  #(
    // Target element name.
    String,
    // Attribute key whose value is inserted.
    String,
    // Connector appended to the attribute value.
    String,
    // Whether traversal returns early after insertion.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    attribute_key: String,
    connector: String,
    traffic_light: TrafficLight,
  )
}

pub const name = "insert_attribute_value_at_start"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Inserts an attribute value at the start of each target,
/// followed by a connector string.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
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
