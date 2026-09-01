import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}
import vxml/blame as bl

pub const name = "wrap_if_not_child_of"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps each occurrence of a target tag in a new
/// parent tag, unless the target is a direct child
/// of one of the specified excluded parent tags.
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
    // Tag to wrap.
    String,
    // Wrapper tag.
    String,
    // Excluded parent tags.
    List(String),
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToOneNoErrorNodemap = fn(vxml, ancestors, _, _, _) {
    nodemap(vxml, ancestors, inner)
  }
  nodemap |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, ancestors: List(VXML), inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 -> {
      let parent_excluded = case list.first(ancestors) {
        Ok(V(_, parent, _, _)) -> list.contains(inner.2, parent)
        _ -> False
      }
      case parent_excluded {
        True -> vxml
        False -> V(blame, inner.1, [], [vxml])
      }
    }
    _ -> vxml
  }
}

const blame = bl.Des([], name, 65)

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("p", "wrapper", ["div"]),
      source: "
                <> root
                  <> div
                    <> p
                      <>
                        'inside excluded'
                  <> section
                    <> p
                      <>
                        'inside allowed'
                ",
      expected: "
                <> root
                  <> div
                    <> p
                      <>
                        'inside excluded'
                  <> section
                    <> wrapper
                      <> p
                        <>
                          'inside allowed'
                ",
    ),
    testing.data(
      param: #("span", "box", ["article", "aside"]),
      source: "
                <> root
                  <> article
                    <> span
                      <>
                        'in article'
                  <> aside
                    <> span
                      <>
                        'in aside'
                  <> div
                    <> span
                      <>
                        'in div'
                ",
      expected: "
                <> root
                  <> article
                    <> span
                      <>
                        'in article'
                  <> aside
                    <> span
                      <>
                        'in aside'
                  <> div
                    <> box
                      <> span
                        <>
                          'in div'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
