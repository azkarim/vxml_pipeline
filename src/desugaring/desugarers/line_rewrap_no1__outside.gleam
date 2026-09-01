import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/line_wrapping
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, Line, T, V}

pub const name = "line_rewrap_no1__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Rewraps lines to a maximum width while reserving space
/// for elements selected by a predicate.
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
  #(Int, fn(VXML) -> Bool)

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, _, children) -> {
      let children = line_wrap_in_list([], 0, False, children, inner)
      V(..vxml, children: children)
    }
  }
}

fn line_wrap_in_list(
  already_wrapped: List(VXML),
  deficit: Int,
  last_was_text: Bool,
  remaining: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case remaining {
    [] -> already_wrapped |> list.reverse
    [T(blame, lines), ..rest] -> {
      let deficit = case last_was_text {
        True -> 0
        False -> deficit
      }
      let #(lines, new_indent) =
        line_wrapping.rewrap_lines(lines, deficit, inner.0)
      line_wrap_in_list(
        [T(blame, lines), ..already_wrapped],
        new_indent,
        True,
        rest,
        inner,
      )
    }
    [V(_, _, _, _) as first, ..rest] -> {
      let deficit = case inner.1(first) {
        True -> core.total_chars(first) + deficit
        False -> 0
      }
      let #(deficit, already_wrapped) = case deficit > inner.0 {
        True -> #(core.total_chars(first), [
          first,
          T(first.blame, [Line(first.blame, "")]),
          ..already_wrapped
        ])
        False -> #(deficit, [first, ..already_wrapped])
      }
      line_wrap_in_list(already_wrapped, deficit, False, rest, inner)
    }
  }
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
