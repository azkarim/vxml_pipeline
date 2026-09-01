import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import on
import vxml.{type VXML, T, V}

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
    V(_, tag, attrs, children) if tag == inner.target_tag -> {
      use attr <- on.ok(core.attrs_unique_key_or_none(
        attrs,
        inner.attribute_key,
      ))

      use attr <- on.none_some(attr, fn() { Ok(#(vxml, Continue)) })

      use first, rest <- on.empty_nonempty(children, fn() {
        Error(DesugaringError(vxml.blame, "first child missing"))
      })

      case first {
        T(..) ->
          Error(DesugaringError(
            first.blame,
            "first child is text node instead of V-node",
          ))
        V(..) -> {
          let first =
            first |> core.v_start_insert_text(attr.val <> inner.connector)
          Ok(#(V(..vxml, children: [first, ..rest]), inner.traffic_light))
        }
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

pub const name = "insert_attribute_value_at_first_child_start"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Inserts an attribute value at the start of the target's
/// first element child, followed by a connector string.
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
