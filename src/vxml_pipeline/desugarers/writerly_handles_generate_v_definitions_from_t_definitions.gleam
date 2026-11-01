import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp}
import gleam/string
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

// Scan a line's content for in-text handle definitions.
// Processes left-to-right, replacing each valid occurrence of
//   PRECEDING_CHAR + HANDLE_NAME + DECORATORS + ##<< + VALUE
// or
//   ## + HANDLE_NAME + DECORATORS + ##<< + VALUE
// with
//   PRECEDING_CHAR + VALUE
// and collecting handle attrs for the parent V node.
fn process_content(
  remaining: String,
  done: String,
  attrs: List(Attr),
  inner: InnerParam,
  blame: Blame,
  at_normal_boundary: Bool,
) -> #(String, List(Attr)) {
  let #(definition_regexp, closer_regexp) = inner
  case regexp.scan(definition_regexp, remaining) {
    [] -> #(done <> remaining, attrs)
    [first_match, ..] -> {
      let #(prefix, handle_name, decorators, line_start_form) = case
        handle_syntax.padded_submatches(first_match, 6)
      {
        [prefix, Some(name), decorators, ..] -> {
          let prefix = option.unwrap(prefix, "")
          #(prefix, name, option.unwrap(decorators, ""), prefix == "")
        }
        [_, _, _, Some(_), Some(name), decorators] -> #(
          "",
          name,
          option.unwrap(decorators, ""),
          False,
        )
        _ -> #("", "", "", False)
      }
      case handle_name, string.split_once(remaining, first_match.content) {
        "", _ -> #(done <> remaining, attrs)
        _, Error(_) -> #(done <> remaining, attrs)
        _, Ok(#(before, after_marker)) -> {
          let content_before = done <> before
          // `^` in the regexp is relative to `remaining`; only accept it
          // at the original line start or immediately after a consumed closer.
          case
            line_start_form
            && !{ content_before == "" || at_normal_boundary && before == "" }
          {
            True ->
              process_content(
                after_marker,
                done <> before <> first_match.content,
                attrs,
                inner,
                blame,
                False,
              )
            False -> {
              let #(possible_value, rest) =
                handle_syntax.take_explicit_value(after_marker, closer_regexp)
              let value = option.unwrap(possible_value, "")
              let next_is_normal_boundary = option.is_some(possible_value)
              let decorated_handle_name = handle_name <> decorators
              let attr_val =
                decorated_handle_name
                <> " "
                <> handle_syntax.encode_value(value)
              let new_attr = Attr(blame, "handle", attr_val)
              let new_done = done <> before <> prefix <> value
              process_content(
                rest,
                new_done,
                [new_attr, ..attrs],
                inner,
                blame,
                next_is_normal_boundary,
              )
            }
          }
        }
      }
    }
  }
}

fn process_line(line: Line, inner: InnerParam) -> #(Line, List(Attr)) {
  let #(new_content, new_attrs) =
    process_content(line.content, "", [], inner, line.blame, True)
  #(Line(..line, content: new_content), new_attrs)
}

// State accumulates handle attrs found in T nodes, to be added to the
// closest enclosing V node.
type State =
  List(Attr)

fn on_text(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert T(blame, lines) = vxml
  let #(new_line_attrs, new_lines) =
    list.map_fold(lines, [], fn(acc_attrs, line) {
      let #(new_line, line_attrs) = process_line(line, inner)
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
  // A definition uses either a normal left boundary or an explicit `##`
  // opener. The closing `##<<` must be directly adjacent.
  let in_text_def_pattern =
    "(?:(^|[ {\\(\\[])([\\p{L}\\p{N}\\p{M}_.:'\\-\\^]*[\\p{L}\\p{N}\\p{M}_'\\^])((?:#[\\p{L}\\p{N}\\p{M}_:'\\-]+)*)|(##)([\\p{L}\\p{N}\\p{M}_.:'\\-\\^]*[\\p{L}\\p{N}\\p{M}_'\\^])((?:#[\\p{L}\\p{N}\\p{M}_:'\\-]+)*))##<<"
  let assert Ok(definition_regexp) =
    regexp.compile(
      in_text_def_pattern,
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  let assert Ok(closer_regexp) = regexp.from_string("(\\\\*)(>>##)")
  Ok(#(definition_regexp, closer_regexp))
}

type Param =
  Nil

type InnerParam =
  #(Regexp, Regexp)

pub const name = "writerly_handles_generate_v_definitions_from_t_definitions"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Scans every text node (T) for in-text handle
/// definitions of the form
///
///   BOUNDARY handleName[#decorator...]##<<VALUE>>##
///   ##handleName[#decorator...]##<<VALUE>>##
///
/// The boundary form is recognized at the start of a line,
/// after a space, '{', '(' or '[', or immediately after a
/// consumed value closer. The explicit '##' form can occur
/// anywhere. Handle names and decorators use the Writerly
/// extension's Unicode-aware grammar. VALUE is the
/// single-line content up to the first
/// unescaped '>>##'. Odd/even backslash parity controls
/// closer escaping, and escape backslashes are removed. An
/// active closer is consumed eagerly; its final '##' is not
/// reused as an explicit opener. If no closer exists, the
/// value is empty and scanning restarts immediately after
/// '##<<'. The same rules apply inside Writerly code blocks.
///
/// For each match found, the desugarer:
///
///   1. Replaces the matched span with just
///      BOUNDARY + VALUE in the text. The explicit '##'
///      opener is removed.
///   2. Adds a 'handle=handleName <<VALUE>>' attribute
///      to the closest ancestor V node of the T node.
///      Every decorator is copied after the handle name;
///      this desugarer does not interpret decorator semantics.
///
/// If '##<<' is found but what precedes it does not
/// form a valid handle-name pattern (or has no valid
/// preceding char), that occurrence is left untouched
/// with no error or warning.
///
/// Any backslash between the name or decorators and '##<<'
/// breaks the required adjacency, so the text is preserved.
///
/// Intended to run before writerly_handles_add_ids so that generated
/// definitions receive ids with other handle-bearing elements.
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
    testing.data_no_param(
      source: "
        <> root
          <>
            'see name##<<value | with spaces  >>## rest'
      ",
      expected: "
        <> root
          handle=name <<value | with spaces  >>
          <>
            'see value | with spaces   rest'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            'first##<<ordinary second##<<value>>##'
      ",
      expected: "
        <> root
          handle=first <<ordinary second##<<value>>
          <>
            'ordinary second##<<value'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            'name##<<before \\>>## after>>##'
      ",
      expected: "
        <> root
          handle=name <<before >>## after>>
          <>
            'before >>## after'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            'name##<<before \\\\>>## after'
      ",
      expected: "
        <> root
          handle=name <<before \\>>
          <>
            'before \\ after'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            'first##<<ordinary second##<<'
      ",
      expected: "
        <> root
          handle=first <<>>
          handle=second <<>>
          <>
            'ordinary '
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            'prefix##name#page#glossary##<<value>>## rest'
      ",
      expected: "
        <> root
          handle=name#page#glossary <<value>>
          <>
            'prefixvalue rest'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            'see δοκιμή_2#σελίδα##<<τιμή>>## rest'
      ",
      expected: "
        <> root
          handle=δοκιμή_2#σελίδα <<τιμή>>
          <>
            'see τιμή rest'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            'punctuation/name##<<value>>##'
      ",
      expected: "
        <> root
          <>
            'punctuation/name##<<value>>##'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            '##one##<<first value>>##two##<<second value>>##'
      ",
      expected: "
        <> root
          handle=one <<first value>>
          handle=two <<second value>>
          <>
            'first valuesecond value'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <>
            '##one##<<first>>####two##<<'
      ",
      expected: "
        <> root
          handle=one <<first>>
          handle=two <<>>
          <>
            'first'
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <> WriterlyCodeBlock
            <>
              'code_handle##<<code value>>##'
      ",
      expected: "
        <> root
          <> WriterlyCodeBlock
            handle=code_handle <<code value>>
            <>
              'code value'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
