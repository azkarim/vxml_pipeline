import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type VXML, T, V}

pub const name = "check_tags"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Rejects any element whose tag is absent from the
/// supplied approved-tag list.
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
    // Approved tags.
    List(String),
    // Description of the list's source or purpose.
    String,
  )

type InnerParam {
  InnerParam(approved_tags: List(String), list_description: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(blame, tag, _, _) -> {
      case list.contains(inner.approved_tags, tag) {
        True -> Ok(vxml)
        False ->
          Error(DesugaringError(
            blame,
            "tag '"
              <> tag
              <> "' is not in approved "
              <> inner.list_description
              <> " list of tags: "
              <> string.inspect(inner.approved_tags),
          ))
      }
    }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #(["root", "div", "p", "span"], "test1"),
      source: "
                <> root
                  <> div
                    <> p
                      <>
                        'Hello'
                    <> span
                      <>
                        'World'
                ",
      expected: "
                <> root
                  <> div
                    <> p
                      <>
                        'Hello'
                    <> span
                      <>
                        'World'
                ",
    ),
    testing.data(
      param: #(["root", "section", "h1"], "test2"),
      source: "
                <> root
                  <> section
                    <> h1
                      <>
                        'Title'
                ",
      expected: "
                <> root
                  <> section
                    <> h1
                      <>
                        'Title'
                ",
    ),
  ]
}

// Note: Error testing support is not available,
// so we only include assertive tests for valid cases.
// Invalid cases would result in DesugaringError at runtime.

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
