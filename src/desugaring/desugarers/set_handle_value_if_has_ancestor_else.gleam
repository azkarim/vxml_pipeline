import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/result
import gleam/string
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "set_handle_value_if_has_ancestor_else"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends one of two handle values according to whether
/// each target has a configured ancestor.
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
    // Required ancestor tag.
    String,
    // Value used inside the ancestor.
    String,
    // Value used outside the ancestor.
    String,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    ancestor_tag: String,
    inside_value: String,
    outside_value: String,
  )
}

type AncestorHasBeenSeen =
  Bool

type State =
  AncestorHasBeenSeen

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, param.3))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneEnterExitStatefulNodemap(State) =
    n2t.OneToOneEnterExitStatefulNodemap(
      on_enter: fn(vxml, state) { v_before_nodemap(vxml, state, inner) },
      on_exit: fn(vxml, original_state, _latest_state) {
        Ok(#(vxml, original_state))
      },
      on_text: fn(vxml, state) { Ok(#(vxml, state)) },
    )
  nodemap
  |> n2t.one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(False)
}

fn v_before_nodemap(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(_, tag, attrs, _) = vxml
  let state = state || tag == inner.ancestor_tag
  case tag == inner.target_tag {
    False -> Ok(#(vxml, state))
    True -> {
      use attrs <- result.try(list.try_map(attrs, map_attr(_, state, inner)))
      Ok(#(V(..vxml, attrs: attrs), state))
    }
  }
}

fn map_attr(
  attr: Attr,
  state: State,
  inner: InnerParam,
) -> Result(Attr, DesugaringError) {
  case attr.key {
    "handle" ->
      case attr.val |> string.split_once(" ") {
        Ok(#(_, handle_value)) ->
          case string.trim(handle_value) == "" {
            True -> Error(malformed_handle_error(attr))
            False -> Ok(attr)
          }
        Error(Nil) -> {
          let appended_value = case state {
            True -> inner.inside_value
            False -> inner.outside_value
          }
          Ok(Attr(..attr, val: attr.val <> " " <> appended_value))
        }
      }
    _ -> Ok(attr)
  }
}

fn malformed_handle_error(attr: Attr) -> DesugaringError {
  DesugaringError(attr.blame, "handle contains a space but no value follows it")
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
