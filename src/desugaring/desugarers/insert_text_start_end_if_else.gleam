import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1.0, param.1.1, param.2.0, param.2.1, param.3))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.target_tag -> {
      case inner.condition(vxml) {
        True ->
          vxml
          |> core.v_start_insert_text(inner.true_start)
          |> core.v_end_insert_text(inner.true_end)
        False ->
          vxml
          |> core.v_start_insert_text(inner.false_start)
          |> core.v_end_insert_text(inner.false_end)
      }
    }
    _ -> vxml
  }
}

type Param =
  #(
    // Target element name.
    String,
    // Text inserted at the start and end when true.
    #(String, String),
    // Text inserted at the start and end when false.
    #(String, String),
    // Condition selecting the text pair.
    fn(VXML) -> Bool,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    true_start: String,
    true_end: String,
    false_start: String,
    false_end: String,
    condition: fn(VXML) -> Bool,
  )
}

pub const name = "insert_text_start_end_if_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Inserts one of two configured text pairs around matching
/// elements according to a predicate.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: "<function>",
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
