import desugaring/core.{pour}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/string.{inspect as ins}
import vxml.{type VXML, T, V}
import vxml/blame.{type Blame} as bl
import vxml/io_lines.{type OutputLine, OutputLine} as io_l

// tracking-related part 1: types
// ************************************************************

/// A VXML instance is serialized into a list of SLine for the
/// purposes of tracking (see "--track" command line option);
/// each SLine (for "Selected (or not) Line") is one of four
/// variants:
///
/// - VSLine: a tag "<> ..." of a V-node
/// - ASLine: a key-attr pair line "key=val" of a V-node
/// - TSLine: the caret "<>" that marks the start of a T-node
/// - LSLine: a content-line for a T-node
///
/// Each SLine comes with a selection status, given by its 'selected'
/// field.
pub type SLine {
  VSLine(
    blame: Blame,
    indent: Int,
    content: String,
    selected: SelectionStatus,
    tag: String,
  )
  ASLine(
    blame: Blame,
    indent: Int,
    content: String,
    selected: SelectionStatus,
    key: String,
    val: String,
  )
  TSLine(blame: Blame, indent: Int, content: String, selected: SelectionStatus)
  LSLine(blame: Blame, indent: Int, content: String, selected: SelectionStatus)
}

pub type SelectionStatus {
  NotSelected
  OG
  Bystander
}

pub type LineSelector =
  fn(SLine) -> SelectionStatus

pub type Selector =
  fn(List(SLine)) -> List(SLine)

// ************************************************************
// tracking-related part 2: VXML -> List(SLine)
// ************************************************************

fn v_s_line(blame: Blame, indent: Int, tag: String) -> SLine {
  VSLine(blame, indent, "<> " <> tag, NotSelected, tag)
}

fn a_s_line(blame: Blame, indent: Int, key: String, val: String) -> SLine {
  ASLine(blame, indent, key <> "=" <> val, NotSelected, key, val)
}

fn t_s_line(blame: Blame, indent: Int) -> SLine {
  TSLine(blame, indent, "<>", NotSelected)
}

fn l_s_line(blame: Blame, indent: Int, content: String) -> SLine {
  LSLine(
    blame,
    indent,
    vxml.vxml_line_delimiter <> content <> vxml.vxml_line_delimiter,
    NotSelected,
  )
}

fn v_s_lines(vxml: VXML, indent: Int) -> List(SLine) {
  let assert V(blame, tag, attrs, _) = vxml
  let attrs =
    attrs
    |> list.map(fn(a) { a_s_line(a.blame, indent + 2, a.key, a.val) })
  [v_s_line(blame, indent, tag), ..attrs]
}

fn t_s_lines(vxml: VXML, indent: Int) -> List(SLine) {
  let assert T(blame, lines) = vxml
  let lines =
    lines
    |> list.map(fn(line) { l_s_line(line.blame, indent + 2, line.content) })
  [t_s_line(blame, indent), ..lines]
}

fn vxml_to_s_lines_internal(
  previous_lines: List(SLine),
  vxml: VXML,
  indent: Int,
) -> List(SLine) {
  case vxml {
    V(_, _, _, children) -> {
      list.fold(
        children,
        pour(v_s_lines(vxml, indent), previous_lines),
        fn(acc, child) { vxml_to_s_lines_internal(acc, child, indent + 2) },
      )
    }
    T(..) -> {
      pour(t_s_lines(vxml, indent), previous_lines)
    }
  }
}

pub fn vxml_to_s_lines(vxml: VXML) -> List(SLine) {
  vxml_to_s_lines_internal([], vxml, 0)
  |> list.reverse
}

// ************************************************************
// tracking-related part 3: creating an initial selection from a LineSelector
// ************************************************************

pub fn apply_line_selector_to_line(
  line: SLine,
  line_selector: LineSelector,
) -> SLine {
  let sel = line_selector(line)
  case line {
    VSLine(_, _, _, _, _) -> VSLine(..line, selected: sel)
    ASLine(_, _, _, _, _, _) -> ASLine(..line, selected: sel)
    TSLine(_, _, _, _) -> TSLine(..line, selected: sel)
    LSLine(_, _, _, _) -> LSLine(..line, selected: sel)
  }
}

pub fn line_selector_to_selector(line_selector: LineSelector) -> Selector {
  list.map(_, apply_line_selector_to_line(_, line_selector))
}

// ************************************************************
// tracking-related part 4: List(SLine) -> List(SLine) operations (extending selections)
// ************************************************************

fn bring_to_bystander_level(line: SLine) -> SLine {
  case line.selected {
    OG | Bystander -> line
    _ ->
      case line {
        VSLine(_, _, _, _, _) -> VSLine(..line, selected: Bystander)
        ASLine(_, _, _, _, _, _) -> ASLine(..line, selected: Bystander)
        TSLine(_, _, _, _) -> TSLine(..line, selected: Bystander)
        LSLine(_, _, _, _) -> LSLine(..line, selected: Bystander)
      }
  }
}

fn is_v_or_t_s_line(line: SLine) -> Bool {
  case line {
    VSLine(_, _, _, _, _) -> True
    TSLine(_, _, _, _) -> True
    _ -> False
  }
}

fn is_a_s_line(line: SLine) -> Bool {
  case line {
    ASLine(_, _, _, _, _, _) -> True
    _ -> False
  }
}

fn is_og(line: SLine) -> Bool {
  line.selected == OG
}

fn extend_selection_down_no_reverse(
  lines: List(SLine),
  amt: Int,
) -> List(SLine) {
  let assert True = amt >= 0
  list.fold(lines, #(0, []), fn(acc, line) {
    let #(gas, lines) = acc
    let gas = case line.selected == OG {
      True -> amt + 1
      False -> gas - 1
    }
    let lines = case gas > 0 {
      True -> [line |> bring_to_bystander_level, ..lines]
      False -> [line, ..lines]
    }
    #(gas, lines)
  })
  |> pair.second
}

pub fn extend_selection_down(lines: List(SLine), amt: Int) -> List(SLine) {
  lines
  |> extend_selection_down_no_reverse(amt)
  |> list.reverse
}

pub fn extend_selection_up(lines: List(SLine), amt: Int) -> List(SLine) {
  lines
  |> list.reverse
  |> extend_selection_down_no_reverse(amt)
}

pub fn extend_selection_to_ancestors(
  lines: List(SLine),
  with_elder_siblings w1: Bool,
  with_ancestor_attrs w2: Bool,
  with_elder_sibling_attrs w3: Bool,
) -> List(SLine) {
  lines
  |> list.reverse
  |> list.fold(#(-1, []), fn(acc, line) {
    let #(indent, lines) = acc
    let is_v_or_t = is_v_or_t_s_line(line)
    let is_a = is_a_s_line(line)
    let line = case
      { line.indent < indent }
      || { line.indent == indent && { { is_v_or_t && w1 } || { is_a && w2 } } }
      || { line.indent == indent + 2 && w1 && is_a && w3 }
    {
      True -> line |> bring_to_bystander_level
      False -> line
    }
    let indent = case
      { line.indent < indent && is_v_or_t }
      || { line.indent > indent && is_og(line) }
    {
      True -> line.indent
      False -> indent
    }
    #(indent, [line, ..lines])
  })
  |> pair.second
}

pub fn extend_selector_up(f: Selector, amt: Int) -> Selector {
  fn(lines) {
    lines
    |> f
    |> extend_selection_up(amt)
  }
}

pub fn extend_selector_down(f: Selector, amt: Int) -> Selector {
  fn(lines) {
    lines
    |> f
    |> extend_selection_down(amt)
  }
}

pub fn extend_selector_to_ancestors(
  f: Selector,
  with_elder_siblings w1: Bool,
  with_ancestor_attrs w2: Bool,
  with_elder_sibling_attrs w3: Bool,
) -> Selector {
  fn(lines) {
    lines
    |> f
    |> extend_selection_to_ancestors(w1, w2, w3)
  }
}

// ************************************************************
// tracking-related part 5: or-ing Selectors (esoteric, but we do it)
// ************************************************************

fn or_a_pair_of_s_lines(l1: SLine, l2: SLine) -> SLine {
  // let assert True = l1.content == l2.content
  // let assert True = l1.indent == l2.indent
  // let assert True = l1.blame == l2.blame
  case l1.selected, l2.selected {
    OG, _ -> l1
    _, OG -> l2
    Bystander, _ -> l1
    _, Bystander -> l2
    _, _ -> l1
  }
}

fn or_two_lists_of_s_lines(l1: List(SLine), l2: List(SLine)) -> List(SLine) {
  let assert True = list.length(l1) == list.length(l2)
  list.map2(l1, l2, or_a_pair_of_s_lines)
}

pub fn or_selectors(s1: Selector, s2: Selector) -> Selector {
  fn(lines) {
    let l1 = lines |> s1
    let l2 = lines |> s2
    or_two_lists_of_s_lines(l1, l2)
  }
}

// ************************************************************
// tracking-related part 6: pretty-printing selections
// ************************************************************

type SelectionOutputState {
  SelectionOutputState(
    has_selected_lines: Bool,
    omitted_lines: Option(#(Int, Int)),
    output_lines: List(OutputLine),
  )
}

@internal
pub fn s_line_to_output_line(line: SLine) -> OutputLine {
  OutputLine(line.blame, line.indent, line.content)
}

@internal
pub fn s_lines_to_output_lines(
  lines: List(SLine),
  dry_run: Bool,
) -> List(OutputLine) {
  s_lines_to_output_lines_with(lines, dry_run, True)
}

@internal
pub fn s_lines_to_output_lines_with(
  lines: List(SLine),
  dry_run: Bool,
  include_ellipses: Bool,
) -> List(OutputLine) {
  let s2l = s_line_to_output_line
  lines
  |> list.fold(SelectionOutputState(False, None, []), fn(state, line) {
    case line.selected {
      OG | Bystander ->
        case state.omitted_lines {
          None ->
            SelectionOutputState(
              has_selected_lines: True,
              omitted_lines: None,
              output_lines: [line |> s2l, ..state.output_lines],
            )

          Some(#(indentation, num_lines)) ->
            SelectionOutputState(
              has_selected_lines: True,
              omitted_lines: None,
              output_lines: case include_ellipses {
                True -> [
                  line |> s2l,
                  OutputLine(
                    bl.NoBlame([
                      ins(case dry_run {
                        True -> 0
                        False -> num_lines
                      })
                      <> " unselected lines",
                    ]),
                    indentation,
                    "...",
                  ),
                  ..state.output_lines
                ]
                False -> [line |> s2l, ..state.output_lines]
              },
            )
        }
      NotSelected ->
        case state.has_selected_lines, state.omitted_lines {
          False, None -> state

          True, None ->
            SelectionOutputState(
              ..state,
              omitted_lines: Some(#(line.indent, 1)),
            )

          True, Some(#(indentation, num_lines)) ->
            SelectionOutputState(
              ..state,
              omitted_lines: Some(#(
                int.min(line.indent, indentation),
                num_lines + 1,
              )),
            )

          False, Some(_) -> panic as "shouldn't reach this combo"
        }
    }
  })
  |> fn(state) { state.output_lines }
  |> list.reverse
}

@internal
pub fn s_lines_table_lines(
  lines: List(SLine),
  banner: String,
  dry_run: Bool,
  indent: Int,
) -> List(String) {
  lines
  |> s_lines_to_output_lines(dry_run)
  |> io_l.output_lines_table_lines(banner, indent)
}

@internal
pub fn s_lines_table_lines_with(
  lines: List(SLine),
  banner: String,
  dry_run: Bool,
  indent: Int,
  blame_digest_margin: bl.BlameTableMarginColumnsMinMax,
  comments_margin: bl.BlameTableMarginColumnsMinMax,
) -> List(String) {
  lines
  |> s_lines_to_output_lines(dry_run)
  |> io_l.output_lines_table_lines_with(
    banner,
    indent,
    blame_digest_margin,
    comments_margin,
  )
}

@internal
pub fn s_lines_table_lines_with_options(
  lines: List(SLine),
  banner: String,
  dry_run: Bool,
  indent: Int,
  blame_digest_margin: bl.BlameTableMarginColumnsMinMax,
  comments_margin: bl.BlameTableMarginColumnsMinMax,
  include_ellipses: Bool,
) -> List(String) {
  lines
  |> s_lines_to_output_lines_with(dry_run, include_ellipses)
  |> io_l.output_lines_table_lines_with(
    banner,
    indent,
    blame_digest_margin,
    comments_margin,
  )
}

@internal
pub fn s_lines_verbatim_lines(
  lines: List(SLine),
  dry_run: Bool,
) -> List(String) {
  lines
  |> s_lines_to_output_lines(dry_run)
  |> list.map(io_l.output_line_to_string)
}

@internal
pub fn s_lines_verbatim_lines_with_options(
  lines: List(SLine),
  dry_run: Bool,
  include_ellipses: Bool,
) -> List(String) {
  lines
  |> s_lines_to_output_lines_with(dry_run, include_ellipses)
  |> list.map(io_l.output_line_to_string)
}

@internal
pub fn s_lines_table(
  lines: List(SLine),
  banner: String,
  dry_run: Bool,
  indent: Int,
) -> String {
  lines
  |> s_lines_to_output_lines(dry_run)
  |> io_l.output_lines_table(banner, indent)
}
