import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type DesugaringWarning, DesugaringError, DesugaringWarning,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Match, type Regexp, Match}
import gleam/result
import gleam/set.{type Set}
import gleam/string.{inspect as ins}
import on
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame} as bl

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

fn hyperlink_constructor(
  handle: #(Bool, String, String, String),
  page: Bool,
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> Result(VXML, DesugaringError) {
  let #(page_by_default, value, id, target_path) = handle

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
  let #(tag, attrs) = case target_path == our_path {
    True -> #(inner.in_page_tag, inner.in_page_attrs)
    False -> #(inner.out_page_tag, inner.out_page_attrs)
  }
  let page = page || page_by_default
  let target_path = case page {
    True -> target_path
    False -> target_path <> "#" <> id
  }
  let attrs = [Attr(blame, "href", target_path), ..attrs]
  Ok(V(blame, tag, attrs, [T(blame, [Line(blame, value)])]))
}

fn warning_element(handle_name: String, blame: Blame) -> VXML {
  V(desugarer_blame(68), "InTextWarning", [], [
    T(desugarer_blame(69), [
      Line(
        desugarer_blame(71),
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
      let quad = #(False, decoy, "decoy-id", "decoy-target-path")
      hyperlink_constructor(quad, page, blame, state, inner)
    }
  })

  let actual_warning =
    DesugaringWarning(blame, "handle '" <> handle_name <> "' is not assigned")

  Ok(#(warning_span_or_decoy_link, [actual_warning], []))
}

fn matches_2_hyperlinks(
  matches: List(Match),
  blame: Blame,
  state: State,
  inner: InnerParam,
) -> Result(
  #(List(VXML), List(DesugaringWarning), List(String)),
  DesugaringError,
) {
  let handles_and_pages_and_decoys =
    matches |> list.map(extract_handle_and_page_and_decoy)
  use #(vxmls, warnings, used) <- on.ok(
    list.try_fold(
      handles_and_pages_and_decoys,
      #([], [], []),
      fn(acc, handle_and_page_and_decoy) {
        use #(vxml, warnings, used) <- on.ok(hyperlink_maybe(
          handle_and_page_and_decoy,
          blame,
          state,
          inner,
        ))
        Ok(#(
          [vxml, ..acc.0],
          core.pour(warnings, acc.1),
          core.pour(used, acc.2),
        ))
      },
    ),
  )
  Ok(#(vxmls |> list.reverse, warnings |> list.reverse, used))
}

fn augment_to_1_mod_3(splits: List(String)) -> List(String) {
  case list.length(splits) % 3 != 1 {
    True -> {
      let assert True = list.is_empty(splits) as { ins(splits) }
      [""]
    }
    False -> splits
  }
}

fn retain_0_mod_3(splits: List(String)) -> List(String) {
  splits
  |> list.index_fold(from: [], with: fn(acc, split, index) {
    case index % 3 == 0 {
      True -> [split, ..acc]
      False -> acc
    }
  })
  |> list.reverse
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
    Ok(#(page_by_default, value, id, target_path)) -> {
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
fn rebuild(
  splits: List(String),
  matches: List(Match),
  blame: Blame,
  state: State,
) -> #(String, List(DesugaringWarning), List(String)) {
  case splits, matches {
    [last], [] -> #(last, [], [])
    [before, next, ..rest_splits], [m, ..rest_matches] -> {
      let fold = string.ends_with(before, "(") && string.starts_with(next, ")")
      let #(before, next) = case fold {
        True -> #(string.drop_end(before, 1), string.drop_start(next, 1))
        False -> #(before, next)
      }
      let #(sub_text, warnings, used) =
        substitution_text(
          extract_handle_and_page_and_decoy(m),
          blame,
          fold,
          state,
        )
      let #(rest_text, rest_warnings, rest_used) =
        rebuild([next, ..rest_splits], rest_matches, blame, state)
      #(
        before <> sub_text <> rest_text,
        core.pour(warnings, rest_warnings),
        core.pour(used, rest_used),
      )
    }
    _, _ ->
      panic as "splits/matches length mismatch in handles_grand_wrapper_substitute"
  }
}

fn process_line_inside_math(
  line: Line,
  matches: List(Match),
  state: State,
  inner: InnerParam,
) -> #(Line, List(DesugaringWarning), List(String)) {
  let Line(blame, content) = line
  let splits =
    regexp.split(inner.handles_regexp, content)
    |> augment_to_1_mod_3
    |> retain_0_mod_3
  let #(new_content, warnings, used) = rebuild(splits, matches, blame, state)
  #(Line(blame, new_content), warnings, used)
}

fn process_lines_inside_math(
  lines: List(Line),
  state: State,
  inner: InnerParam,
) -> #(List(Line), List(DesugaringWarning), List(String)) {
  let triples =
    lines
    |> list.map(fn(line) {
      case regexp.scan(inner.handles_regexp, line.content) {
        [] -> #(line, [], [])
        matches -> process_line_inside_math(line, matches, state, inner)
      }
    })
  #(
    triples |> list.map(fn(triple) { triple.0 }),
    triples |> list.map(fn(triple) { triple.1 }) |> list.flatten,
    triples |> list.map(fn(triple) { triple.2 }) |> list.flatten,
  )
}

fn split_2_t(split: String, blame: Blame) -> VXML {
  T(blame, [Line(blame, split)])
}

fn splits_2_ts(splits: List(String), blame: Blame) -> List(VXML) {
  splits
  |> augment_to_1_mod_3
  |> retain_0_mod_3
  |> list.map(split_2_t(_, blame))
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
  case regexp.scan(inner.handles_regexp, content) {
    [_, ..] as matches -> {
      let splits = regexp.split(inner.handles_regexp, content)
      use #(hyperlinks, warnings, used) <- on.ok(matches_2_hyperlinks(
        matches,
        blame,
        state,
        inner,
      ))
      let text_nodes = splits_2_ts(splits, blame)
      let vxmls =
        list.interleave([text_nodes, hyperlinks])
        |> core.last_to_first_concatenation
      Ok(#(vxmls, warnings, used))
    }
    [] -> Ok(#([T(line.blame, [line])], [], []))
  }
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

fn grand_wrapper_load(state: State, attrs: List(Attr)) -> State {
  let #(handles, _) = core.attrs_extract_key_occurrences(attrs, "handle")

  let handles =
    list.fold(handles, dict.new(), fn(acc, attr) {
      let assert [handle_name, page, value, id, path] =
        attr.val |> string.split("|")
      let page = case page {
        "#page" -> True
        "" -> False
        _ -> panic as "malformed GrandWrapper dictionary"
      }
      dict.insert(acc, handle_name, #(page, value, id, path))
    })

  State(..state, handles: handles)
}

fn mark_used(used: Set(String), names: List(String)) -> Set(String) {
  list.fold(names, used, fn(acc, name) { set.insert(acc, name) })
}

/// Appends a 6th 'used' column to each handle dictionary entry of the
/// GrandWrapper, turning
///
/// handle=<name>|<page>|<value>|<id>|<path>
///
/// into
///
/// handle=<name>|<page>|<value>|<id>|<path>|used     (handle was referenced)
/// handle=<name>|<page>|<value>|<id>|<path>|         (handle was never referenced)
fn grand_wrapper_record_usage(
  attrs: List(Attr),
  used: Set(String),
) -> List(Attr) {
  attrs
  |> list.map(fn(attr) {
    case attr.key == "handle" {
      False -> attr
      True -> {
        let assert [handle_name, _, _, _, _] = attr.val |> string.split("|")
        let suffix = case set.contains(used, handle_name) {
          True -> "|used"
          False -> "|"
        }
        Attr(..attr, val: attr.val <> suffix)
      }
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
    Ok(#(page_by_default, _, id, target_path)) -> {
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
) -> #(Attr, HrefType, List(DesugaringWarning), List(String)) {
  case attr.key == "href", attr.val {
    True, ">>" <> _ -> substitute_handle_in_href(attr, state)
    _, _ -> #(attr, NotAHandleHref, [], [])
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
      let #(attr, href_type, warnings, used) = substitute_in_href(attr, state)
      use acc0 <- on.ok(case acc.0, href_type {
        _, NotAHandleHref -> Ok(acc.0)
        None, _ -> Ok(Some(href_type))
        _, _ ->
          Error(DesugaringError(
            desugarer_blame(467),
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
  let assert V(_, tag, attrs, _) = vxml
  let state = case tag {
    "GrandWrapper" -> grand_wrapper_load(state, attrs)
    _ -> update_state_path(state, vxml, inner)
  }
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
  let assert V(_, tag, attrs, _) = vxml
  let exit_state =
    State(
      ..latest_state,
      inside_a_link_tag: original_state.inside_a_link_tag,
      inside_math: original_state.inside_math,
    )
  let vxml = case tag {
    "GrandWrapper" ->
      V(..vxml, attrs: grand_wrapper_record_usage(attrs, latest_state.used))
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
    State(dict.new(), None, False, False, set.new()),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(handles_regexp) =
    regexp.from_string(
      "(>>)([\\w^.:'-]+[\\w'](?:#page)?(?:#decoy:[0-9]+)?(?:##)?)",
    )

  Ok(InnerParam(
    handle_key: param.0,
    in_page_tag: param.1,
    out_page_tag: param.2,
    in_page_attrs: param.3 |> core.string_pairs_to_attrs(desugarer_blame(594)),
    out_page_attrs: param.4 |> core.string_pairs_to_attrs(desugarer_blame(595)),
    link_tags: param.5,
    math_tags: param.6,
    handles_regexp: handles_regexp,
  ))
}

type HandlesDict =
  Dict(String, #(Bool, String, String, String))

//                      handle    #page value   id      path
//                                by
//                                default

type State {
  State(
    handles: HandlesDict,
    path: Option(String),
    inside_a_link_tag: Bool,
    // inside one of the param-listed math tags, where a substitution has
    // to be flat LaTeX text rather than an 'a' V-node
    inside_math: Bool,
    // names of handles that were actually referenced somewhere in the
    // document; written back to the GrandWrapper dictionary as a 6th
    // 'used' column, for downstream unused-handle reporting
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
    handles_regexp: Regexp,
  )
}

pub const name = "handles_grand_wrapper_substitute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️🏖️

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

/// Expects a document with root 'GrandWrapper' whose attrs include handle
/// dictionary entries of the form:
///
/// handle=handle_name|page_flag|value|id|path
///
/// Replaces in-text >>handle_name occurrences and href=>>handle_name attrs
/// by links. The produced link tag and attrs depend on whether the handle's
/// path equals the current local path. A handle using #page links to the page
/// path without appending #id.
///
/// This desugarer does not rewrite href=#id links and does not remove the
/// GrandWrapper node.
///
/// On its way out it appends a 6th 'used' column to every GrandWrapper
/// handle entry, recording whether the handle was referenced anywhere in
/// the document:
///
/// handle=handle_name|page_flag|value|id|path|used
/// handle=handle_name|page_flag|value|id|path|
///
/// (see `handles_grand_wrapper_warn_unused`, which consumes
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
          handle=fluescence||AA|_23-super-id|./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'some text with >>fluescence in it'
      ",
      expected: "
        <> GrandWrapper
          handle=fluescence||AA|_23-super-id|./ch1.html|used
          <> root
            <> Chapter
              path=./ch1.html
              <>
                'some text with '
              <> InChapterLink
                href=./ch1.html#_23-super-id
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
          handle=section||Section 1|section-1|./ch1.html
          id=section-1 ./ch1.html
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
          handle=section||Section 1|section-1|./ch1.html|used
          id=section-1 ./ch1.html
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
          handle=lonely||(1.1)|eq-1|./ch1.html
          handle=in-math-only||(1.2)|eq-2|./ch1.html
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
          handle=lonely||(1.1)|eq-1|./ch1.html|
          handle=in-math-only||(1.2)|eq-2|./ch1.html|
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
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '(>>some_handle) a + b = 2'
      ",
      expected: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html|used
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
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                <>
                  'see >>some_handle for details'
      ",
      expected: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html|used
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
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> MathBlock
                <>
                  'see >>some_handle#page for the page'
      ",
      expected: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html|used
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
          handle=other||2|eq-id|./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '(>>missing#decoy:26) a + b'
      ",
      expected: "
        <> GrandWrapper
          handle=other||2|eq-id|./ch1.html|
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
          handle=other||2|eq-id|./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <> Math
                <>
                  '>>missing a + b'
      ",
      expected: "
        <> GrandWrapper
          handle=other||2|eq-id|./ch1.html|
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
          handle=some_handle||2|eq-id|./ch1.html
          <> root
            <> Chapter
              path=./ch1.html
              <>
                '(>>some_handle) is outside of math'
      ",
      expected: "
        <> GrandWrapper
          handle=some_handle||2|eq-id|./ch1.html|used
          <> root
            <> Chapter
              path=./ch1.html
              <>
                '('
              <> a
                href=./ch1.html#eq-id
                <>
                  '2'
              <>
                ') is outside of math'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
