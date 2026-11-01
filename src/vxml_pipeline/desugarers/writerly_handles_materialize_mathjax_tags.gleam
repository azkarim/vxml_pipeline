import gleam/list
import gleam/option
import gleam/regexp.{type Regexp}
import gleam/string
import vxml.{Line, T, V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "writerly_handles_materialize_mathjax_tags"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Replaces math labels and in-text handle definitions with
/// MathJax tags inside configured ancestor elements. It uses
/// Writerly's boundary and explicit-'##' definition forms.
/// Definitions whose closing operator is separated from the
/// name or decorators by a backslash remain untouched.
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
    // Compiled braced-label expression.
    Regexp,
    // Compiled bare-definition expression.
    Regexp,
    // Compiled explicit-value closer expression.
    Regexp,
  )

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(ancestor_tag, counter_expr) = param
  let name = "[\\p{L}\\p{N}\\p{M}_.:'\\-\\^]*[\\p{L}\\p{N}\\p{M}_'\\^]"
  let decorators = "(?:#[\\p{L}\\p{N}\\p{M}_:'\\-]+)*"
  let assert Ok(braced_re) =
    regexp.compile(
      "\\\\(label|tag)\\{(" <> name <> ")(" <> decorators <> ")##<<([^}]*)\\}",
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  let assert Ok(bare_re) =
    regexp.compile(
      "(?:(^|[ {\\(\\[])("
        <> name
        <> ")("
        <> decorators
        <> ")|(##)("
        <> name
        <> ")("
        <> decorators
        <> "))##<<",
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  let assert Ok(closer_re) = regexp.from_string("(\\\\*)(>>##)")
  Ok(#(ancestor_tag, counter_expr, braced_re, bare_re, closer_re))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let #(ancestor_tag, counter_expr, braced_re, bare_re, closer_re) = inner
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
                    braced_re,
                    bare_re,
                    closer_re,
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
  braced_re: Regexp,
  bare_re: Regexp,
  closer_re: Regexp,
  counter_expr: String,
) -> String {
  content
  |> replace_braced_labels(braced_re, closer_re, counter_expr)
  |> replace_bare_labels("", bare_re, closer_re, counter_expr, True)
}

fn replace_braced_labels(
  content: String,
  re: Regexp,
  closer_re: Regexp,
  counter_expr: String,
) -> String {
  case regexp.scan(re, content) {
    [] -> content
    [first_match, ..] ->
      case handle_syntax.padded_submatches(first_match, 4) {
        [option.Some(keyword), option.Some(name), decorators, remainder, ..] -> {
          let decorators = option.unwrap(decorators, "")
          let remainder = option.unwrap(remainder, "")
          let #(possible_value, rest) =
            handle_syntax.take_explicit_value(remainder, closer_re)
          let value = option.unwrap(possible_value, "")
          case string.split_once(content, first_match.content) {
            Error(_) -> content
            Ok(#(before, after)) -> {
              let replacement = case value, keyword {
                "", _ ->
                  "\\tag{"
                  <> name
                  <> decorators
                  <> "##<<"
                  <> counter_expr
                  <> ">>##"
                  <> "}"
                existing, "label" ->
                  "\\tag{"
                  <> name
                  <> decorators
                  <> "##<<"
                  <> existing
                  <> ">>##}"
                _, _ -> first_match.content
              }
              before
              <> replacement
              <> rest
              <> replace_braced_labels(after, re, closer_re, counter_expr)
            }
          }
        }
        _ -> content
      }
  }
}

fn replace_bare_labels(
  remaining: String,
  done: String,
  re: Regexp,
  closer_re: Regexp,
  counter_expr: String,
  at_normal_boundary: Bool,
) -> String {
  case regexp.scan(re, remaining) {
    [] -> done <> remaining
    [first_match, ..] -> {
      let #(prefix, name, decorators, line_start_form) = case
        handle_syntax.padded_submatches(first_match, 6)
      {
        [prefix, option.Some(name), decorators, ..] -> {
          let prefix = option.unwrap(prefix, "")
          #(prefix, name, option.unwrap(decorators, ""), prefix == "")
        }
        [_, _, _, option.Some(_), option.Some(name), decorators] -> #(
          "",
          name,
          option.unwrap(decorators, ""),
          False,
        )
        _ -> #("", "", "", False)
      }
      case name, string.split_once(remaining, first_match.content) {
        "", _ -> done <> remaining
        _, Error(_) -> done <> remaining
        _, Ok(#(before, after)) -> {
          let content_before = done <> before
          let content_through_prefix = content_before <> prefix
          case
            line_start_form
            && !{ content_before == "" || at_normal_boundary && before == "" }
            || string.ends_with(content_through_prefix, "\\label{")
            || string.ends_with(content_through_prefix, "\\tag{")
          {
            True ->
              replace_bare_labels(
                after,
                done <> before <> first_match.content,
                re,
                closer_re,
                counter_expr,
                False,
              )
            False -> {
              let #(possible_value, rest) =
                handle_syntax.take_explicit_value(after, closer_re)
              let value = case possible_value {
                option.Some("") | option.None -> counter_expr
                option.Some(value) -> value
              }
              let next_is_normal_boundary = option.is_some(possible_value)
              replace_bare_labels(
                rest,
                done
                  <> before
                  <> prefix
                  <> "\\tag{"
                  <> name
                  <> decorators
                  <> "##<<"
                  <> value
                  <> ">>##"
                  <> "}",
                re,
                closer_re,
                counter_expr,
                next_is_normal_boundary,
              )
            }
          }
        }
      }
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
    // Test 1: \label{name##<<>>##} inside MathBlock → fills counter
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:lebesgue##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:lebesgue##<<::øøSectionCounter.::++EquationCounter>>##}'
        ",
    ),

    // Test 2: \label{name##<<>>##} outside ancestor tag → no change
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<>>##}'
        ",
      expected: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<>>##}'
        ",
    ),

    // Test 3: multiple \label{name##<<>>##} on separate lines
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:first##<<>>##}'
              'c = d \\label{eq:second##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:first##<<::øøSectionCounter.::++EquationCounter>>##}'
              'c = d \\tag{eq:second##<<::øøSectionCounter.::++EquationCounter>>##}'
        ",
    ),

    // Test 4: label name with colons and hyphens
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'x = y \\label{eq:sec-1:item##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'x = y \\tag{eq:sec-1:item##<<::øøSectionCounter.::++EquationCounter>>##}'
        ",
    ),

    // Test 5: \tag{name##<<value>>##} with value already set → no change
    testing.data(
      param: #("MathBlock", "::øøSectionCounter.::++EquationCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:explicit##<<A>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:explicit##<<A>>##}'
        ",
    ),

    // Test 6: empty ancestor_tag applies to all T nodes
    testing.data(
      param: #("", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b \\label{eq:lebesgue##<<>>##}'
        ",
      expected: "
        <> root
          <>
            'a = b \\tag{eq:lebesgue##<<::++EqCounter>>##}'
        ",
    ),

    // Test 7: two \label{##<<>>##} on the same line
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              '& a = b \\label{eq:line1##<<>>##} & c = d \\label{eq:line2##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              '& a = b \\tag{eq:line1##<<::++EqCounter>>##} & c = d \\tag{eq:line2##<<::++EqCounter>>##}'
        ",
    ),

    // Test 8: \tag{name##<<>>##} (tag form, empty value) → fills counter
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<::++EqCounter>>##}'
        ",
    ),

    // Test 9: \label{name##<<value>>##} → changes \label to \tag, preserves value
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo##<<A>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo##<<A>>##}'
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
              'a = b eq:lebesgue##<<>>##'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:lebesgue##<<::++EqCounter>>##}'
        ",
    ),

    // Test 12: bare name##<< outside ancestor tag → no change
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b eq:lebesgue##<<>>##'
        ",
      expected: "
        <> root
          <>
            'a = b eq:lebesgue##<<>>##'
        ",
    ),

    // Test 13: bare name##<< with empty ancestor_tag applies to all T nodes
    testing.data(
      param: #("", "::++EqCounter"),
      source: "
        <> root
          <>
            'a = b eq:lebesgue##<<>>##'
        ",
      expected: "
        <> root
          <>
            'a = b \\tag{eq:lebesgue##<<::++EqCounter>>##}'
        ",
    ),

    // Test 15: bare name#decorator##<< inside MathBlock → fills counter, decorator preserved
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a + b = c eq:lebesgue#page##<<>>##'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a + b = c \\tag{eq:lebesgue#page##<<::++EqCounter>>##}'
        ",
    ),

    // Test 16: \label{name#decorator##<<>>##} → converts to \tag, decorator preserved
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo#page##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<::++EqCounter>>##}'
        ",
    ),

    // Test 17: multiple decorators on bare form
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'x = y eq:thm#page#glossary##<<>>##'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'x = y \\tag{eq:thm#page#glossary##<<::++EqCounter>>##}'
        ",
    ),

    // Test 18: \tag{name#decorator##<<>>##} with existing value → unchanged
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A>>##}'
        ",
    ),

    // Test 19: \label{name#decorator##<<value>>##} → changes to \tag, preserves value and decorator
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:foo#page##<<A>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:foo#page##<<A>>##}'
        ",
    ),

    // Test 20: bare name#decorator##<< outside MathBlock → no change
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <>
            'a + b = c eq:lebesgue#page##<<>>##'
        ",
      expected: "
        <> root
          <>
            'a + b = c eq:lebesgue#page##<<>>##'
        ",
    ),

    // Test 21: bare name with prime char (e.g. left-reduction-w')
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b left-reduction-w'##<<>>##'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{left-reduction-w'##<<::++EqCounter>>##}'
        ",
    ),

    // Test 22: \\label with prime in handle name
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{left-reduction-w'##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{left-reduction-w'##<<::++EqCounter>>##}'
        ",
    ),

    // Test 14: bare name##<< alongside \label{...>>##} on separate lines
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:first##<<>>##}'
              'c = d eq:second##<<>>##'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{eq:first##<<::++EqCounter>>##}'
              'c = d \\tag{eq:second##<<::++EqCounter>>##}'
        ",
    ),

    // Any backslash breaks adjacency and leaves the label untouched.
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:literal\\##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:literal\\##<<>>##}'
        ",
    ),

    // Definition escaping does not use the usage operator's parity rule.
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:active\\\\##<<>>##}'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\label{eq:active\\\\##<<>>##}'
        ",
    ),

    // The explicit opener permits a definition at an arbitrary position.
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a=b##eq:active#page##<<>>##'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a=b\\tag{eq:active#page##<<::++EqCounter>>##}'
        ",
    ),

    // Unicode handle names and decorators follow the extension grammar.
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              'a = b δοκιμή_2#σελίδα##<<>>##'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a = b \\tag{δοκιμή_2#σελίδα##<<::++EqCounter>>##}'
        ",
    ),
    testing.data(
      param: #("MathBlock", "::++EqCounter"),
      source: "
        <> root
          <> MathBlock
            <>
              '##one##<<A>>##two##<<>>##'
      ",
      expected: "
        <> root
          <> MathBlock
            <>
              '\\tag{one##<<A>>##}\\tag{two##<<::++EqCounter>>##}'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
