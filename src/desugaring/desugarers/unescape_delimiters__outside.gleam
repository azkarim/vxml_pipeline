import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type VXML, Line, T}

pub const name = "unescape_delimiters__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Unescapes neutralized delimiters outside configured
/// subtrees after splitting.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

// walks a string left-to-right, consuming backslash escapes:
//
//   "\\d"   -> "d"   for d escapable   (escaped delimiter)
//   "\\X"   -> "\\X" otherwise         (left alone)
//
// the second case is what keeps this safe on LaTeX-bearing prose: an
// unrecognized escape is emitted verbatim AND its second character is
// not reconsidered, so "\\alpha" can never lose its backslash.
//
// NOTE a backslash is deliberately NOT self-escapable here: these
// documents use a trailing "\\" as a LaTeX row break in ordinary prose
// (outside any Math node), and collapsing it would corrupt them. The
// cost is that a literal backslash sitting directly in front of a live
// delimiter is not halved -- "\\\\_x_" yields "\\\\<i>x</i>" rather than
// "\\<i>x</i>". No occurrence of that shape exists in any current
// document; fixing it properly means teaching the splitter itself to
// halve the run at the point it consumes it.
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

fn nodemap(node: VXML, inner: InnerParam) -> VXML {
  case node {
    T(blame, lines) ->
      T(
        blame,
        list.map(lines, fn(line) {
          Line(
            line.blame,
            unescape_graphemes(string.to_graphemes(line.content), inner, []),
          )
        }),
      )
    _ -> node
  }
}

fn unescape_graphemes(
  graphemes: List(String),
  escapable: List(String),
  acc: List(String),
) -> String {
  case graphemes {
    [] -> acc |> list.reverse |> string.join("")
    ["\\", second, ..rest] ->
      case list.contains(escapable, second) {
        True -> unescape_graphemes(rest, escapable, [second, ..acc])
        False -> unescape_graphemes(rest, escapable, [second, "\\", ..acc])
      }
    [first, ..rest] -> unescape_graphemes(rest, escapable, [first, ..acc])
  }
}

type Param =
  // Single-character delimiters whose backslash escape
  // should be consumed. A backslash is always escapable.
  List(String)

type InnerParam =
  Param

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: ["_", "*"],
      outside: ["Math"],
      source: "
                <> root
                  <>
                    'a \\_x\\_ b'
                    'a \\* b'
                    'trailing row break stays \\\\'
                    'keep \\alpha and \\frac here'
                  <> Math
                    <>
                      'a \\_x\\_ b'
                ",
      expected: "
                <> root
                  <>
                    'a _x_ b'
                    'a * b'
                    'trailing row break stays \\\\'
                    'keep \\alpha and \\frac here'
                  <> Math
                    <>
                      'a \\_x\\_ b'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
