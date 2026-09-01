import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import vxml.{type VXML}

pub const name = "delete_outside_subtrees"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Retains matching subtrees and the ancestor paths leading
/// to them.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  // A node is retained if it or a descendant satisfies this.
  fn(VXML) -> Bool

type InnerParam =
  Param

type State =
  Bool

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(
    State,
  ) =
    n2t.EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(
      on_enter: fn(vxml, state) { on_enter(vxml, state, inner) },
      on_exit: on_exit,
      on_text: fn(vxml, state) { on_text(vxml, state, inner) },
    )
  nodemap
  |> n2t.early_return_one_to_option_enter_exit_stateful_with_child_states_no_error_nodemap_2_desugarer_transform(
    False,
  )
}

fn on_enter(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> #(Option(VXML), State, core.TrafficLight) {
  assert !state
  case inner(vxml) {
    True -> #(Some(vxml), True, core.GoBack)
    False -> #(Some(vxml), False, core.Continue)
  }
}

fn on_exit(
  vxml: VXML,
  original_state: State,
  children_states: List(State),
) -> #(Option(VXML), State) {
  assert !original_state
  case list.any(children_states, function.identity) {
    True -> #(Some(vxml), True)
    False -> #(None, False)
  }
}

fn on_text(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> #(Option(VXML), State) {
  assert !state
  case inner(vxml) {
    True -> #(Some(vxml), True)
    False -> #(None, False)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: core.is_v_and_tag_equals(_, "keep_this"),
      source: "
                <> R
                  <>
                    'hello world'
                  <> blabla
                  <> keep_this
                    <>
                      'hello world'
                ",
      expected: "
                <> R
                  <> keep_this
                    <>
                      'hello world'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
