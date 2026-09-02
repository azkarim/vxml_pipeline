import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp, Match}
import gleam/result
import vxml.{type Attr, type VXML, Attr, V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "writerly_handles_set_value_if_has_ancestor_else"

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
    handle_regexp: Regexp,
  )
}

type AncestorHasBeenSeen =
  Bool

type State =
  AncestorHasBeenSeen

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(handle_regexp) =
    regexp.from_string(
      "^(" <> handle_syntax.decorated_name_pattern <> ")(?: <<(.*)>>)?$",
    )
  Ok(InnerParam(param.0, param.1, param.2, param.3, handle_regexp))
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
      case regexp.scan(inner.handle_regexp, attr.val) {
        [Match(_, [Some(_)]), ..] -> {
          let appended_value = case state {
            True -> inner.inside_value
            False -> inner.outside_value
          }
          Ok(
            Attr(
              ..attr,
              val: attr.val <> " " <> handle_syntax.encode_value(appended_value),
            ),
          )
        }
        [Match(_, [Some(_), _]), ..] -> Ok(attr)
        _ -> Error(malformed_handle_error(attr))
      }
    _ -> Ok(attr)
  }
}

fn malformed_handle_error(attr: Attr) -> DesugaringError {
  DesugaringError(
    attr.blame,
    "handle attr must have form <name> or <name> <<value>>; found: “"
      <> attr.val
      <> "”",
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("Item", "Appendix", "appendix value", "ordinary value"),
      source: "
        <> root
          <> Appendix
            <> Item
              handle=inside
          <> Item
            handle=outside#page
          <> Item
            handle=assigned <<existing>>
      ",
      expected: "
        <> root
          <> Appendix
            <> Item
              handle=inside <<appendix value>>
          <> Item
            handle=outside#page <<ordinary value>>
          <> Item
            handle=assigned <<existing>>
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
