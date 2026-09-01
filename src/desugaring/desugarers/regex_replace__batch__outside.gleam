import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/regex_replace_engine as engine
import desugaring/testing

pub const name = "regex_replace__batch__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Applies multiple regular-expression replacements outside
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
  List(
    #(
      // Regular-expression pattern.
      String,
      // Replacement text.
      String,
    ),
  )

type InnerParam =
  List(engine.Rule)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  engine.prepare_batch(param)
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = engine.nodemap_batch(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: [#("[0-9]+", "#"), #("_+", "-")],
      outside: ["Protected"],
      source: "
                <> root
                  <>
                    'item_12'
                  <> Protected
                    <>
                      'item_34'
                ",
      expected: "
                <> root
                  <>
                    'item-#'
                  <> Protected
                    <>
                      'item_34'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
