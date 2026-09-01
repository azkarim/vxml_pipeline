import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}
import vxml/blame as bl

pub const name = "wrap_children_avoiding"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps runs of children except elements bearing the
/// avoided or wrapper tag.
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
    // Tag whose elements split the wrapped runs.
    String,
    // Traversal behavior after wrapping.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    parent: String,
    wrapper: String,
    avoiding: String,
    traffic_light: TrafficLight,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(parent, wrapper, avoiding, traffic_light) = param
  case core.valid_tag(wrapper) {
    True -> Ok(InnerParam(parent, wrapper, avoiding, traffic_light))
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
    V(_, tag, _, children) if tag == inner.parent -> {
      let children = wrap_in_list([], [], children, inner)
      #(V(..vxml, children: children), inner.traffic_light)
    }
    _ -> #(vxml, Continue)
  }
}

fn wrap_in_list(
  already_wrapped: List(VXML),
  currently_being_wrapped: List(VXML),
  upcoming: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case upcoming {
    [] ->
      case currently_being_wrapped {
        [] -> list.reverse(already_wrapped)
        _ -> {
          let wrapper =
            V(
              desugarer_blame(87),
              inner.wrapper,
              [],
              list.reverse(currently_being_wrapped),
            )
          list.reverse([wrapper, ..already_wrapped])
        }
      }
    [V(_, tag, _, _) as first, ..rest]
      if tag == inner.avoiding || tag == inner.wrapper
    ->
      case currently_being_wrapped {
        [] -> wrap_in_list([first, ..already_wrapped], [], rest, inner)
        _ -> {
          let wrapper =
            V(
              desugarer_blame(103),
              inner.wrapper,
              [],
              list.reverse(currently_being_wrapped),
            )
          wrap_in_list([first, wrapper, ..already_wrapped], [], rest, inner)
        }
      }
    [first, ..rest] ->
      wrap_in_list(
        already_wrapped,
        [first, ..currently_being_wrapped],
        rest,
        inner,
      )
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
      param: #("parent", "wrapper", "avoid_me", GoBack),
      source: "
                <> root
                  <> parent
                    <> p
                    <> q
                    <> avoid_me
                    <> avoid_me
                    <> q
                ",
      expected: "
                <> root
                  <> parent
                    <> wrapper
                      <> p
                      <> q
                    <> avoid_me
                    <> avoid_me
                    <> wrapper
                      <> q
                ",
    ),
    testing.data(
      param: #("parent", "wrapper", "avoid_me", GoBack),
      source: "
                <> root
                  <> parent
                    <> wrapper
                    <> p
                    <> q
                    <> wrapper
                    <> avoid_me
                    <> avoid_me
                    <> q
                ",
      expected: "
                <> root
                  <> parent
                    <> wrapper
                    <> wrapper
                      <> p
                      <> q
                    <> wrapper
                    <> avoid_me
                    <> avoid_me
                    <> wrapper
                      <> q
                ",
    ),
    testing.data(
      param: #("parent", "wrapper", "avoid_me", GoBack),
      source: "
                <> root
                  <> parent
                    <> avoid_me
                    <> p1
                    <> p2
                    <> p3
                    <> avoid_me
                ",
      expected: "
                <> root
                  <> parent
                    <> avoid_me
                    <> wrapper
                      <> p1
                      <> p2
                      <> p3
                    <> avoid_me
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
