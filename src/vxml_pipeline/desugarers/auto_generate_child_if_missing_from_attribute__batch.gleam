import gleam/list
import gleam/result
import gleam/string
import on
import vxml.{type VXML, Line, T, V}
import vxml/blame as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "auto_generate_child_if_missing_from_attribute__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends children populated from attributes when matching
/// parents have the configured attribute but no child of the
/// requested tag. Repeated parent tags are allowed.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: core.list_param_stringifier(param),
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Parent tag.
      String,
      // Generated child tag.
      String,
      // Source attribute key.
      String,
    ),
  )

type InnerParam {
  InnerParam(parent_tag: String, child_tag: String, attr_key: String)
}

fn param_to_inner_param(
  param: Param,
) -> Result(List(InnerParam), DesugaringError) {
  list.try_map(param, fn(item) {
    use <- on.false_true(core.valid_tag(item.0), fn() {
      Error(DesugaringError(
        bl.no_blame,
        "invalid parent tag name '" <> item.0 <> "'",
      ))
    })
    use <- on.false_true(core.valid_tag(item.1), fn() {
      Error(DesugaringError(
        bl.no_blame,
        "invalid child tag name '" <> item.1 <> "'",
      ))
    })
    use <- on.false_true(result.is_ok(vxml.validate_key(item.2)), fn() {
      Error(DesugaringError(
        bl.no_blame,
        "invalid attribute key '" <> item.2 <> "'",
      ))
    })
    Ok(InnerParam(item.0, item.1, item.2))
  })
}

fn inner_param_to_transform(inner: List(InnerParam)) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: List(InnerParam)) -> VXML {
  list.fold(inner, vxml, apply_one)
}

fn apply_one(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.parent_tag -> {
      case core.v_children_with_tag(vxml, inner.child_tag) {
        [_, ..] -> vxml
        [] ->
          case core.v_attrs_with_key(vxml, inner.attr_key) {
            [attr, ..] ->
              V(..vxml, children: [
                V(authoring.blame(name, 93), inner.child_tag, [], [
                  T(attr.blame, [
                    Line(
                      attr.blame
                        |> bl.advance(string.length(inner.attr_key) + 1),
                      attr.val,
                    ),
                  ]),
                ]),
                ..vxml.children
              ])
            [] -> vxml
          }
      }
    }
    _ -> vxml
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [
        #("Chapter", "ChapterTitle", "title"),
        #("Chapter", "ShortTitle", "short-title"),
        #("Section", "SectionTitle", "title"),
      ],
      source: "
                  <> root
                    <> Chapter
                      title=Introduction
                      short-title=Intro
                      <> ChapterTitle
                        <>
                          'Existing title'
                      <> Section
                        title=Overview
                    <> Chapter
                      title=Appendix
                ",
      expected: "
                  <> root
                    <> Chapter
                      title=Introduction
                      short-title=Intro
                      <> ShortTitle
                        <>
                          'Intro'
                      <> ChapterTitle
                        <>
                          'Existing title'
                      <> Section
                        title=Overview
                        <> SectionTitle
                          <>
                            'Overview'
                    <> Chapter
                      title=Appendix
                      <> ChapterTitle
                        <>
                          'Appendix'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
