import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "prepend_counter_incrementing_attribute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a counter-increment instruction attribute to
/// matching elements.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Target tag.
    String,
    // Counter name.
    String,
    // Whether to traverse matching descendants.
    TrafficLight,
  )

type InnerParam =
  #(String, Attr, TrafficLight)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(
    param.0,
    Attr(desugarer_blame(42), "_", param.1 <> " ::++" <> param.1),
    param.2,
  )
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, attrs, _) if tag == inner.0 -> #(
      V(..vxml, attrs: [inner.1, ..attrs]),
      inner.2,
    )
    _ -> #(vxml, Continue)
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("Chapter", "ChapterCounter", GoBack),
      source: "
                  <> root
                    <> Chapter
                      title=Introduction
                      <>
                        'Chapter content'
                      <> Chapter
                        title=Should not change
                    <> Chapter
                      title=Advanced Topics
                      <>
                        'More content'
                      <> Chapter
                        title=Should not change
                    <> OtherElement
                      <>
                        'Should not change'
                ",
      expected: "
                  <> root
                    <> Chapter
                      _=ChapterCounter ::++ChapterCounter
                      title=Introduction
                      <>
                        'Chapter content'
                      <> Chapter
                        title=Should not change
                    <> Chapter
                      _=ChapterCounter ::++ChapterCounter
                      title=Advanced Topics
                      <>
                        'More content'
                      <> Chapter
                        title=Should not change
                    <> OtherElement
                      <>
                        'Should not change'
                ",
    ),
    testing.data(
      param: #("Sub", "SubCounter", Continue),
      source: "
                  <> root
                    <> Sub
                      title=Overview
                      <>
                        'Sub content'
                      <> Sub
                        title=Details
                        <>
                          'More sub content'
                    <> Chapter
                      title=Should not change
                      <>
                        'Chapter content'
                ",
      expected: "
                  <> root
                    <> Sub
                      _=SubCounter ::++SubCounter
                      title=Overview
                      <>
                        'Sub content'
                      <> Sub
                        _=SubCounter ::++SubCounter
                        title=Details
                        <>
                          'More sub content'
                    <> Chapter
                      title=Should not change
                      <>
                        'Chapter content'
                ",
    ),
    testing.data(
      param: #("Exercise", "ExerciseCounter", Continue),
      source: "
                  <> root
                    <> Exercise
                      number=1
                      <> Exercise
                        number=nested
                        <>
                          'Nested exercise'
                      <>
                        'Exercise content'
                    <> Section
                      <>
                        'Section content'
                ",
      expected: "
                  <> root
                    <> Exercise
                      _=ExerciseCounter ::++ExerciseCounter
                      number=1
                      <> Exercise
                        _=ExerciseCounter ::++ExerciseCounter
                        number=nested
                        <>
                          'Nested exercise'
                      <>
                        'Exercise content'
                    <> Section
                      <>
                        'Section content'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
