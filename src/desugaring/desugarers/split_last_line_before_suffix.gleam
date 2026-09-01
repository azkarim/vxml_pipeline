import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "split_last_line_before_suffix"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Splits the last text line before a matching suffix.
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
    // Suffix before which to split.
    String,
  )

type InnerParam =
  #(String, String, Int)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  #(param.0, param.1, string.length(param.1))
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 -> {
      let children = children |> core.t_map(do_it(_, inner.1, inner.2))
      V(..vxml, children: children)
    }
    _ -> vxml
  }
}

fn do_it(t: VXML, suffix: String, suffix_length: Int) -> VXML {
  let assert T(blame, lines) = t
  let assert [first, ..rest] = lines |> list.reverse
  case string.ends_with(first.content, suffix) {
    False -> t
    True -> {
      let start = string.drop_end(first.content, suffix_length)
      case start == "" {
        True -> t
        False -> {
          let trimmed_start = string.trim_end(start)
          let suffix_blame = bl.advance(first.blame, string.length(start))
          case trimmed_start == "" {
            True ->
              T(
                blame,
                [Line(suffix_blame, suffix), ..rest]
                  |> list.reverse,
              )
            False -> {
              T(
                blame,
                [
                  Line(suffix_blame, suffix),
                  Line(first.blame, trimmed_start),
                  ..rest
                ]
                  |> list.reverse,
              )
            }
          }
        }
      }
    }
  }
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
