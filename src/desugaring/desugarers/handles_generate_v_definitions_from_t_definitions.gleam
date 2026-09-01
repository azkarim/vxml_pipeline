import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp}
import gleam/string
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame}

// Extract the value token after ##<<:
//   - stops at the first space when not inside a bracket
//   - stops at the first | when not inside a bracket
//   - stops at an unmatched closing bracket (depth would go negative)
//   - stops at end of string
fn do_extract_value(remaining: String, depth: Int, acc: String) -> String {
  case string.pop_grapheme(remaining) {
    Error(_) -> acc
    Ok(#(char, rest)) ->
      case char {
        "(" | "[" | "{" -> do_extract_value(rest, depth + 1, acc <> char)
        ")" | "]" | "}" ->
          case depth {
            0 -> acc
            _ -> do_extract_value(rest, depth - 1, acc <> char)
          }
        " " ->
          case depth {
            0 -> acc
            _ -> do_extract_value(rest, depth, acc <> char)
          }
        "|" ->
          case depth {
            0 -> acc
            _ -> do_extract_value(rest, depth, acc <> char)
          }
        _ -> do_extract_value(rest, depth, acc <> char)
      }
  }
}

fn extract_value(s: String) -> String {
  do_extract_value(s, 0, "")
}

// Scan a line's content for in-text handle definitions.
// Processes left-to-right, replacing each valid occurrence of
//   PRECEDING_CHAR + HANDLE_NAME + ##<< + VALUE
// with
//   PRECEDING_CHAR + VALUE
// and collecting handle attrs for the parent V node.
fn replacement_prefix(preceding_char: String) -> String {
  case preceding_char {
    "#" -> ""
    _ -> preceding_char
  }
}

fn process_content(
  remaining: String,
  done: String,
  attrs: List(Attr),
  re: Regexp,
  blame: Blame,
) -> #(String, List(Attr)) {
  case regexp.scan(re, remaining) {
    [] -> #(done <> remaining, attrs)
    [first_match, ..] -> {
      let preceding_char = case first_match.submatches {
        [Some(pc), ..] -> pc
        _ -> ""
      }
      let handle_name = case first_match.submatches {
        [_, Some(hn), ..] -> hn
        _ -> ""
      }
      case handle_name, string.split_once(remaining, first_match.content) {
        "", _ -> #(done <> remaining, attrs)
        _, Error(_) -> #(done <> remaining, attrs)
        _, Ok(#(before, after_marker)) -> {
          let value = extract_value(after_marker)
          let rest = string.drop_start(after_marker, string.length(value))
          let attr_val = core.normalize_spaces(handle_name <> " " <> value)
          let new_attr = Attr(blame, "handle", attr_val)
          let new_done =
            done <> before <> replacement_prefix(preceding_char) <> value
          process_content(rest, new_done, [new_attr, ..attrs], re, blame)
        }
      }
    }
  }
}

fn process_line(line: Line, re: Regexp) -> #(Line, List(Attr)) {
  let #(new_content, new_attrs) =
    process_content(line.content, "", [], re, line.blame)
  #(Line(..line, content: new_content), new_attrs)
}

// State accumulates handle attrs found in T nodes, to be added to the
// closest enclosing V node.
type State =
  List(Attr)

fn on_text(
  vxml: VXML,
  state: State,
  re: Regexp,
) -> Result(#(VXML, State), DesugaringError) {
  let assert T(blame, lines) = vxml
  let #(new_line_attrs, new_lines) =
    list.map_fold(lines, [], fn(acc_attrs, line) {
      let #(new_line, line_attrs) = process_line(line, re)
      #(list.append(line_attrs, acc_attrs), new_line)
    })
  Ok(#(T(blame, new_lines), list.append(new_line_attrs, state)))
}

// Reset the accumulated attrs when entering a V node, so that only
// attrs from *this* V's children are collected for this V.
fn v_before(
  vxml: VXML,
  _state: State,
) -> Result(#(VXML, State), DesugaringError) {
  Ok(#(vxml, []))
}

// After processing a V's children, add the newly-collected handle attrs
// to this V and restore the state to what it was before entering this V.
fn v_after(
  vxml: VXML,
  original_state: State,
  latest_state: State,
) -> Result(#(VXML, State), DesugaringError) {
  let new_handle_attrs = list.reverse(latest_state)
  let assert V(_, _, attrs, _) = vxml
  Ok(#(V(..vxml, attrs: list.append(new_handle_attrs, attrs)), original_state))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneEnterExitStatefulNodemap(State) =
    n2t.OneToOneEnterExitStatefulNodemap(
      on_enter: v_before,
      on_exit: v_after,
      on_text: fn(vxml, state) { on_text(vxml, state, inner) },
    )
  n2t.one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(nodemap, [])
}

fn param_to_inner_param(_param: Param) -> Result(InnerParam, DesugaringError) {
  // Matches: (start of line | space | '#' | '(' | '[')(handleName[#decorator]*)##<<
  // Handle chars:    letters, digits, _, ., :, -, ^
  // Handle end chars: letters, digits, _
  // Decorator chars:  same minus . and ^
  let in_text_def_pattern =
    "(^|[# {\\(\\[])([a-zA-Z0-9_.:\\-\\^']*[a-zA-Z0-9_'](?:#[a-zA-Z0-9_:\\-]+)*)##<<"
  let assert Ok(re) =
    regexp.compile(
      in_text_def_pattern,
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  Ok(re)
}

type Param =
  Nil

type InnerParam =
  Regexp

pub const name = "handles_generate_v_definitions_from_t_definitions"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Scans every text node (T) for in-text handle
/// definitions of the form
///
///   PRECEDING_CHAR handleName[#decorator...]##<<VALUE
///
/// where PRECEDING_CHAR is the start of the line, a space, '#', '(' or '[';
/// handleName must satisfy the handle-name regex;
/// each #decorator consists of '#' followed by one
/// or more decorator chars; and VALUE is everything
/// after '##<<' up to the first un-bracketed space or '|',
/// end of string, or unmatched closing bracket.
///
/// For each match found, the desugarer:
///
///   1. Replaces the matched span with just
///      PRECEDING_CHAR + VALUE in the text, except
///      that a '#' preceding char is removed.
///   2. Adds a 'handle=handleName VALUE' attribute
///      to the closest ancestor V node of the T node.
///
/// If '##<<' is found but what precedes it does not
/// form a valid handle-name pattern (or has no valid
/// preceding char), that occurrence is left untouched
/// with no error or warning.
///
/// Intended to run before handles_add_ids so that the
/// generated 'handle=' attrs are in the same
/// 'name value' format that handles_add_ids expects.
pub fn constructor() -> Desugarer {
  let assert Ok(inner) = param_to_inner_param(Nil)
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(inner),
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    // Test 1: basic single handle definition (space as preceding char)
    testing.data_no_param(
      source: "
        <> root
          <>
            'hello handleBob##<<Bobbba is here'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            'hello Bobbba is here'
        ",
    ),

    // Test 2: handle preceded by '('
    testing.data_no_param(
      source: "
        <> root
          <>
            '(handleBob##<<Bobbba rest)'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            '(Bobbba rest)'
        ",
    ),

    // Test 3: handle preceded by '['
    testing.data_no_param(
      source: "
        <> root
          <>
            '[handleBob##<<Bobbba rest]'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            '[Bobbba rest]'
        ",
    ),

    // Test 4: no match because '##<<' has no valid preceding character
    testing.data_no_param(
      source: "
        <> root
          <>
            'prefix/handleBob##<<value rest'
        ",
      expected: "
        <> root
          <>
            'prefix/handleBob##<<value rest'
        ",
    ),

    // Test 5: value extraction stops at unmatched closing bracket
    testing.data_no_param(
      source: "
        <> root
          <>
            'foo handleBob##<<Value) rest'
        ",
      expected: "
        <> root
          handle=handleBob Value
          <>
            'foo Value) rest'
        ",
    ),

    // Test 6: value with balanced parentheses (space inside parens is not a stop)
    testing.data_no_param(
      source: "
        <> root
          <>
            'def handleFn##<<f(x y) more'
        ",
      expected: "
        <> root
          handle=handleFn f(x y)
          <>
            'def f(x y) more'
        ",
    ),

    // Test 7: value extends to end of line (no terminating space)
    testing.data_no_param(
      source: "
        <> root
          <>
            'def handleFoo##<<TheValue'
        ",
      expected: "
        <> root
          handle=handleFoo TheValue
          <>
            'def TheValue'
        ",
    ),

    // Test 8: empty value (##<< at end of line)
    testing.data_no_param(
      source: "
        <> root
          <>
            'foo handleBob##<<'
        ",
      expected: "
        <> root
          handle=handleBob
          <>
            'foo '
        ",
    ),

    // Test 9: handle with a single decorator
    testing.data_no_param(
      source: "
        <> root
          <>
            'see handleBob#page##<<TheValue rest'
        ",
      expected: "
        <> root
          handle=handleBob#page TheValue
          <>
            'see TheValue rest'
        ",
    ),

    // Test 10: handle with multiple decorators
    testing.data_no_param(
      source: "
        <> root
          <>
            'see handleBob#page#glossary##<<TheValue rest'
        ",
      expected: "
        <> root
          handle=handleBob#page#glossary TheValue
          <>
            'see TheValue rest'
        ",
    ),

    // Test 11: two definitions on the same line
    testing.data_no_param(
      source: "
        <> root
          <>
            'alpha handleA##<<ValA and handleB##<<ValB end'
        ",
      expected: "
        <> root
          handle=handleA ValA
          handle=handleB ValB
          <>
            'alpha ValA and ValB end'
        ",
    ),

    // Test 12: definitions on different lines of the same T node
    testing.data_no_param(
      source: "
        <> root
          <>
            'line1 handleA##<<ValA rest'
            'line2 handleB##<<ValB rest'
        ",
      expected: "
        <> root
          handle=handleA ValA
          handle=handleB ValB
          <>
            'line1 ValA rest'
            'line2 ValB rest'
        ",
    ),

    // Test 13: handle in inner V goes to inner V; handle in outer V goes to outer V
    testing.data_no_param(
      source: "
        <> root
          <> Outer
            <>
              'outer text handleOuter##<<OuterVal rest'
            <> Inner
              <>
                'inner text handleInner##<<InnerVal rest'
        ",
      expected: "
        <> root
          <> Outer
            handle=handleOuter OuterVal
            <>
              'outer text OuterVal rest'
            <> Inner
              handle=handleInner InnerVal
              <>
                'inner text InnerVal rest'
        ",
    ),

    // Test 14: no ##<< in content at all — no change
    testing.data_no_param(
      source: "
        <> root
          <>
            'just ordinary text here'
        ",
      expected: "
        <> root
          <>
            'just ordinary text here'
        ",
    ),

    // Test 15: handle preceded by '(' with nested balanced brackets in value
    testing.data_no_param(
      source: "
        <> root
          <>
            '(handleEq##<<f(g(x)) rest'
        ",
      expected: "
        <> root
          handle=handleEq f(g(x))
          <>
            '(f(g(x)) rest'
        ",
    ),

    // Test 16: existing V attrs are preserved, handle attrs prepended
    testing.data_no_param(
      source: "
        <> root
          <> Para
            class=intro
            <>
              'hello handleBob##<<Bobbba done'
        ",
      expected: "
        <> root
          <> Para
            handle=handleBob Bobbba
            class=intro
            <>
              'hello Bobbba done'
        ",
    ),

    // Test 17: two separate T nodes in the same V, each contributing a handle
    testing.data_no_param(
      source: "
        <> root
          <> Para
            <>
              'first handleA##<<ValA end'
            <>
              'second handleB##<<ValB end'
        ",
      expected: "
        <> root
          <> Para
            handle=handleA ValA
            handle=handleB ValB
            <>
              'first ValA end'
            <>
              'second ValB end'
        ",
    ),

    // Test 18: handle name with dots and colons (valid handle chars)
    testing.data_no_param(
      source: "
        <> root
          <>
            'ref section:1.2##<<SectionTitle rest'
        ",
      expected: "
        <> root
          handle=section:1.2 SectionTitle
          <>
            'ref SectionTitle rest'
        ",
    ),

    // Test 19: value with balanced square brackets
    testing.data_no_param(
      source: "
        <> root
          <>
            'see handleList##<<[a b] more'
        ",
      expected: "
        <> root
          handle=handleList [a b]
          <>
            'see [a b] more'
        ",
    ),

    // Test 20: handle definition at line start
    testing.data_no_param(
      source: "
        <> root
          <>
            'handleBob##<<value rest'
        ",
      expected: "
        <> root
          handle=handleBob value
          <>
            'value rest'
        ",
    ),

    // Test 21: handle preceded by '{' (LaTeX \tag{handle##<<value} pattern)
    testing.data_no_param(
      source: "
        <> root
          <>
            '\\\\tag{eq:firstline##<<(A)}'
        ",
      expected: "
        <> root
          handle=eq:firstline (A)
          <>
            '\\\\tag{(A)}'
        ",
    ),

    // Test 22: handle name with prime char (e.g. left-reduction-w')
    testing.data_no_param(
      source: "
        <> root
          <>
            'see left-reduction-w'##<<TheValue rest'
        ",
      expected: "
        <> root
          handle=left-reduction-w' TheValue
          <>
            'see TheValue rest'
        ",
    ),

    // Test 23: prime at end of handle in LaTeX \tag context
    testing.data_no_param(
      source: "
        <> root
          <>
            '\\\\tag{left-reduction-w'##<<(A)}'
        ",
      expected: "
        <> root
          handle=left-reduction-w' (A)
          <>
            '\\\\tag{(A)}'
        ",
    ),

    // Test 24: handle preceded by '#' drops the prefix marker
    testing.data_no_param(
      source: "
        <> root
          <>
            'see #handleBob##<<Bobbba rest'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            'see Bobbba rest'
        ",
    ),

    // Test 25: line-start '#' prefix marker is dropped
    testing.data_no_param(
      source: "
        <> root
          <>
            '#handleBob##<<Bobbba rest'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            'Bobbba rest'
        ",
    ),

    // Test 26: value extraction stops at unbracketed pipe
    testing.data_no_param(
      source: "
        <> root
          <>
            'see handleBob##<<Bobbba|rest'
        ",
      expected: "
        <> root
          handle=handleBob Bobbba
          <>
            'see Bobbba|rest'
        ",
    ),

    // Test 27: value extraction keeps pipe inside brackets
    testing.data_no_param(
      source: "
        <> root
          <>
            'see handleBob##<<[Bobbba|still-value]|rest'
        ",
      expected: "
        <> root
          handle=handleBob [Bobbba|still-value]
          <>
            'see [Bobbba|still-value]|rest'
        ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
