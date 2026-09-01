import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}
import vxml/blame as bl

pub const name = "wrap_children"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps all children of configured parent elements in
/// one new wrapper element.
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
    // Wrapper tag.
    String,
    // Traversal behavior after wrapping.
    TrafficLight,
  )

type InnerParam {
  InnerParam(parent: String, wrapper: String, traffic_light: TrafficLight)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(parent, wrapper, traffic_light) = param
  case core.valid_tag(wrapper) {
    True -> Ok(InnerParam(parent, wrapper, traffic_light))
    False -> Error(DesugaringError(bl.no_blame, "invalid tag for wrapper"))
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = fn(vxml) {
    nodemap(vxml, inner)
  }
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(blame, tag, attrs, children) if tag == inner.parent -> {
      let wrapped_children = [V(blame, inner.wrapper, [], children)]
      #(V(blame, tag, attrs, wrapped_children), inner.traffic_light)
    }
    _ -> #(vxml, Continue)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("div", "wrapper", GoBack),
      source: "
                <> root
                  <> div
                    <> p
                      <> div
                        <>
                          'Hello'
                    <> span
                      <>
                        'World'
                ",
      expected: "
                <> root
                  <> div
                    <> wrapper
                      <> p
                        <> div
                          <>
                            'Hello'
                      <> span
                        <>
                          'World'
                ",
    ),
    testing.data(
      param: #("section", "content", GoBack),
      source: "
                <> root
                  <> section
                ",
      expected: "
                <> root
                  <> section
                    <> content
                ",
    ),
    testing.data(
      param: #("article", "body", GoBack),
      source: "
                <> root
                  <> article
                    <> h1
                      <>
                        'Title'
                    <> footer
                      <>
                        'Footer'
                ",
      expected: "
                <> root
                  <> article
                    <> body
                      <> h1
                        <>
                          'Title'
                      <> footer
                        <>
                          'Footer'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
