import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/line_wrapping
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/int
import gleam/list
import vxml.{type VXML, Line, T, V}
import vxml/blame.{Des}

pub const name = "line_rewrap_no2__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Rewraps lines within configured width and indentation
/// limits while reserving space for selected elements.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Element names that reset indentation to zero.
    List(String),
    // Maximum line length.
    Int,
    // Minimum line length.
    Int,
    // Width reduction at each nesting level.
    Int,
    // Whether an element will later be folded into text.
    fn(VXML) -> Bool,
  )

type InnerParam {
  InnerParam(
    zero_indent_tags: List(String),
    maximum_length: Int,
    minimum_length: Int,
    nesting_width_reduction: Int,
    will_fold_into_text: fn(VXML) -> Bool,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, param.3, param.4))
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToOneEnterExitStatefulNoErrorNodemap(State) =
    n2t.OneToOneEnterExitStatefulNoErrorNodemap(
      on_enter: fn(v: VXML, s: State) { v_before(v, s, inner) },
      on_exit: fn(v: VXML, o: State, s: State) { v_after(v, o, s, inner) },
      on_text: fn(v, state) { #(v, state) },
    )
  nodemap
  |> n2t.one_to_one_enter_exit_stateful_no_error_nodemap_2_desugarer_transform_with_forbidden(
    0,
    outside,
  )
}

type State =
  Int

const const_blame = Des([], name, 71)

const one_empty_line = T(const_blame, [Line(const_blame, "")])

fn line_wrap_in_list(
  already_wrapped: List(VXML),
  deficit: Int,
  last_was_text: Bool,
  remaining: List(VXML),
  line_length: Int,
  incorporating_condition: fn(VXML) -> Bool,
) -> List(VXML) {
  case remaining {
    [] -> already_wrapped |> list.reverse
    [T(blame, lines), ..rest] -> {
      let deficit = case last_was_text {
        True -> 0
        False -> deficit
      }
      let #(lines, new_indent) =
        line_wrapping.rewrap_lines(lines, deficit, line_length)
      line_wrap_in_list(
        [T(blame, lines), ..already_wrapped],
        new_indent,
        True,
        rest,
        line_length,
        incorporating_condition,
      )
    }
    [V(_, _, _, _) as first, ..rest] -> {
      let deficit = case incorporating_condition(first) {
        True -> core.total_chars(first) + deficit
        False -> 0
      }
      let #(deficit, already_wrapped) = case deficit > line_length {
        True -> #(
          // this can only occur if the V-node is incorporated
          // (else deficit == 0), and in which case we want that
          // V-node to go on its own new line, which is why we
          // insert the empty text line as buffer (it will suck
          // up the last_to_first concatenation coming from the
          // V-node):
          core.total_chars(first),
          [first, one_empty_line, ..already_wrapped],
        )
        False -> #(deficit, [first, ..already_wrapped])
      }
      line_wrap_in_list(
        already_wrapped,
        deficit,
        False,
        rest,
        line_length,
        incorporating_condition,
      )
    }
  }
}

fn v_before(vxml: VXML, state: State, inner: InnerParam) -> #(VXML, State) {
  let assert V(_, tag, _, _) = vxml
  case list.contains(inner.zero_indent_tags, tag) {
    True -> #(vxml, 0)
    False -> #(vxml, state + inner.nesting_width_reduction)
  }
}

fn v_after(
  vxml: VXML,
  original_state: State,
  state: State,
  inner: InnerParam,
) -> #(VXML, State) {
  let assert V(_, _, _, children) = vxml
  let children =
    line_wrap_in_list(
      [],
      0,
      False,
      children,
      int.max(inner.maximum_length - state - 1, inner.minimum_length),
      inner.will_fold_into_text,
    )
  #(V(..vxml, children: children), original_state)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
