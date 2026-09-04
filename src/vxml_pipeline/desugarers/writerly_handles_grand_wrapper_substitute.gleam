import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Match, type Regexp, Match}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import on
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame} as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning, DesugaringError, DesugaringWarning,
}
import vxml_pipeline/handle_escaping
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

fn has_decorator(decorators: String, expected: String) -> Bool {
  decorators
  |> string.split("#")
  |> list.contains(expected)
}

fn extract_handle_and_page_and_decoy(
  match: Match,
) -> #(String, Bool, Option(String)) {
  let assert Match(_, [_, option.Some(handle_name)]) = match
  let #(handle_name, page) = case string.split_once(handle_name, "#page") {
    Ok(#(before, after)) -> #(before <> after, True)
    _ -> #(handle_name, False)
  }
  let handle_name = string.remove_suffix(handle_name, "##")
  let #(handle_name, decoy) = case string.split_once(handle_name, "#decoy:") {
    Ok(#(before, after)) -> #(before, option.Some(after))
    _ -> #(handle_name, None)
  }
  #(handle_name, page, decoy)
}

type HandleTextPart {
  PlainText(String)
  ActiveHandle(Match)
}

fn handle_text_parts(
  remaining: String,
  done: String,
  candidate_regexp: Regexp,
) -> List(HandleTextPart) {
  case regexp.scan(candidate_regexp, remaining) {
    [] -> [PlainText(done <> remaining)]
    [candidate, ..] -> {
      let backslashes = case candidate.submatches {
        [Some(backslashes), ..] -> backslashes
        _ -> ""
      }
      let handle_name = case candidate.submatches {
        [_, _, Some(handle_name)] -> handle_name
        _ -> ""
      }
      let assert Ok(#(before, after)) =
        string.split_once(remaining, candidate.content)
      let decoded_backslashes = handle_escaping.decode_backslashes(backslashes)
      case handle_escaping.is_escaped(backslashes) {
        True ->
          handle_text_parts(
            after,
            done <> before <> decoded_backslashes <> ">>" <> handle_name,
            candidate_regexp,
          )
        False -> {
          let handle_match =
            Match(">>" <> handle_name, [Some(">>"), Some(handle_name)])
          [
            PlainText(done <> before <> decoded_backslashes),
            ActiveHandle(handle_match),
            ..handle_text_parts(after, "", candidate_regexp)
          ]
        }
      }
    }
  }
}

fn hyperlink_constructor(
  handle: #(String, String, String, String),
  page: Bool,
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  let #(decorators, value, id, target_path) = handle
  let page_by_default = has_decorator(decorators, "page")

  use _ <- on.stay(case state.inside_a_link_tag {
    False -> on.Stay(Nil)
    True -> on.Return(Ok(T(blame, [Line(blame, value)])))
  })

  use our_path <- on.none_some(state.path, fn() {
    Error(DesugaringError(
      blame,
      "handle occurrence when local path is not defined",
    ))
  })
  let in_page = target_path == our_path
  let #(tag, attrs) = case in_page {
    True -> #(inner.in_page_tag, inner.in_page_attrs)
    False -> #(inner.out_page_tag, inner.out_page_attrs)
  }
  let page = page || page_by_default
  let href = case page, in_page {
    True, _ -> target_path
    False, True -> "#" <> id
    False, False -> target_path <> "#" <> id
  }
  let attrs = [Attr(blame, "href", href), ..attrs]
  Ok(V(blame, tag, attrs, [T(blame, [Line(blame, value)])]))
}

fn warning_element(handle_name: String, blame: Blame) -> VXML {
  V(desugarer_blame(118), "InTextWarning", [], [
    T(desugarer_blame(119), [
      Line(
        desugarer_blame(121),
        "undefined handle at " <> bl.blame_digest(blame) <> ": " <> handle_name,
      ),
    ]),
  ])
}

fn hyperlink_maybe(
  handle_and_page_and_decoy: #(String, Bool, Option(String)),
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, List(DesugaringWarning), List(String)), DesugaringError) {
  let #(handle_name, page, decoy) = handle_and_page_and_decoy
  use _ <- on.ok_error(dict.get(state.handles, handle_name), fn(quad) {
    hyperlink_constructor(quad, page, blame, state, inner)
    |> result.try(fn(vxml) { Ok(#(vxml, [], [handle_name])) })
  })

  use warning_span_or_decoy_link <- on.ok(case decoy {
    None -> Ok(warning_element(handle_name, blame))
    Some(decoy) -> {
      let quad = #("", decoy, "decoy-id", "decoy-target-path")
      hyperlink_constructor(quad, page, blame, state, inner)
    }
  })

  let actual_warning =
    DesugaringWarning(blame, "handle '" <> handle_name <> "' is not assigned")

  Ok(#(warning_span_or_decoy_link, [actual_warning], []))
}

// ***********************************************************
// math mode: substitution as flat LaTeX text, not as V-nodes
// ***********************************************************

/// MathJax parses the text content of a Math/MathBlock node as TeX
/// source, so a link there must be a LaTeX \href fragment and not an
/// 'a' V-node — an element node inside the math would be fed to the TeX
/// parser as literal markup.
fn substitution_text(
  handle_and_page_and_decoy: #(String, Bool, Option(String)),
  blame: Blame,
  fold_parens: Bool,
  state: State,
) -> #(String, List(DesugaringWarning), List(String)) {
  let #(handle_name, page, decoy) = handle_and_page_and_decoy
  let wrap = fn(s: String) -> String {
    case fold_parens {
      True -> "(" <> s <> ")"
      False -> s
    }
  }
  case dict.get(state.handles, handle_name) {
    Ok(#(decorators, value, id, target_path)) -> {
      let page_by_default = has_decorator(decorators, "page")
      let target = case page || page_by_default {
        True -> target_path
        False -> target_path <> "#" <> id
      }
      #("\\href{" <> target <> "}{" <> wrap(value) <> "}", [], [handle_name])
    }
    Error(_) -> {
      let warning =
        DesugaringWarning(
          blame,
          "handle '" <> handle_name <> "' is not assigned",
        )
      case decoy {
        Some(decoy_value) -> #(
          "\\href{decoy-target-path#decoy-id}{" <> wrap(decoy_value) <> "}",
          [warning],
          [],
        )
        None -> #(wrap("undefined handle: " <> handle_name), [warning], [])
      }
    }
  }
}

/// Rebuilds a line from its non-matching pieces and the handle matches
/// that sit between them. A handle occurrence whose immediately
/// surrounding characters are '(' and ')' with no whitespace absorbs
/// both parens into the \href value, so the whole "(2.5)" is clickable
/// rather than just the number.
fn render_math_parts(
  parts: List(HandleTextPart),
  blame: Blame,
  state: State,
) -> #(String, List(DesugaringWarning), List(String)) {
  case parts {
    [PlainText(text)] -> #(text, [], [])
    [PlainText(before), ActiveHandle(handle), PlainText(next), ..rest] -> {
      let fold = string.ends_with(before, "(") && string.starts_with(next, ")")
      let #(before, next) = case fold {
        True -> #(string.drop_end(before, 1), string.drop_start(next, 1))
        False -> #(before, next)
      }
      let #(substitution, warnings, used) =
        substitution_text(
          extract_handle_and_page_and_decoy(handle),
          blame,
          fold,
          state,
        )
      let #(rest_text, rest_warnings, rest_used) =
        render_math_parts([PlainText(next), ..rest], blame, state)
      #(
        before <> substitution <> rest_text,
        core.pour(warnings, rest_warnings),
        core.pour(used, rest_used),
      )
    }
    _ -> panic as "malformed handle-text parts"
  }
}

fn process_line_inside_math(
  line: Line,
  state: State,
  inner: InnerParam,
) -> #(Line, List(DesugaringWarning), List(String)) {
  let Line(blame, content) = line
  let #(new_content, warnings, used) =
    content
    |> handle_text_parts("", inner.handle_candidates_regexp)
    |> render_math_parts(blame, state)
  #(Line(blame, new_content), warnings, used)
}

fn process_lines_inside_math(
  lines: List(Line),
  state: State,
  inner: InnerParam,
) -> #(List(Line), List(DesugaringWarning), List(String)) {
  let triples =
    lines
    |> list.map(process_line_inside_math(_, state, inner))
  #(
    triples |> list.map(fn(triple) { triple.0 }),
    triples |> list.map(fn(triple) { triple.1 }) |> list.flatten,
    triples |> list.map(fn(triple) { triple.2 }) |> list.flatten,
  )
}

fn process_line(
  line: Line,
  state: State,
  inner: InnerParam,
) -> Result(
  #(List(VXML), List(DesugaringWarning), List(String)),
  DesugaringError,
) {
  let Line(blame, content) = line
  use #(vxmls, warnings, used) <- on.ok(
    content
    |> handle_text_parts("", inner.handle_candidates_regexp)
    |> list.try_fold(#([], [], []), fn(acc, part) {
      case part {
        PlainText(text) ->
          Ok(#([T(blame, [Line(blame, text)]), ..acc.0], acc.1, acc.2))
        ActiveHandle(handle) -> {
          use #(hyperlink, warnings, used) <- on.ok(hyperlink_maybe(
            extract_handle_and_page_and_decoy(handle),
            blame,
            state,
            inner,
          ))
          Ok(#(
            [hyperlink, ..acc.0],
            core.pour(warnings, acc.1),
            core.pour(used, acc.2),
          ))
        }
      }
    }),
  )
  Ok(#(list.reverse(vxmls), list.reverse(warnings), used))
}

fn process_lines(
  lines: List(Line),
  state: State,
  inner: InnerParam,
) -> Result(
  #(List(VXML), List(DesugaringWarning), List(String)),
  DesugaringError,
) {
  use big_list <- on.ok(
    lines
    |> list.map(process_line(_, state, inner))
    |> result.all,
  )

  let vxmls =
    big_list
    |> list.map(fn(triple) { triple.0 })
    |> list.flatten
    |> core.plain_concatenation_in_list

  let warnings =
    big_list
    |> list.map(fn(triple) { triple.1 })
    |> list.flatten

  let used =
    big_list
    |> list.map(fn(triple) { triple.2 })
    |> list.flatten

  Ok(#(vxmls, warnings, used))
}

fn malformed_handle_element(child: VXML, detail: String) -> DesugaringError {
  DesugaringError(child.blame, "malformed Handle element: " <> detail)
}

fn insert_handle_element(
  handles: HandlesDict,
  child: VXML,
  inner: InnerParam,
) -> Result(HandlesDict, DesugaringError) {
  let name = core.v_first_attr_with_key(child, "name")
  let decorators = core.v_first_attr_with_key(child, "decorators")
  let value = core.v_first_attr_with_key(child, "value")
  let id = core.v_first_attr_with_key(child, "id")
  let path = core.v_first_attr_with_key(child, "path")
  use #(name, decorators, value, id, path) <- on.ok(
    case name, decorators, value, id, path {
      Some(name), Some(decorators), Some(value), Some(id), Some(path) ->
        Ok(#(name, decorators, value, id, path))
      _, _, _, _, _ ->
        Error(malformed_handle_element(
          child,
          "expected name, decorators, value, id, and path attributes",
        ))
    },
  )
  use <- on.false_true(
    regexp.check(inner.dictionary_handle_name_regexp, name.val),
    fn() {
      Error(malformed_handle_element(child, "invalid name '" <> name.val <> "'"))
    },
  )
  use value <- on.ok(
    handle_syntax.decode_value(value.val)
    |> result.map_error(fn(_) {
      malformed_handle_element(child, "value must have form <<value>>")
    }),
  )
  use <- on.true_false(dict.has_key(handles, name.val), fn() {
    Error(malformed_handle_element(child, "duplicate name '" <> name.val <> "'"))
  })
  Ok(dict.insert(handles, name.val, #(decorators.val, value, id.val, path.val)))
}

fn grand_wrapper_load(
  state: State,
  children: List(VXML),
  inner: InnerParam,
) -> Result(State, DesugaringError) {
  use handles <- on.ok(
    list.try_fold(children, dict.new(), fn(handles, child) {
      case child {
        V(_, "Handle", _, _) -> insert_handle_element(handles, child, inner)
        _ -> Ok(handles)
      }
    }),
  )
  Ok(State(..state, handles: handles))
}

fn mark_used(used: Set(String), names: List(String)) -> Set(String) {
  list.fold(names, used, fn(acc, name) { set.insert(acc, name) })
}

fn grand_wrapper_record_usage(
  children: List(VXML),
  used: Set(String),
) -> List(VXML) {
  children
  |> list.map(fn(child) {
    case child {
      V(_, "Handle", attrs, _) -> {
        let assert Some(name) = core.v_first_attr_with_key(child, "name")
        let used_value = case set.contains(used, name.val) {
          True -> "true"
          False -> "false"
        }
        let attrs =
          attrs
          |> list.filter(fn(attr) { attr.key != "used" })
          |> list.append([Attr(child.blame, "used", used_value)])
        V(..child, attrs: attrs)
      }
      _ -> child
    }
  })
}

type HrefType {
  InPage
  OutOfPage
  UndefinedOrOutOfDocument
  NotAHandleHref
}

fn substitute_handle_in_href(
  attr: Attr,
  state: State,
) -> #(Attr, HrefType, List(DesugaringWarning), List(String)) {
  assert attr.val |> string.starts_with(">>")
  let handle_name = attr.val |> string.drop_start(2)
  let #(page, handle_name) = case string.ends_with(handle_name, "#page") {
    True -> #(True, handle_name |> string.drop_end(5))
    False -> #(False, handle_name)
  }
  case dict.get(state.handles, handle_name) {
    Ok(#(decorators, _, id, target_path)) -> {
      let page_by_default = has_decorator(decorators, "page")
      let href_type = case target_path == option.unwrap(state.path, "") {
        True -> InPage
        False -> OutOfPage
      }
      let attr = case page || page_by_default, href_type {
        True, _ -> Attr(..attr, val: target_path)
        False, InPage -> Attr(..attr, val: "#" <> id)
        False, OutOfPage -> Attr(..attr, val: target_path <> "#" <> id)
        False, _ -> panic
      }
      #(attr, href_type, [], [handle_name])
    }
    _ -> {
      let warning =
        DesugaringWarning(
          attr.blame,
          "handle '" <> handle_name <> "' is not assigned",
        )
      #(attr, UndefinedOrOutOfDocument, [warning], [])
    }
  }
}

fn substitute_in_href(
  attr: Attr,
  state: State,
  inner: InnerParam,
) -> #(Attr, HrefType, List(DesugaringWarning), List(String)) {
  case attr.key {
    "href" ->
      case handle_text_parts(attr.val, "", inner.handle_candidates_regexp) {
        [PlainText(prefix), ActiveHandle(handle), PlainText("")] -> {
          let #(attr, href_type, warnings, used) =
            substitute_handle_in_href(Attr(..attr, val: handle.content), state)
          #(Attr(..attr, val: prefix <> attr.val), href_type, warnings, used)
        }
        [PlainText(literal)] -> #(
          Attr(..attr, val: literal),
          NotAHandleHref,
          [],
          [],
        )
        _ -> #(attr, NotAHandleHref, [], [])
      }
    _ -> #(attr, NotAHandleHref, [], [])
  }
}

fn substitute_hrefs_in_a(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, "a", attrs, _) = vxml
  use #(attrs, acc) <- on.ok(
    core.try_map_fold(attrs, #(None, [], []), fn(acc, attr) {
      let #(attr, href_type, warnings, used) =
        substitute_in_href(attr, state, inner)
      use acc0 <- on.ok(case acc.0, href_type {
        _, NotAHandleHref -> Ok(acc.0)
        None, _ -> Ok(Some(href_type))
        _, _ ->
          Error(DesugaringError(
            desugarer_blame(511),
            "duplicate 'href' attribute",
          ))
      })
      Ok(#(attr, #(acc0, list.append(warnings, acc.1), core.pour(used, acc.2))))
    }),
  )
  let #(tag, attrs) = case acc.0 {
    Some(InPage) -> #(inner.in_page_tag, core.pour(inner.in_page_attrs, attrs))
    Some(OutOfPage) -> #(
      inner.out_page_tag,
      core.pour(inner.out_page_attrs, attrs),
    )
    _ -> #(vxml.tag, attrs)
  }
  Ok(#(
    V(..vxml, tag: tag, attrs: attrs),
    State(..state, used: mark_used(state.used, acc.2)),
    acc.1,
  ))
}

fn update_state_path(state: State, vxml: VXML, inner: InnerParam) -> State {
  let assert V(_, _, _, _) = vxml
  case core.v_first_attr_with_key(vxml, inner.handle_key) {
    Some(Attr(_, _, value)) -> State(..state, path: Some(value))
    None -> state
  }
}

fn v_before_transform(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, tag, _, children) = vxml
  use state <- on.ok(case tag {
    "GrandWrapper" -> grand_wrapper_load(state, children, inner)
    "Handle" -> Ok(state)
    _ -> Ok(update_state_path(state, vxml, inner))
  })
  let state = case
    state.inside_a_link_tag || !list.contains(inner.link_tags, tag)
  {
    True -> state
    False -> State(..state, inside_a_link_tag: True)
  }
  let state = case state.inside_math || !list.contains(inner.math_tags, tag) {
    True -> state
    False -> State(..state, inside_math: True)
  }
  let state = case state.inside_code_block || tag != "WriterlyCodeBlock" {
    True -> state
    False -> State(..state, inside_code_block: True)
  }
  case tag {
    "a" -> substitute_hrefs_in_a(vxml, state, inner)
    _ -> Ok(#(vxml, state, []))
  }
}

fn v_after_transform(
  vxml: VXML,
  original_state: State,
  latest_state: State,
) -> Result(#(List(VXML), State, List(DesugaringWarning)), DesugaringError) {
  let assert V(_, tag, _, children) = vxml
  let exit_state =
    State(
      ..latest_state,
      inside_a_link_tag: original_state.inside_a_link_tag,
      inside_math: original_state.inside_math,
      inside_code_block: original_state.inside_code_block,
    )
  let vxml = case tag {
    "GrandWrapper" ->
      V(
        ..vxml,
        children: grand_wrapper_record_usage(children, latest_state.used),
      )
    _ -> vxml
  }
  Ok(#([vxml], exit_state, []))
}

fn t_transform(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(List(VXML), State, List(DesugaringWarning)), DesugaringError) {
  let assert T(blame, lines) = vxml

  use <- on.true_false(state.inside_code_block, fn() {
    Ok(#([vxml], state, []))
  })

  // inside math the substitution stays flat text, so the T node survives
  // as a single T node instead of being split into text/link siblings
  use <- on.true_false(state.inside_math, fn() {
    let #(new_lines, warnings, used) =
      process_lines_inside_math(lines, state, inner)
    Ok(#(
      [T(blame, new_lines)],
      State(..state, used: mark_used(state.used, used)),
      warnings,
    ))
  })

  use #(updated_lines, warnings, used) <- on.ok(process_lines(
    lines,
    state,
    inner,
  ))
  Ok(#(
    updated_lines,
    State(..state, used: mark_used(state.used, used)),
    warnings,
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToManyEnterExitStatefulWithWarningsNodemap(State) =
    n2t.OneToManyEnterExitStatefulWithWarningsNodemap(
      on_enter: fn(vxml, state) { v_before_transform(vxml, state, inner) },
      on_exit: fn(vxml, original_state, latest_state) {
        v_after_transform(vxml, original_state, latest_state)
      },
      on_text: fn(vxml, state) { t_transform(vxml, state, inner) },
    )
  nodemap
  |> n2t.one_to_many_enter_exit_stateful_with_warnings_nodemap_2_desugarer_transform(
    State(dict.new(), None, False, False, False, set.new()),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let handle_name = "[\\p{L}\\p{N}\\p{M}_.:'\\-\\^]*[\\p{L}\\p{N}\\p{M}_'\\^]"
  let assert Ok(dictionary_handle_name_regexp) =
    regexp.from_string("^" <> handle_name <> "$")
  let assert Ok(handle_candidates_regexp) =
    regexp.from_string(
      "(\\\\*)(>>)(" <> handle_name <> "(?:#page)?(?:#decoy:[0-9]+)?(?:##)?)",
    )

  Ok(InnerParam(
    handle_key: param.0,
    in_page_tag: param.1,
    out_page_tag: param.2,
    in_page_attrs: param.3 |> core.string_pairs_to_attrs(desugarer_blame(659)),
    out_page_attrs: param.4 |> core.string_pairs_to_attrs(desugarer_blame(660)),
    link_tags: param.5,
    math_tags: param.6,
    handle_candidates_regexp: handle_candidates_regexp,
    dictionary_handle_name_regexp: dictionary_handle_name_regexp,
  ))
}

type HandlesDict =
  Dict(String, #(String, String, String, String))

//                      handle    decorators value   id      path

type State {
  State(
    handles: HandlesDict,
    path: Option(String),
    inside_a_link_tag: Bool,
    // inside one of the param-listed math tags, where a substitution has
    // to be flat LaTeX text rather than an 'a' V-node
    inside_math: Bool,
    // Writerly recognizes definitions but not usages in fenced code content.
    inside_code_block: Bool,
    // names of handles that were actually referenced somewhere in the
    // document; written to each Handle element's 'used' attribute
    used: Set(String),
  )
}

type Param =
  #(
    String,
    // 'path' attribute key
    String,
    // in-page-link tag name
    String,
    // out-page-link tag name
    List(#(String, String)),
    // in-page link attributes
    List(#(String, String)),
    // out-page link attributes
    List(String),
    // tags that already define you as being inside a lin
    List(String),
    // tags whose contents are LaTeX (typically Math, MathBlock)
  )

type InnerParam {
  InnerParam(
    handle_key: String,
    in_page_tag: String,
    out_page_tag: String,
    in_page_attrs: List(Attr),
    out_page_attrs: List(Attr),
    link_tags: List(String),
    math_tags: List(String),
    handle_candidates_regexp: Regexp,
    dictionary_handle_name_regexp: Regexp,
  )
}

pub const name = "writerly_handles_grand_wrapper_substitute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️🏖️

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

/// Expects a document with root 'GrandWrapper' containing structured
/// `Handle` children with `name`, `decorators`, `value`, `id`, and `path`
/// attrs.
///
/// Replaces in-text >>handle_name occurrences and href=>>handle_name attrs
/// by links. The produced link tag and attrs depend on whether the handle's
/// path equals the current local path. A handle using #page links to the page
/// path without appending #id.
///
/// A backslash immediately before '>>' escapes the operator. Odd backslash
/// runs produce literal text; even runs leave the usage active. Each pair of
/// source backslashes becomes one literal backslash.
///
/// Writerly code-block contents are left untouched: definitions
/// are recognized there by the definition desugarer, but usages
/// remain literal and do not mark their target handles as used.
///
/// This desugarer does not rewrite href=#id links and does not remove the
/// GrandWrapper node.
///
/// On its way out it adds a boolean `used` attr to every `Handle` child.
///
/// (see `writerly_handles_grand_wrapper_warn_unused`, which consumes
/// that column).
///
/// Inside any descendant of a tag named in the last param entry
/// (typically "Math" and "MathBlock") the substitution is made in place
/// as plain text, as a LaTeX
///
/// \href{<target_path>}{<value>}
///
/// fragment, rather than as a link V-node: MathJax parses the text
/// content of those nodes as TeX source, and an element node sitting in
/// the middle of it is fed to the TeX parser as literal markup. If the
/// occurrence is immediately wrapped in unspaced parens, both parens are
/// absorbed into the \href value, so the whole "(2.5)" is clickable.
/// An unassigned handle falls back to its #decoy: value if present and
/// otherwise becomes plain 'undefined handle: <name>' text, warning in
/// both cases.
///
/// The #page, #decoy:<digits>, and terminal ## usage suffixes are
/// VXML Pipeline extensions rather than parts of a Writerly handle name.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'before'
                ''
                'after'
      ",
      expected: "
        <> GrandWrapper
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'before'
                ''
                'after'
      ",
    ),
    testing.data(
      param: #(
        "path",
        "InChapterLink",
        "OutChapterLink",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
        ["Math", "MathBlock"],
      ),
      source: "
        <> GrandWrapper
          <> Handle
            name=fluescence
            decorators=
            value=<<AA>>
            id=_23-super-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'some text with >>fluescence in it'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=fluescence
            decorators=
            value=<<AA>>
            id=_23-super-id
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'some text with '
              <> InChapterLink
                href=#_23-super-id
                class=handle-in-chapter-link
                <>
                  'AA'
              <>
                ' in it'
      ",
    ),
    testing.data(
      param: #(
        "path",
        "InChapterLink",
        "OutChapterLink",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
        ["Math", "MathBlock"],
      ),
      source: "
        <> GrandWrapper
          id=section-1 ./ch1.html
          <> Handle
            name=section
            decorators=
            value=<<Section 1>>
            id=section-1
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch2.html
              <> a
                href=#section-1
                <>
                  'local-looking id link'
              <> a
                href=>>section
                <>
                  'handle attr link'
      ",
      expected: "
        <> GrandWrapper
          id=section-1 ./ch1.html
          <> Handle
            name=section
            decorators=
            value=<<Section 1>>
            id=section-1
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch2.html
              <> a
                href=#section-1
                <>
                  'local-looking id link'
              <> OutChapterLink
                class=handle-out-chapter-link
                href=./ch1.html#section-1
                <>
                  'handle attr link'
      ",
    ),
    // a handle nowhere referenced gets an empty 'used' column
    testing.data(
      param: #(
        "path",
        "InChapterLink",
        "OutChapterLink",
        [#("class", "handle-in-chapter-link")],
        [#("class", "handle-out-chapter-link")],
        ["a"],
        ["Math", "MathBlock"],
      ),
      source: "
        <> GrandWrapper
          <> Handle
            name=lonely
            decorators=
            value=<<(1.1)>>
            id=eq-1
            path=./ch1.html
          <> Handle
            name=in-math-only
            decorators=
            value=<<(1.2)>>
            id=eq-2
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=eq-2
                <>
                  'x = y'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=lonely
            decorators=
            value=<<(1.1)>>
            id=eq-1
            path=./ch1.html
            used=false
          <> Handle
            name=in-math-only
            decorators=
            value=<<(1.2)>>
            id=eq-2
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                id=eq-2
                <>
                  'x = y'
      ",
    ),

    // inside math: substitution is flat \\href text, and unspaced
    // surrounding parens fold into the link value
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '(>>some_handle) a + b = 2'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '\\href{./ch1.html#eq-id}{(2)} a + b = 2'
      ",
    ),
    // inside math without surrounding parens: no folding
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                <>
                  'see >>some_handle for details'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                <>
                  'see \\href{./ch1.html#eq-id}{2} for details'
      ",
    ),
    // inside math, #page suffix: links to the page, no #id
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                <>
                  'see >>some_handle#page for the page'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                <>
                  'see \\href{./ch1.html}{2} for the page'
      ",
    ),
    // inside math, unassigned handle with a #decoy: falls back to it
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=other
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '(>>missing#decoy:26) a + b'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=other
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '\\href{decoy-target-path#decoy-id}{(26)} a + b'
      ",
    ),
    // inside math, unassigned handle without decoy: plain text, no node
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=other
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '>>missing a + b'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=other
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  'undefined handle: missing a + b'
      ",
    ),
    // outside math the very same occurrence becomes a link node
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <>
                '(>>some_handle) is outside of math'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <>
                '('
              <> a
                href=#eq-id
                <>
                  '2'
              <>
                ') is outside of math'
        ",
    ),

    // Escaped usages remain literal text and do not mark the handle used.
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'see \\>>some_handle for details'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'see >>some_handle for details'
      ",
    ),

    // An even backslash run decodes to one literal backslash and leaves the
    // usage active.
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'see \\\\>>some_handle for details'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'see \\'
              <> a
                href=#eq-id
                <>
                  '2'
              <>
                ' for details'
      ",
    ),

    // Escaping follows the same parity rule inside math text.
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '\\>>some_handle and \\\\>>some_handle'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '>>some_handle and \\\\href{./ch1.html#eq-id}{2}'
      ",
    ),

    // Escaped href usages become literal href values without substitution.
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> a
                href=\\>>some_handle
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=some_handle
            decorators=
            value=<<2>>
            id=eq-id
            path=./ch1.html
            used=false
          <> root
            <> Chapter
              path=./ch1.html
              <> a
                href=>>some_handle
        ",
    ),

    // Usage names accept the extension's Unicode handle grammar.
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=δοκιμή_2
            decorators=
            value=<<value>>
            id=id
            path=./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'see >>δοκιμή_2'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=δοκιμή_2
            decorators=
            value=<<value>>
            id=id
            path=./ch1.html
            used=true
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'see '
              <> a
                href=#id
                <>
                  'value'
              <>
                ''
      ",
    ),
    testing.data(
      param: #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      source: "
        <> GrandWrapper
          <> Handle
            name=code_handle
            decorators=
            value=<<code value>>
            id=code-id
            path=./chapter.html
          <> root
            <> WriterlyCodeBlock
              <>
                'literal >>code_handle usage'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=code_handle
            decorators=
            value=<<code value>>
            id=code-id
            path=./chapter.html
            used=false
          <> root
            <> WriterlyCodeBlock
              <>
                'literal >>code_handle usage'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
