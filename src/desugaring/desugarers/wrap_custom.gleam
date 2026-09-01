import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, T, V}
import vxml/blame as bl

pub const name = "wrap_custom"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps each configured element in a supplied V-node
/// wrapper, replacing any existing wrapper children.
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
    // VXML wrapper.
    VXML,
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  case param.1 {
    V(..) -> Ok(param)
    T(..) -> Error(DesugaringError(bl.no_blame, "expecting V-node as wrapper"))
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = fn(vxml) { nodemap(vxml, inner) }
  nodemap |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 -> {
      let wrapper = inner.1
      case wrapper {
        V(..) -> V(..wrapper, children: [vxml])
        T(..) -> vxml
      }
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
  let wrapper = V(desugarer_blame(65), "wrapper", [], [])
  let container = V(desugarer_blame(66), "container", [], [])
  let main = V(desugarer_blame(67), "main", [], [])
  [
    testing.data(
      param: #("p", wrapper),
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
                    <> wrapper
                      <> p
                        <>
                          'Hello'
                    <> span
                      <>
                        'World'
                ",
    ),
    testing.data(
      param: #("section", container),
      source: "
                <> root
                  <> section
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
                ",
    ),
    testing.data(
      param: #("article", main),
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
                  <> main
                    <> article
                      <> h1
                        <>
                          'Title'
                      <> footer
                        <>
                          'Footer'
                ",
    ),
    testing.data(
      param: #("p", wrapper),
      source: "
                <> root
                  <> div
                    <> p
                      <>
                        'First paragraph'
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
                      <> p
                        <>
                          'First paragraph'
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
