import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "find_replace__batch__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Applies each literal replacement to text nodes outside
/// the listed subtrees.
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
  List(
    #(
      // Text to replace.
      String,
      // Replacement text.
      String,
    ),
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = core.find_replace_if_t__batch(
    _,
    inner,
  )
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_outside(outside)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: [#("from", "to")],
      outside: ["keep_out"],
      source: "
                <> root
                  <> A
                    <> B
                      <>
                        'from a thing'
                        'to a thing'
                      <> keep_out
                        <>
                          'from a thing'
                          'to a thing'
                    <> keep_out
                      <> B
                        <>
                          'from a thing'
                          'to a thing'
                ",
      expected: "
                <> root
                  <> A
                    <> B
                      <>
                        'to a thing'
                        'to a thing'
                      <> keep_out
                        <>
                          'from a thing'
                          'to a thing'
                    <> keep_out
                      <> B
                        <>
                          'from a thing'
                          'to a thing'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
