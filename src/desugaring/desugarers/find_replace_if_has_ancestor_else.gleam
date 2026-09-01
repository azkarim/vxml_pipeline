import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML}

pub const name = "find_replace_if_has_ancestor_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Uses one literal replacement inside the configured
/// ancestors and another replacement outside them.
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
    // Ancestor tags.
    List(String),
    // Replacement used inside a matching ancestor.
    #(String, String),
    // Replacement used outside a matching ancestor.
    #(String, String),
  )

type InnerParam {
  InnerParam(
    ancestor_tags: List(String),
    inside_from: String,
    inside_to: String,
    outside_from: String,
    outside_to: String,
  )
}

type State {
  State(has_seen_ancestor: Bool, from: String, to: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(ancestor_tags, inside, outside) = param
  let #(inside_from, inside_to) = inside
  let #(outside_from, outside_to) = outside
  Ok(InnerParam(ancestor_tags, inside_from, inside_to, outside_from, outside_to))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneEnterExitStatefulNoErrorNodemap(State) =
    n2t.OneToOneEnterExitStatefulNoErrorNodemap(
      on_enter: fn(vxml, state) { on_enter(vxml, state, inner) },
      on_exit: on_exit,
      on_text: on_text,
    )

  let initial_state = State(False, inner.outside_from, inner.outside_to)
  nodemap
  |> n2t.one_to_one_enter_exit_stateful_no_error_nodemap_2_desugarer_transform(
    initial_state,
  )
}

fn on_enter(vxml: VXML, state: State, inner: InnerParam) -> #(VXML, State) {
  let state = case
    state.has_seen_ancestor
    || !list.contains(inner.ancestor_tags, core.v_get_tag(vxml))
  {
    True -> state
    False -> State(True, inner.inside_from, inner.inside_to)
  }
  #(vxml, state)
}

fn on_exit(
  vxml: VXML,
  original_state: State,
  _latest_state: State,
) -> #(VXML, State) {
  #(vxml, original_state)
}

fn on_text(vxml: VXML, state: State) -> #(VXML, State) {
  #(core.t_find_replace(vxml, state.from, state.to), state)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #(["special"], #("``", "“"), #("``", "`")),
      source: "
                <> root
                  <> special
                    <>
                      'First line ``'
                      'Second line ``'
                  <> ordinary
                    <>
                      'Outside special ``'
                ",
      expected: "
                <> root
                  <> special
                    <>
                      'First line “'
                      'Second line “'
                  <> ordinary
                    <>
                      'Outside special `'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
