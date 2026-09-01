import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "normalize_br_in_pre"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Replaces `br` children of `pre` elements with line
/// breaks.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
}

type InnerParam =
  Nil

fn inner_param_to_transform(_inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(_, "pre", _, children) -> {
      let children =
        list.map(children, fn(c) {
          case c {
            V(_, "br", _, _) -> {
              newline_t
            }
            _ -> c
          }
        })
        |> core.last_to_first_concatenation
      V(..vxml, children: children)
    }
    _ -> vxml
  }
}

const newline_t = T(
  bl.Des([], name, 52),
  [
    Line(bl.Des([], name, 54), ""),
    Line(bl.Des([], name, 55), ""),
  ],
)

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    testing.data_no_param(
      source: "
                <> pre
                  <>
                    'line 1'
                  <> br
                  <>
                    'line 2'
                ",
      expected: "
                <> pre
                  <>
                    'line 1'
                    'line 2'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
