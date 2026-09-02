import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, Some}
import on
import vxml.{type VXML, V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning, DesugaringError, DesugaringWarning,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneEnterExitStatefulWithWarningsNodemap(
    State,
  ) =
    n2t.EarlyReturnOneToOneEnterExitStatefulWithWarningsNodemap(
      on_enter: fn(vxml, state) { v_before(vxml, state, inner) },
      on_exit: v_after,
      on_text: fn(vxml, state) { Ok(#(vxml, state, [])) },
    )
  n2t.early_return_one_to_one_enter_exit_stateful_with_warnings_nodemap_2_desugarer_transform(
    nodemap,
    State(dict.new(), []),
  )
}

fn v_before(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(
  #(VXML, State, List(DesugaringWarning), core.TrafficLight),
  DesugaringError,
) {
  let assert V(_, tag, _, children) = vxml

  case tag {
    "GrandWrapper" -> {
      use remaining <- on.ok(collect_unused_ids(children))
      let state = State(..state, remaining: remaining)
      Ok(#(vxml, state, [], traffic_light(remaining)))
    }

    "Handle" -> Ok(#(vxml, state, [], core.GoBack))

    _ -> {
      let state = case our_id(vxml) {
        Some(id) ->
          case dict.get(state.remaining, id) {
            Ok(names) ->
              State(
                remaining: dict.delete(state.remaining, id),
                warnings: core.pour(
                  warnings_for(names |> list.reverse, vxml, inner),
                  state.warnings,
                ),
              )
            Error(_) -> state
          }
        _ -> state
      }
      Ok(#(vxml, state, [], traffic_light(state.remaining)))
    }
  }
}

fn collect_unused_ids(
  children: List(VXML),
) -> Result(Dict(String, List(String)), DesugaringError) {
  list.try_fold(children, dict.new(), fn(acc, child) {
    case child {
      V(_, "Handle", _, _) -> {
        let name = core.v_first_attr_with_key(child, "name")
        let id = core.v_first_attr_with_key(child, "id")
        let used = core.v_first_attr_with_key(child, "used")
        case name, id, used {
          Some(_), Some(_), Some(used) if used.val == "true" -> Ok(acc)
          Some(name), Some(id), Some(used) if used.val == "false" ->
            Ok(
              dict.upsert(acc, id.val, fn(existing) {
                [name.val, ..option.unwrap(existing, [])]
              }),
            )
          _, _, _ ->
            Error(DesugaringError(
              child.blame,
              "Handle element is malformed or has no valid 'used' attribute "
                <> "(run handles_grand_wrapper_substitute first)",
            ))
        }
      }
      _ -> Ok(acc)
    }
  })
}

fn traffic_light(remaining: Dict(String, List(String))) -> core.TrafficLight {
  case dict.is_empty(remaining) {
    True -> core.GoBack
    False -> core.Continue
  }
}

fn our_id(vxml: VXML) -> Option(String) {
  core.v_first_attr_with_key(vxml, "id")
  |> option.map(fn(attr) { attr.val })
}

fn warnings_for(
  names: List(String),
  vxml: VXML,
  inner: InnerParam,
) -> List(DesugaringWarning) {
  let assert V(blame, tag, _, _) = vxml
  case list.contains(inner, tag) {
    False -> []
    True ->
      names
      |> list.map(fn(name) {
        DesugaringWarning(
          blame,
          "handle '"
            <> name
            <> "' is defined on a '"
            <> tag
            <> "' element but is never used",
        )
      })
  }
}

fn v_after(
  vxml: VXML,
  _original_state: State,
  latest_state: State,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, tag, _, _) = vxml
  case tag {
    // the GrandWrapper is the root: this is the one and only place where
    // the accumulated warnings are handed over to the pipeline
    "GrandWrapper" ->
      Ok(#(vxml, latest_state, latest_state.warnings |> list.reverse))
    _ -> Ok(#(vxml, latest_state, []))
  }
}

type State {
  State(
    // id -> names of the handles that point to it, for handles that the
    // GrandWrapper dictionary marks as unused; an entry is dropped as
    // soon as the node bearing that id is reached
    remaining: Dict(String, List(String)),
    // the early-return walker drops the warnings returned by
    // on_enter whenever it is told to GoBack, so we
    // accumulate them in the state and emit them all at the root instead
    warnings: List(DesugaringWarning),
  )
}

type Param =
  List(String)

// tags for which an unused handle is worth warning about
type InnerParam =
  Param

pub const name = "handles_grand_wrapper_warn_unused"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Expects a document whose root is a 'GrandWrapper'
/// carrying structured `Handle` children whose boolean
/// `used` attrs were added by `handles_grand_wrapper_substitute`.
///
/// Emits one DesugaringWarning per handle whose
/// `used` attr is `false` and whose id points to a
/// node whose tag is listed in the param, blamed on
/// that node. (Passing ["MathBlock"] therefore
/// reports unused equation handles.)
///
/// Handles on nodes of any other tag are silently
/// ignored, as are ids that no node carries.
///
/// Leaves the tree unchanged; must run before the
/// GrandWrapper is unwrapped.
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
    // Test 1: unused handle on a MathBlock -> tree unchanged (the
    // warning itself is not observable through assertive tests)
    testing.data(
      param: ["MathBlock"],
      source: "
        <> GrandWrapper
          <> Handle
            name=eq:unused
            page=false
            value=<<(1.1)>>
            id=_1_h.a.i_
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=_1_h.a.i_
                <>
                  'x = y'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=eq:unused
            page=false
            value=<<(1.1)>>
            id=_1_h.a.i_
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=_1_h.a.i_
                <>
                  'x = y'
      ",
    ),

    // Test 2: used handle on a MathBlock -> tree unchanged
    testing.data(
      param: ["MathBlock"],
      source: "
        <> GrandWrapper
          <> Handle
            name=eq:used
            page=false
            value=<<(1.1)>>
            id=_1_h.a.i_
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=_1_h.a.i_
                <>
                  'x = y'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=eq:used
            page=false
            value=<<(1.1)>>
            id=_1_h.a.i_
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=_1_h.a.i_
                <>
                  'x = y'
      ",
    ),

    // Test 3: unused handle on a non-listed tag -> tree unchanged
    testing.data(
      param: ["MathBlock"],
      source: "
        <> GrandWrapper
          <> Handle
            name=sec:intro
            page=false
            value=<<1.1>>
            id=_1_h.a.i_
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <> Section
                id=_1_h.a.i_
                <>
                  'Introduction'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=sec:intro
            page=false
            value=<<1.1>>
            id=_1_h.a.i_
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <> Section
                id=_1_h.a.i_
                <>
                  'Introduction'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
