import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/string
import on
import vxml.{type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "auto_generate_child_if_missing_from_attribute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a child populated from an attribute when a
/// matching parent has the attribute but no child of the
/// requested tag.
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
    // Parent tag.
    String,
    // Generated child tag.
    String,
    // Source attribute key.
    String,
  )

type InnerParam {
  InnerParam(parent_tag: String, child_tag: String, attr_key: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, _, _) if tag == inner.parent_tag -> {
      // return early if we have a child of tag child_tag:
      use <- on.nonempty_empty(
        core.v_children_with_tag(vxml, inner.child_tag),
        fn(_, _) { #(vxml, GoBack) },
      )

      // return early if we don't have an attr of key attr_key:
      use attr, _ <- on.empty_nonempty(
        core.v_attrs_with_key(vxml, inner.attr_key),
        fn() { #(vxml, GoBack) },
      )

      #(
        V(..vxml, children: [
          V(authoring.blame(name, 71), inner.child_tag, [], [
            T(attr.blame, [
              Line(
                attr.blame |> bl.advance(string.length(inner.attr_key) + 1),
                attr.val,
              ),
            ]),
          ]),
          ..vxml.children
        ]),
        GoBack,
      )
    }
    _ -> #(vxml, Continue)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("Chapter", "ChapterTitle", "title"),
      source: "
                  <> root
                    <> Chapter
                      title=Einleitung
                      <>
                        'Chapter content'
                    <> Chapter
                      title=Advanced Topics
                      <> ChapterTitle
                        <>
                          'Existing title'
                      <>
                        'More content'
                    <> Chapter
                      <>
                        'No title attr'
                    <> OtherElement
                      title=Should not change
                      <>
                        'Other content'
                ",
      expected: "
                  <> root
                    <> Chapter
                      title=Einleitung
                      <> ChapterTitle
                        <>
                          'Einleitung'
                      <>
                        'Chapter content'
                    <> Chapter
                      title=Advanced Topics
                      <> ChapterTitle
                        <>
                          'Existing title'
                      <>
                        'More content'
                    <> Chapter
                      <>
                        'No title attr'
                    <> OtherElement
                      title=Should not change
                      <>
                        'Other content'
                ",
    ),
    testing.data(
      param: #("Sub", "SubTitle", "title"),
      source: "
                  <> root
                    <> Sub
                      title=Overview
                      <>
                        'Sub content'
                    <> Sub
                      title=Details
                      <> SubTitle
                        <>
                          'Existing subtitle'
                      <>
                        'More sub content'
                    <> Sub
                      <>
                        'No title attr'
                    <> Chapter
                      title=Should not change
                      <>
                        'Chapter content'
                ",
      expected: "
                  <> root
                    <> Sub
                      title=Overview
                      <> SubTitle
                        <>
                          'Overview'
                      <>
                        'Sub content'
                    <> Sub
                      title=Details
                      <> SubTitle
                        <>
                          'Existing subtitle'
                      <>
                        'More sub content'
                    <> Sub
                      <>
                        'No title attr'
                    <> Chapter
                      title=Should not change
                      <>
                        'Chapter content'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
