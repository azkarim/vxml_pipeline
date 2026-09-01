import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, param.3.0, param.3.1))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, [one], _)
      if tag == inner.target_tag
      && one.key == inner.attribute_key
      && one.val == inner.attribute_value
    -> {
      vxml
      |> core.v_start_insert_text(inner.start)
      |> core.v_end_insert_text(inner.end)
    }
    _ -> vxml
  }
}

type Param =
  #(
    // Target element name.
    String,
    // Required singleton attribute key.
    String,
    // Required singleton attribute value.
    String,
    // Text inserted at the start and end.
    #(String, String),
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    attribute_key: String,
    attribute_value: String,
    start: String,
    end: String,
  )
}

pub const name = "insert_text_start_end_if_unique_attr"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Inserts configured text around matching elements whose
/// only attribute equals the required key and value.
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
