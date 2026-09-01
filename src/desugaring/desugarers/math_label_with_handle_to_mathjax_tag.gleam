import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option
import gleam/regexp.{type Regexp}
import gleam/string
import vxml.{Line, T, V}

pub const name = "math_label_with_handle_to_mathjax_tag"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Replaces math labels with tag handles inside configured
/// ancestor elements.
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
    // Ancestor tag.
    String,
    // Counter expression.
    String,
  )

type InnerParam =
  #(
    // Ancestor tag.
    String,
    // Counter expression.
    String,
    // Compiled label-matching expression.
    Regexp,
  )

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(ancestor_tag, counter_expr) = param
  let pattern =
    "\\\\(label|tag)\\{([a-zA-Z0-9_.:^\\-']+(?:#[a-zA-Z0-9_:\\-]+)*)##<<([^}]*)\\}|([a-zA-Z0-9_.:^\\-']+(?:#[a-zA-Z0-9_:\\-]+)*)##<<"
  let assert Ok(re) =
    regexp.compile(
      pattern,
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  Ok(#(ancestor_tag, counter_expr, re))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let #(ancestor_tag, counter_expr, re) = inner
  let nodemap: n2t.OneToOneEnterExitStatefulNoErrorNodemap(State) =
    n2t.OneToOneEnterExitStatefulNoErrorNodemap(
      on_enter: fn(vxml, state) {
        let assert V(_, tag, _, _) = vxml
        #(vxml, state || tag == ancestor_tag)
      },
      on_exit: fn(vxml, original_state, _latest_state) {
        #(vxml, original_state)
      },
      on_text: fn(vxml, state) {
        case state {
          False -> #(vxml, state)
          True -> {
            let assert T(blame, lines) = vxml
            let new_lines =
              list.map(lines, fn(line) {
                Line(
                  ..line,
                  content: replace_labels_in_content(
                    line.content,
                    re,
                    counter_expr,
                  ),
                )
              })
            #(T(blame, new_lines), state)
          }
        }
      },
    )
  n2t.one_to_one_enter_exit_stateful_no_error_nodemap_2_desugarer_transform(
    nodemap,
    ancestor_tag == "",
  )
}

fn replace_labels_in_content(
  content: String,
  re: Regexp,
  counter_expr: String,
) -> String {
  case regexp.scan(re, content) {
    [] -> content
    [first_match, ..] ->
      case first_match.submatches {
        [option.Some(keyword), option.Some(name), ..rest] -> {
          let value = case rest {
            [option.Some(v), ..] -> v
            _ -> ""
          }
          case string.split_once(content, first_match.content) {
            Error(_) -> content
            Ok(#(before, after)) -> {
              let replacement = case value {
                "" -> "\\tag{" <> name <> "##<<" <> counter_expr <> "}"
                existing ->
                  case keyword {
                    "label" -> "\\tag{" <> name <> "##<<" <> existing <> "}"
                    _ -> first_match.content
                  }
              }
              before
              <> replacement
              <> replace_labels_in_content(after, re, counter_expr)
            }
          }
        }
        [option.None, option.None, option.None, option.Some(bare_name)] -> {
          case string.split_once(content, first_match.content) {
            Error(_) -> content
            Ok(#(before, after)) ->
              before
              <> "\\tag{"
              <> bare_name
              <> "##<<"
              <> counter_expr
              <> "}"
              <> replace_labels_in_content(after, re, counter_expr)
          }
        }
        _ -> content
      }
  }
}

type State =
  Bool

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    // Test 1: \label{name##<<} inside MathBlock → fills counter
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:lebesgue##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:lebesgue##<<::øøSectionCounter.::++EquationCounter}'
        ",
    ),

    // Test 2: \label{name##<<} outside ancestor tag → no change
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<}'
        ",
      expected: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<}'
        ",
    ),

    // Test 3: multiple \label{name##<<} on separate lines
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:first##<<}'
              'c = d \\label{eq:second##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:first##<<::øøSectionCounter.::++EquationCounter}'
              'c = d \\tag{eq:second##<<::øøSectionCounter.::++EquationCounter}'
        ",
    ),

    // Test 4: label name with colons and hyphens
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'x = y \\label{eq:sec-1:item##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'x = y \\tag{eq:sec-1:item##<<::øøSectionCounter.::++EquationCounter}'
        ",
    ),

    // Test 5: \tag{name##<<value} with value already set → no change
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:explicit##<<A}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:explicit##<<A}'
        ",
    ),

    // Test 6: empty ancestor_tag applies to all T nodes
    testing.data(
      param: #("", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<}'
        ",
      expected: "
        <> root
          <>
            'a = b \\tag{eq:lebesgue##<<::++EqCounter}'
        ",
    ),

    // Test 7: two \label{##<<} on the same line
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              '& a = b \\label{eq:line1##<<} & c = d \\label{eq:line2##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '& a = b \\tag{eq:line1##<<::++EqCounter} & c = d \\tag{eq:line2##<<::++EqCounter}'
        ",
    ),

    // Test 8: \tag{name##<<} (tag form, empty value) → fills counter
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<::++EqCounter}'
        ",
    ),

    // Test 9: \label{name##<<value} → changes \label to \tag, preserves value
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo##<<A}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<A}'
        ",
    ),

    // Test 10: \label{name} without ##<< → not matched, left unchanged
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo}'
        ",
    ),

    // Test 11: bare name##<< inside MathBlock → fills counter
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b eq:lebesgue##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:lebesgue##<<::++EqCounter}'
        ",
    ),

    // Test 12: bare name##<< outside ancestor tag → no change
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b eq:lebesgue##<<'
        ",
      expected: "
        <> root
          <>
            'a = b eq:lebesgue##<<'
        ",
    ),

    // Test 13: bare name##<< with empty ancestor_tag applies to all T nodes
    testing.data(
      param: #("", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b eq:lebesgue##<<'
        ",
      expected: "
        <> root
          <>
            'a = b \\tag{eq:lebesgue##<<::++EqCounter}'
        ",
    ),

    // Test 15: bare name#decorator##<< inside MathBlock → fills counter, decorator preserved
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a + b = c eq:lebesgue#page##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a + b = c \\tag{eq:lebesgue#page##<<::++EqCounter}'
        ",
    ),

    // Test 16: \label{name#decorator##<<} → converts to \tag, decorator preserved
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo#page##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<::++EqCounter}'
        ",
    ),

    // Test 17: multiple decorators on bare form
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'x = y eq:thm#page#glossary##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'x = y \\tag{eq:thm#page#glossary##<<::++EqCounter}'
        ",
    ),

    // Test 18: \tag{name#decorator##<<} with existing value → unchanged
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A}'
        ",
    ),

    // Test 19: \label{name#decorator##<<value} → changes to \tag, preserves value and decorator
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo#page##<<A}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A}'
        ",
    ),

    // Test 20: bare name#decorator##<< outside MathBlock → no change
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <>
            'a + b = c eq:lebesgue#page##<<'
        ",
      expected: "
        <> root
          <>
            'a + b = c eq:lebesgue#page##<<'
        ",
    ),

    // Test 21: bare name with prime char (e.g. left-reduction-w')
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b left-reduction-w'##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{left-reduction-w'##<<::++EqCounter}'
        ",
    ),

    // Test 22: \\label with prime in handle name
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{left-reduction-w'##<<}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{left-reduction-w'##<<::++EqCounter}'
        ",
    ),

    // Test 14: bare name##<< alongside \label{...} on separate lines
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:first##<<}'
              'c = d eq:second##<<'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:first##<<::++EqCounter}'
              'c = d \\tag{eq:second##<<::++EqCounter}'
        ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
