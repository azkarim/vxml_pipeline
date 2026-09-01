import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type Line, type VXML, Line, V}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0,
    Line(desugarer_blame(27), param.1.0),
    Line(desugarer_blame(28), param.1.1),
  )
  |> Ok
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

type Param =
  #(
    // Target element name.
    String,
    #(
      // Line content inserted at the start.
      String,
      // Line content inserted at the end.
      String,
    ),
  )

type InnerParam =
  #(String, Line, Line)

pub const name = "insert_line_start_end"

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 -> {
      vxml
      |> core.v_start_insert_line(inner.1)
      |> core.v_end_insert_line(inner.2)
    }
    _ -> vxml
  }
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Inserts configured lines at the beginning and end of
/// each matching element.
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
