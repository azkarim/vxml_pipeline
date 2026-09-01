import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

pub const name = "wrap_if_first_child_of"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps the first child of each configured parent in a
/// new wrapper element.
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
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
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
    V(blame, tag, attrs, children) if tag == inner.0 ->
      case children {
        [first, ..rest] -> {
          let children = [V(blame, inner.1, [], [first]), ..rest]
          #(V(blame, tag, attrs, children), GoBack)
        }
        [] -> #(vxml, GoBack)
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
      param: #("parent", "wrapper"),
      source: "
        <> parent
          <> child1
          <> child2
      ",
      expected: "
        <> parent
          <> wrapper
            <> child1
          <> child2
      ",
    ),
    testing.data(
      param: #("parent", "wrapper"),
      source: "
        <> parent
      ",
      expected: "
        <> parent
      ",
    ),
    testing.data(
      param: #("parent", "wrapper"),
      source: "
        <> parent
          <>
            'text node'
          <> child
      ",
      expected: "
        <> parent
          <> wrapper
            <>
              'text node'
          <> child
      ",
    ),
    testing.data(
      param: #("parent", "wrapper"),
      source: "
        <> root
          <> parent
            <> child1
          <> parent
            <> child2
      ",
      expected: "
        <> root
          <> parent
            <> wrapper
              <> child1
          <> parent
            <> wrapper
              <> child2
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}

import desugaring/authoring
