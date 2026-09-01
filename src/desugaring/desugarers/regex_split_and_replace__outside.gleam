import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/split_replacement as sr
import desugaring/testing

pub const name = "regex_split_and_replace__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Applies a regular-expression splitting and replacement
/// rule outside configured subtrees.
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
  sr.RegexpSplitRule

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToManyNoErrorNodemap = sr.apply_regexp_split_rule(
    _,
    inner,
  )
  nodemap
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: sr.regexp_split_rule("_", sr.Tag("Marker")),
      outside: ["Protected"],
      source: "
                <> root
                  <>
                    'before_after'
                  <> Protected
                    <>
                      'keep_this'
                ",
      expected: "
                <> root
                  <>
                    'before'
                  <> Marker
                  <>
                    'after'
                  <> Protected
                    <>
                      'keep_this'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
