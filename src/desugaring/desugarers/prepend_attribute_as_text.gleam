import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/option.{Some}
import vxml.{type VXML, Attr, Line, T, V}

pub const name = "prepend_attribute_as_text"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends an attribute value as a text child of every
/// matching element.
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
    // Attribute key.
    String,
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 -> {
      case core.v_first_attr_with_key(vxml, inner.1) {
        Some(Attr(_, _, value)) if value != "" ->
          V(..vxml, children: [
            T(desugarer_blame(53), [Line(desugarer_blame(53), value)]),
            ..children
          ])
        _ -> vxml
      }
    }
    _ -> vxml
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
      param: #("div", "title"),
      source: "
                <> div
                  title='Hello World'
                  <> p
                    <>
                      'Content'
                ",
      expected: "
                <> div
                  title='Hello World'
                  <>
                    ''Hello World''
                  <> p
                    <>
                      'Content'
                ",
    ),
    testing.data(
      param: #("div", "missing"),
      source: "
                <> div
                  class='test'
                  <> p
                    <>
                      'Content'
                ",
      expected: "
                <> div
                  class='test'
                  <> p
                    <>
                      'Content'
                ",
    ),
    testing.data(
      param: #("section", "description"),
      source: "
                <> section
                  description='Line 1\\nLine 2\\nLine 3'
                  <> h1
                    <>
                      'Title'
                ",
      expected: "
                <> section
                  description='Line 1\\nLine 2\\nLine 3'
                  <>
                    ''Line 1\\nLine 2\\nLine 3''
                  <> h1
                    <>
                      'Title'
                ",
    ),
    testing.data(
      param: #("span", "data"),
      source: "
                <> span
                  data=
                  <> em
                    <>
                      'Text'
                ",
      expected: "
                <> span
                  data=
                  <> em
                    <>
                      'Text'
                ",
    ),
    testing.data(
      param: #("section", "title"),
      source: "
                <> div
                  <> section
                    title=Outer Section
                    <> section
                      title=Inner Section
                      <> p
                        <>
                          'Content'
                ",
      expected: "
                <> div
                  <> section
                    title=Outer Section
                    <>
                      'Outer Section'
                    <> section
                      title=Inner Section
                      <>
                        'Inner Section'
                      <> p
                        <>
                          'Content'
                ",
    ),
    testing.data(
      param: #("item", "value"),
      source: "
                <> container
                  <> item
                    value='Parent'
                    <> item
                      value=Child1
                      <> p
                        <>
                          'Text1'
                    <> item
                      value=Child2
                      <> p
                        <>
                          'Text2'
                    <> p
                      <>
                        'Parent Content'
                ",
      expected: "
                <> container
                  <> item
                    value='Parent'
                    <>
                      ''Parent''
                    <> item
                      value=Child1
                      <>
                        'Child1'
                      <> p
                        <>
                          'Text1'
                    <> item
                      value=Child2
                      <>
                        'Child2'
                      <> p
                        <>
                          'Text2'
                    <> p
                      <>
                        'Parent Content'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
