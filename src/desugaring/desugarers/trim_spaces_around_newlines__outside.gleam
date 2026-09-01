import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, T}

pub const name = "trim_spaces_around_newlines__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Trims spaces around newlines outside configured subtrees.
pub fn constructor(outside: List(String)) -> Desugarer {
  authoring.no_param_desugarer_with_outside(
    name: name,
    outside: outside,
    transform: inner_param_to_transform,
  )
}

fn inner_param_to_transform(outside: List(String)) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    T(_, _) ->
      vxml
      |> core.trim_ending_spaces_except_last_line
      |> core.trim_starting_spaces_except_first_line
    _ -> vxml
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParamWithOutside) {
  [
    testing.data_no_param_with_outside(
      outside: ["pre"],
      source: "
                <> root
                  <>
                    '  first  '
                    '  middle  '
                    '  last  '
                  <> pre
                    <>
                      '  kept  '
                      '  intact  '
                ",
      expected: "
                <> root
                  <>
                    '  first'
                    'middle'
                    'last  '
                  <> pre
                    <>
                      '  kept  '
                      '  intact  '
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param_with_outside(
    name,
    assertive_tests_data(),
    constructor,
  )
}
