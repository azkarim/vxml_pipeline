import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}
import vxml/blame as bl

pub const name = "wrap_and_steal"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps configured elements while moving children with
/// specified tags above or below them.
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
    // Wrapper tag.
    String,
    // Tags of children moved above the target.
    List(String),
    // Tags of children moved below the target.
    List(String),
  )

type InnerParam {
  InnerParam(
    target: String,
    wrapper: VXML,
    move_above: List(String),
    move_below: List(String),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(target, wrapper, move_above, move_below) = param
  Ok(InnerParam(
    target,
    V(desugarer_blame(51), wrapper, [], []),
    move_above,
    move_below,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = fn(vxml) { nodemap(vxml, inner) }
  nodemap |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.target -> {
      let wrapper = inner.wrapper
      let assert V(..) = wrapper
      let #(above, children) =
        list.partition(children, core.is_v_and_tag_is_one_of(
          _,
          inner.move_above,
        ))
      let #(below, children) =
        list.partition(children, core.is_v_and_tag_is_one_of(
          _,
          inner.move_below,
        ))
      let vxml = V(..vxml, children: children)
      V(..wrapper, children: [above, [vxml], below] |> list.flatten)
    }
    _ -> vxml
  }
}

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("p", "wrapper", ["mister"], []),
      source: "
                <> root
                  <> div
                    <> p
                      <> none
                      <>
                        'Hello'
                      <> mister
                    <> span
                      <>
                        'World'
                ",
      expected: "
                <> root
                  <> div
                    <> wrapper
                      <> mister
                      <> p
                        <> none
                        <>
                          'Hello'
                    <> span
                      <>
                        'World'
                ",
    ),
    testing.data(
      param: #("section", "container", [], ["mister"]),
      source: "
                <> root
                  <> section
                    <> mister
                    <> h1
                      <>
                        'Title'
                ",
      expected: "
                <> root
                  <> container
                    <> section
                      <> h1
                        <>
                          'Title'
                    <> mister
                ",
    ),
    testing.data(
      param: #("article", "main", [], ["mister"]),
      source: "
                <> root
                  <> article
                    <> mister
                    <> none
                    <> mister
                    <> none
                    <> h1
                      <>
                        'Title'
                    <> footer
                      <>
                        'Footer'
                ",
      expected: "
                <> root
                  <> main
                    <> article
                      <> none
                      <> none
                      <> h1
                        <>
                          'Title'
                      <> footer
                        <>
                          'Footer'
                    <> mister
                    <> mister
                ",
    ),
    testing.data(
      param: #("p", "wrapper", ["a"], ["b"]),
      source: "
                <> root
                  <> div
                    <> p
                      <> b
                      <> a
                      <> b
                      <>
                        'First paragraph'
                      <> a
                    <> section
                      <> p
                        <>
                          'Second paragraph'
                      <> p
                        <>
                          'Third paragraph'
                ",
      expected: "
                <> root
                  <> div
                    <> wrapper
                      <> a
                      <> a
                      <> p
                        <>
                          'First paragraph'
                      <> b
                      <> b
                    <> section
                      <> wrapper
                        <> p
                          <>
                            'Second paragraph'
                      <> wrapper
                        <> p
                          <>
                            'Third paragraph'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
