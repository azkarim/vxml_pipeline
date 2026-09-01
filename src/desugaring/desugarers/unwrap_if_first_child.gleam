import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}

pub const name = "unwrap_if_first_child"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Repeatedly unwraps matching first children of parent elements.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(node: VXML, inner: InnerParam) -> VXML {
  case node {
    V(_, _, _, children) -> V(..node, children: map_children(children, inner))
    _ -> node
  }
}

fn map_children(children: List(VXML), inner: InnerParam) -> List(VXML) {
  case children {
    [V(_, tag, _, grandchildren), ..more] if tag == inner ->
      case grandchildren {
        [] -> map_children(more, inner)
        _ -> map_children(list.append(grandchildren, more), inner)
      }
    _ -> children
  }
}

type Param =
  // Tag to unwrap when it is the first child.
  String

type InnerParam =
  Param

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: "UnbridgeableTag",
      source: "
                <> Proof
                  <> UnbridgeableTag
                  <> UnbridgeableTag
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <>
                    'some text'
                ",
    ),
    testing.data(
      param: "UnbridgeableTag",
      source: "
                <> Proof
                  <> UnbridgeableTag
                    <> Granchild1
                    <> Granchild2
                  <> UnbridgeableTag
                    <> Granchild3
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <> Granchild1
                  <> Granchild2
                  <> UnbridgeableTag
                    <> Granchild3
                  <>
                    'some text'
                ",
    ),
    testing.data(
      param: "UnbridgeableTag",
      source: "
                <> Proof
                  <> UnbridgeableTag
                    <> UnbridgeableTag
                    <> Granchild2
                  <>
                    'some text'
                ",
      expected: "
                <> Proof
                  <> Granchild2
                  <>
                    'some text'
                ",
    ),
    testing.data(
      param: "UnbridgeableTag",
      source: "
                <> div
                  <> p
                    <>
                      'Text'
                  <> UnbridgeableTag
                  <>
                    'More'
                ",
      expected: "
                <> div
                  <> p
                    <>
                      'Text'
                  <> UnbridgeableTag
                  <>
                    'More'
                ",
    ),
    testing.data(
      param: "span",
      source: "
                <> div
                  <> span
                    <> span
                      <>
                        'Inside'
                ",
      expected: "
                <> div
                  <>
                    'Inside'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
