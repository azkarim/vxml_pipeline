import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/string
import vxml.{type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "split_first_line_after_prefix"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Splits the first text line after a matching prefix.
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
    // Prefix after which to split.
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

fn do_it(t: VXML, prefix: String, prefix_length: Int) -> VXML {
  let assert T(blame, [first, ..rest]) = t
  case string.starts_with(first.content, prefix) {
    False -> t
    True -> {
      let end = string.drop_start(first.content, prefix_length)
      case end == "" {
        True -> t
        False -> {
          let trimmed_end = string.trim_start(end)
          case trimmed_end == "" {
            True -> T(blame, [Line(first.blame, prefix), ..rest])
            False -> {
              let amt_trimmed = string.length(end) - string.length(trimmed_end)
              let scnd_blame = bl.advance(first.blame, amt_trimmed)
              T(blame, [
                Line(first.blame, prefix),
                Line(scnd_blame, trimmed_end),
                ..rest
              ])
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
  [
    testing.data(
      param: #("MathBlock", "\\begin{align}"),
      source: "
                <> root
                  <> MathBlock
                    <>
                      '\\begin{align}x + y = z'
                  <> MathBlock
                    <>
                      '\\begin{align}'
                      'a + b = c'
                  <> MathBlock
                    <>
                      '\\begin{align} '
                      'more content'
                  <> MathBlock
                    <>
                      'normal content'
                  <> OtherElement
                    <>
                      '\\begin{align}should not change'
                ",
      expected: "
                <> root
                  <> MathBlock
                    <>
                      '\\begin{align}'
                      'x + y = z'
                  <> MathBlock
                    <>
                      '\\begin{align}'
                      'a + b = c'
                  <> MathBlock
                    <>
                      '\\begin{align}'
                      'more content'
                  <> MathBlock
                    <>
                      'normal content'
                  <> OtherElement
                    <>
                      '\\begin{align}should not change'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
