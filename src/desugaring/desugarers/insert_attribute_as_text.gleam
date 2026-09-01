import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/option.{Some}
import vxml.{type VXML, Attr, V}

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
    V(_, tag, _, _) if tag == inner.0 -> {
      case core.v_first_attr_with_key(vxml, inner.1) {
        Some(Attr(_, _, value)) if value != "" ->
          core.v_start_insert_text(vxml, value)
        _ -> vxml
      }
    }
    _ -> vxml
  }
}

type Param =
  #(
    // Target element name.
    String,
    // Attribute key whose value is inserted.
    String,
  )

type InnerParam =
  Param

pub const name = "insert_attribute_as_text"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Given arguments
/// ```
/// tag, attr_key
/// ```
/// insert the value of the attr with key
/// 'attr_key' into the first line of the first
/// text node child of the tag, or else as a text
/// node unto itself if the first child is not a
/// text node. If the attr doesn't exist, the node
/// is left unchanged. The attr value is used
/// as-is without any newline splitting. Empty
/// attr values are ignored.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
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
                    value=Parent
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
                    value=Parent
                    <>
                      'Parent'
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
    testing.data(
      param: #("item", "value"),
      source: "
                <> container
                  <> item
                    value=Parent
                    <> item
                      value=Child1
                      <>
                        'Text1'
                    <> item
                      value=Child2
                      <>
                        'Text2'
                    <> p
                      <>
                        'Parent Content'
                ",
      expected: "
                <> container
                  <> item
                    value=Parent
                    <>
                      'Parent'
                    <> item
                      value=Child1
                      <>
                        'Child1Text1'
                    <> item
                      value=Child2
                      <>
                        'Child2Text2'
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
