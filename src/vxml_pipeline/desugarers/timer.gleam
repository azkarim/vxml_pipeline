import vxml_pipeline/authoring
import vxml_pipeline/core.{type Desugarer, type DesugarerTransform}
import vxml_pipeline/testing

pub const name = "timer"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Marks a timing position without changing the VXML.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn inner_param_to_transform() -> DesugarerTransform {
  fn(vxml) { Ok(#(vxml, [])) }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    testing.data_no_param(
      source: "
                <> root
                  <> p
                    <>
                      'unchanged'
                ",
      expected: "
                <> root
                  <> p
                    <>
                      'unchanged'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
