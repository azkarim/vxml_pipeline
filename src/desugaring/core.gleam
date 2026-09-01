import either_or as eo
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string.{inspect as ins}
import on
import splitter
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame} as bl

// ************************************************************
// Traffic Light for early returns
// ************************************************************

pub type TrafficLight {
  Continue
  GoBack
}

// ************************************************************
// Helper Types
// ************************************************************
pub type ContextualVXMLCondition =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) -> Bool

// ************************************************************
// LatexDelimiterPair, LatexDelimiterSingleton
// ************************************************************

pub type LatexDelimiterPair {
  DoubleDollar
  SingleDollar
  BackslashParenthesis
  BackslashSquareBracket
  BeginEndAlign
  BeginEndAlignStar
  // a standalone display environment named `name`, i.e. the delimiter pair
  // `\begin{name}` … `\end{name}` (e.g. name == "equation", "gather*", …). Which
  // environments are recognized, and whether each is `$$`-wrapped, is a consumer
  // policy decision (e.g. dr's formatter display_delimiter_dollar_policy).
  BeginEndEnvironment(name: String)
}

pub type LatexDelimiterSingleton {
  DoubleDollarSingleton
  SingleDollarSingleton
  BackslashOpeningParenthesis
  BackslashClosingParenthesis
  BackslashOpeningSquareBracket
  BackslashClosingSquareBracket
  BeginAlign
  EndAlign
  BeginAlignStar
  EndAlignStar
  BeginEnvironment(name: String)
  EndEnvironment(name: String)
}

pub fn latex_inline_delimiters() -> List(LatexDelimiterPair) {
  [SingleDollar, BackslashParenthesis]
}

pub fn latex_strippable_display_delimiters() -> List(LatexDelimiterPair) {
  [DoubleDollar, BackslashSquareBracket]
}

pub fn latex_strippable_delimiter_pairs() -> List(LatexDelimiterPair) {
  [DoubleDollar, SingleDollar, BackslashParenthesis, BackslashSquareBracket]
}

pub fn opening_and_closing_string_for_pair(
  pair: LatexDelimiterPair,
) -> #(String, String) {
  case pair {
    DoubleDollar -> #("$$", "$$")
    SingleDollar -> #("$", "$")
    BackslashParenthesis -> #("\\(", "\\)")
    BackslashSquareBracket -> #("\\[", "\\]")
    BeginEndAlign -> #("\\begin{align}", "\\end{align}")
    BeginEndAlignStar -> #("\\begin{align*}", "\\end{align*}")
    BeginEndEnvironment(name) -> #(
      "\\begin{" <> name <> "}",
      "\\end{" <> name <> "}",
    )
  }
}

pub fn opening_and_closing_singletons_for_pair(
  pair: LatexDelimiterPair,
) -> #(LatexDelimiterSingleton, LatexDelimiterSingleton) {
  case pair {
    DoubleDollar -> #(DoubleDollarSingleton, DoubleDollarSingleton)
    SingleDollar -> #(SingleDollarSingleton, SingleDollarSingleton)
    BackslashParenthesis -> #(
      BackslashOpeningParenthesis,
      BackslashClosingParenthesis,
    )
    BackslashSquareBracket -> #(
      BackslashOpeningSquareBracket,
      BackslashClosingSquareBracket,
    )
    BeginEndAlign -> #(BeginAlign, EndAlign)
    BeginEndAlignStar -> #(BeginAlignStar, EndAlignStar)
    BeginEndEnvironment(name) -> #(BeginEnvironment(name), EndEnvironment(name))
  }
}

pub fn opening_and_closing_delimiter_strings(
  delimiters: List(LatexDelimiterPair),
) -> #(List(String), List(String)) {
  delimiters
  |> list.map(opening_and_closing_string_for_pair)
  |> list.unzip
}

// ************************************************************
// use <- utilities
// ************************************************************

pub fn on_t_on_v(
  node: VXML,
  f1: fn(Blame, List(Line)) -> c,
  f2: fn(Blame, String, List(Attr), List(VXML)) -> c,
) -> c {
  case node {
    T(blame, lines) -> f1(blame, lines)
    V(blame, tag, attrs, children) -> f2(blame, tag, attrs, children)
  }
}

// ************************************************************
// descendant_ text_contains/!text_contains
// ************************************************************

pub fn descendant_lines(v: VXML) -> List(Line) {
  case v {
    T(_, lines) -> lines
    V(_, _, _, children) -> {
      list.flat_map(children, descendant_lines)
    }
  }
}

pub fn descendant_text_contains(v: VXML, s: String) -> Bool {
  case v {
    T(_, lines) -> lines_contain(lines, s)
    V(_, _, _, children) -> list.any(children, descendant_text_contains(_, s))
  }
}

pub fn descendant_text_does_not_contain(vxml: VXML, s: String) -> Bool {
  !descendant_text_contains(vxml, s)
}

pub fn filter_descendants(
  vxml: VXML,
  condition: fn(VXML) -> Bool,
) -> List(VXML) {
  case vxml {
    T(..) -> []
    V(_, _, _, children) -> {
      let matching_children = list.filter(children, condition)
      let descendants_from_children =
        list.flat_map(children, filter_descendants(_, condition))
      list.append(matching_children, descendants_from_children)
    }
  }
}

pub fn descendants_with_tag(vxml: VXML, tag: String) -> List(VXML) {
  filter_descendants(vxml, is_v_and_tag_equals(_, tag))
}

pub fn descendants_with_class(vxml: VXML, class: String) -> List(VXML) {
  filter_descendants(vxml, is_v_and_has_class(_, class))
}

// ************************************************************
// option
// ************************************************************

pub fn with_default(o: Option(a), default: a) -> Option(a) {
  case o {
    None -> Some(default)
    _ -> o
  }
}

// ************************************************************
// string
// ************************************************************

pub fn drop_suffix(s: String, suffix: String) -> String {
  case string.ends_with(s, suffix) {
    True -> string.drop_end(s, suffix |> string.length)
    False -> s
  }
}

pub fn drop_prefix(s: String, prefix: String) -> String {
  case string.starts_with(s, prefix) {
    True -> string.drop_start(s, prefix |> string.length)
    False -> s
  }
}

pub fn assert_drop_prefix(s: String, prefix: String) -> String {
  case string.starts_with(s, prefix) {
    True -> string.drop_start(s, prefix |> string.length)
    False -> panic
  }
}

pub fn ensure_prefix(s: String, prefix: String) -> String {
  case string.starts_with(s, prefix) {
    True -> s
    False -> prefix <> s
  }
}

pub fn ensure_suffix(s: String, suffix: String) -> String {
  case string.ends_with(s, suffix) {
    True -> s
    False -> s <> suffix
  }
}

// ************************************************************
// list utilities
// ************************************************************

pub fn prefix_partition(
  list: List(a),
  condition: fn(a) -> Bool,
) -> #(List(a), List(a)) {
  case list {
    [] -> #([], [])
    [first, ..rest] ->
      case condition(first) {
        False -> #([], list)
        True -> {
          let #(prefix, list) = prefix_partition(rest, condition)
          #([first, ..prefix], list)
        }
      }
  }
}

pub fn suffix_partition(
  l: List(a),
  condition: fn(a) -> Bool,
) -> #(List(a), List(a)) {
  let #(prefix, others) = prefix_partition(l |> list.reverse, condition)
  #(others |> list.reverse, prefix |> list.reverse)
}

pub fn get_duplicate(list: List(a)) -> Option(a) {
  case list {
    [] -> None
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> Some(first)
        False -> get_duplicate(rest)
      }
  }
}

pub fn get_contained(from: List(a), in: List(a)) -> Option(a) {
  case from {
    [] -> None
    [first, ..rest] ->
      case list.contains(in, first) {
        True -> Some(first)
        False -> get_contained(rest, in)
      }
  }
}

/// dumps the contents of 'from' "upside-down" into
/// 'into', so that the first element of 'from' ends
/// up buried inside the resulting list, while the last
/// element of 'from' ends up surfaced as the first
/// element of the result
pub fn pour(from: List(a), into: List(a)) -> List(a) {
  case from {
    [first, ..rest] -> pour(rest, [first, ..into])
    [] -> into
  }
}

pub fn pour_but_last(from: List(a), into: List(a)) -> #(List(a), a) {
  case from {
    [one] -> #(into, one)
    [first, ..rest] -> pour_but_last(rest, [first, ..into])
    [] -> panic as "don't call pour_but_last with an empty first list"
  }
}

pub fn try_map_fold(
  over items: List(q),
  from state: a,
  with f: fn(a, q) -> Result(#(q, a), c),
) -> Result(#(List(q), a), c) {
  case items {
    [] -> Ok(#([], state))
    [first, ..rest] -> {
      use #(mapped_first, state) <- on.ok(f(state, first))
      use #(mapped_rest, state) <- on.ok(try_map_fold(rest, state, f))
      Ok(#([mapped_first, ..mapped_rest], state))
    }
  }
}

pub fn list_set(items: List(a), index: Int, element: a) -> List(a) {
  let assert True = 0 <= index && index < list.length(items)
  let prefix = list.take(items, index)
  let suffix = list.drop(items, index + 1)
  list.append(prefix, [element, ..suffix])
}

pub fn list_string_stringifier(param: List(String)) -> String {
  "["
  <> {
    param
    |> list.index_map(fn(p, i) {
      case i > 0 {
        True -> "\n, "
        False -> " "
      }
      <> p
    })
    |> string.join("")
  }
  <> "\n]"
}

pub fn list_param_stringifier(param: List(p)) -> String {
  param
  |> list.map(ins)
  |> list_string_stringifier
}

pub fn drop_last(z: List(a)) -> List(a) {
  z |> list.reverse |> list.drop(1) |> list.reverse
}

pub fn assert_drop_last(z: List(a)) -> List(a) {
  let assert [_, ..rest] = z |> list.reverse
  rest |> list.reverse
}

pub type SingletonError {
  MoreThanOne
  LessThanOne
}

pub fn read_singleton(z: List(a)) -> Result(a, SingletonError) {
  case z {
    [] -> Error(LessThanOne)
    [one] -> Ok(one)
    _ -> Error(MoreThanOne)
  }
}

pub fn delete(items: List(a), item: a) -> #(Bool, List(a)) {
  case items {
    [] -> #(False, [])
    [first, ..rest] if first == item -> #(True, delete(rest, item).1)
    [first, ..rest] -> {
      let #(b, rest) = delete(rest, item)
      #(b, [first, ..rest])
    }
  }
}

pub fn insert_before_first(list: List(a), elt: a, condition: fn(a) -> Bool) {
  case list {
    [] -> [elt]
    [first, ..rest] ->
      case condition(first) {
        True -> [elt, first, ..rest]
        False -> [first, ..insert_before_first(rest, elt, condition)]
      }
  }
}

pub fn pour_before_first(
  list: List(a),
  to_pour: List(a),
  condition: fn(a) -> Bool,
) {
  case list {
    [] -> to_pour |> list.reverse
    [first, ..rest] ->
      case condition(first) {
        True -> pour(to_pour, [first, ..rest])
        False -> [first, ..pour_before_first(rest, to_pour, condition)]
      }
  }
}

pub fn not_contains(list: List(a), element: a) -> Bool {
  !list.contains(list, element)
}

// ************************************************************
// tuples
// ************************************************************

pub fn quad_to_pair_pair(t: #(a, b, c, d)) -> #(#(a, b), #(c, d)) {
  #(#(t.0, t.1), #(t.2, t.3))
}

pub fn quad_drop_3rd(t: #(a, b, c, d)) -> #(a, b, d) {
  #(t.0, t.1, t.3)
}

pub fn quad_drop_4th(t: #(a, b, c, d)) -> #(a, b, c) {
  #(t.0, t.1, t.2)
}

pub fn triple_3rd(t: #(a, b, c)) -> c {
  t.2
}

pub fn triple_drop_2nd(t: #(a, b, c)) -> #(a, c) {
  #(t.0, t.2)
}

pub fn triple_drop_3rd(t: #(a, b, c)) -> #(a, b) {
  #(t.0, t.1)
}

pub fn triple_to_pair(t: #(a, b, c)) -> #(a, #(b, c)) {
  #(t.0, #(t.1, t.2))
}

pub fn pair_2nd(t: #(a, b)) -> b {
  t.1
}

pub fn quad_to_pair(t: #(a, b, c, d)) -> #(a, #(b, c, d)) {
  #(t.0, #(t.1, t.2, t.3))
}

pub fn quads_to_pair_pairs(
  l: List(#(a, b, c, d)),
) -> List(#(#(a, b), #(c, d))) {
  l
  |> list.map(quad_to_pair_pair)
}

pub fn triples_to_pairs(l: List(#(a, b, c))) -> List(#(a, #(b, c))) {
  l
  |> list.map(triple_to_pair)
}

pub fn quads_to_pairs(l: List(#(a, b, c, d))) -> List(#(a, #(b, c, d))) {
  l
  |> list.map(quad_to_pair)
}

//**************************************************************
//* dictionary-building utilities
//**************************************************************

pub fn validate_unique_keys(
  l: List(#(a, b)),
) -> Result(List(#(a, b)), DesugaringError) {
  case get_duplicate(list.map(l, pair.first)) {
    Some(guy) ->
      Error(DesugaringError(
        bl.no_blame,
        "duplicate key in list being converted to dict: " <> ins(guy),
      ))
    None -> Ok(l)
  }
}

pub fn dict_from_list(l: List(#(a, b))) -> Result(Dict(a, b), DesugaringError) {
  validate_unique_keys(l)
  |> result.map(dict.from_list)
}

pub fn aggregate_on_first(l: List(#(a, b))) -> Dict(a, List(b)) {
  list.fold(l, dict.from_list([]), fn(d, pair) {
    let #(a, b) = pair
    case dict.get(d, a) {
      Error(Nil) -> dict.insert(d, a, [b])
      Ok(prev_list) -> dict.insert(d, a, [b, ..prev_list])
    }
  })
}

pub fn use_list_pair_as_dict(
  list_pairs: List(#(a, b)),
  key: a,
) -> Result(b, Nil) {
  case list_pairs {
    [] -> Error(Nil)
    [#(alice, bob), ..] if alice == key -> Ok(bob)
    [_, ..rest] -> use_list_pair_as_dict(rest, key)
  }
}

fn insert_in_list_pair_as_dict_accumulator(
  previous: List(#(a, b)),
  item: #(a, b),
  remaining: List(#(a, b)),
) -> List(#(a, b)) {
  case remaining {
    [] -> [item, ..previous] |> list.reverse
    [first, ..rest] ->
      case first.0 == item.0 {
        True -> pour([item, ..previous], rest)
        False ->
          insert_in_list_pair_as_dict_accumulator(
            [first, ..previous],
            item,
            rest,
          )
      }
  }
}

pub fn insert_in_list_pair_as_dict(
  list_pairs: List(#(a, b)),
  item: #(a, b),
) -> List(#(a, b)) {
  insert_in_list_pair_as_dict_accumulator([], item, list_pairs)
}

pub fn triples_to_dict(l: List(#(a, b, c))) -> Dict(a, #(b, c)) {
  l
  |> triples_to_pairs
  |> dict.from_list
}

pub fn triples_to_aggregated_dict(
  l: List(#(a, b, c)),
) -> Dict(a, List(#(b, c))) {
  l
  |> triples_to_pairs
  |> aggregate_on_first
}

//**************************************************************
//* find replace
//**************************************************************

fn find_replace_in_line(line: Line, from: String, to: String) -> Line {
  Line(..line, content: line.content |> string.replace(from, to))
}

pub fn t_find_replace(node: VXML, from: String, to: String) -> VXML {
  let assert T(blame, contents) = node
  T(blame, list.map(contents, find_replace_in_line(_, from, to)))
}

pub fn find_replace_if_t(node: VXML, from: String, to: String) -> VXML {
  case node {
    T(..) -> t_find_replace(node, from, to)
    _ -> node
  }
}

fn find_replace_in_line__batch(
  line: Line,
  pairs: List(#(String, String)),
) -> Line {
  list.fold(pairs, line, fn(acc, pair) {
    find_replace_in_line(acc, pair.0, pair.1)
  })
}

pub fn t_find_replace__batch(
  vxml: VXML,
  pairs: List(#(String, String)),
) -> VXML {
  let assert T(blame, lines) = vxml
  T(
    blame,
    lines
      |> list.map(find_replace_in_line__batch(_, pairs)),
  )
}

pub fn find_replace_if_t__batch(
  node: VXML,
  pairs: List(#(String, String)),
) -> VXML {
  case node {
    T(..) -> t_find_replace__batch(node, pairs)
    _ -> node
  }
}

// ************************************************************
// String
// ************************************************************

pub fn drop_ending_slash(path: String) -> String {
  case string.ends_with(path, "/") {
    True -> string.drop_end(path, 1)
    False -> path
  }
}

pub fn kebab_case_to_camel_case(input: String) -> String {
  input
  |> string.split("-")
  |> list.index_map(fn(word, index) {
    case index {
      0 -> word
      _ ->
        case string.to_graphemes(word) {
          [] -> ""
          [first, ..rest] -> string.uppercase(first) <> string.join(rest, "")
        }
    }
  })
  |> string.join("")
}

pub fn normalize_spaces(s: String) -> String {
  s
  |> string.split(" ")
  |> list.filter(fn(x) { !string.is_empty(x) })
  |> string.join(" ")
}

pub fn extract_trim_start(content: String) -> #(String, String) {
  let new_content = string.trim_start(content)
  let num_spaces = string.length(content) - string.length(new_content)
  #(string.repeat(" ", num_spaces), new_content)
}

pub fn extract_trim_end(content: String) -> #(String, String) {
  let new_content = string.trim_end(content)
  let num_spaces = string.length(content) - string.length(new_content)
  #(string.repeat(" ", num_spaces), new_content)
}

// ************************************************************
// lines
// ************************************************************

pub fn lines_map_content(
  lines: List(Line),
  m: fn(String) -> String,
) -> List(Line) {
  lines |> list.map(fn(l) { Line(l.blame, m(l.content)) })
}

pub fn lines_are_whitespace(lines: List(Line)) -> Bool {
  list.all(lines, fn(line) { string.trim(line.content) == "" })
}

pub fn lines_remove_starting_empty_lines(l: List(Line)) -> List(Line) {
  case l {
    [] -> []
    [first, ..rest] ->
      case first.content {
        "" -> lines_remove_starting_empty_lines(rest)
        _ -> l
      }
  }
}

pub fn lines_contain(lines: List(Line), s: String) -> Bool {
  list.any(lines, fn(line) { string.contains(line.content, s) })
}

pub fn lines_first_blame(lines: List(Line)) -> Blame {
  case lines {
    [] -> bl.no_blame
    [first, ..] -> first.blame
  }
}

fn split_lines_internal(
  previous_splits: List(List(Line)),
  current_lines: List(Line),
  remaining: List(Line),
  splitter: String,
) -> List(List(Line)) {
  case remaining {
    [] ->
      [current_lines |> list.reverse, ..previous_splits]
      |> list.reverse
    [first, ..rest] -> {
      case string.split_once(first.content, splitter) {
        Error(_) ->
          split_lines_internal(
            previous_splits,
            [first, ..current_lines],
            rest,
            splitter,
          )
        Ok(#(before, after)) ->
          split_lines_internal(
            [
              [Line(first.blame, before), ..current_lines]
                |> list.reverse,
              ..previous_splits
            ],
            [],
            [Line(first.blame, after), ..rest],
            splitter,
          )
      }
    }
  }
}

pub fn split_lines(lines: List(Line), splitter: String) -> List(List(Line)) {
  split_lines_internal([], [], lines, splitter)
}

pub fn trim_starting_spaces_except_first_line(vxml: VXML) -> VXML {
  let assert T(blame, lines) = vxml
  let assert [first_line, ..rest] = lines
  let updated_rest =
    rest
    |> list.map(fn(line) {
      Line(..line, content: string.trim_start(line.content))
    })

  T(blame, [first_line, ..updated_rest])
}

pub fn trim_ending_spaces_except_last_line(vxml: VXML) -> VXML {
  let assert T(blame, lines) = vxml
  let assert [last_line, ..rest] = lines |> list.reverse()
  let updated_rest =
    rest
    |> list.map(fn(line) {
      Line(..line, content: string.trim_end(line.content))
    })
  T(blame, list.reverse([last_line, ..updated_rest]))
}

pub fn lines_trim_start(lines: List(Line)) -> List(Line) {
  case lines {
    [] -> []
    [first, ..rest] -> {
      case string.first(first.content) {
        Error(_) -> lines_trim_start(rest)
        Ok(" ") ->
          case string.trim_start(first.content) {
            "" -> lines_trim_start(rest)
            nonempty -> [Line(first.blame, nonempty), ..rest]
          }
        _ -> lines
      }
    }
  }
}

pub fn reversed_lines_trim_end(lines: List(Line)) -> List(Line) {
  case lines {
    [] -> []
    [first, ..rest] -> {
      case string.last(first.content) {
        Error(_) -> reversed_lines_trim_end(rest)
        Ok(" ") ->
          case string.trim_end(first.content) {
            "" -> reversed_lines_trim_end(rest)
            nonempty ->
              reversed_lines_trim_end([Line(first.blame, nonempty), ..rest])
          }
        _ -> lines
      }
    }
  }
}

pub fn first_line_starts_with(lines: List(Line), s: String) -> Bool {
  case lines {
    [] -> False
    [Line(_, line), ..] -> string.starts_with(line, s)
  }
}

pub fn first_line_ends_with(lines: List(Line), s: String) -> Bool {
  case lines {
    [] -> False
    [Line(_, line), ..] -> string.ends_with(line, s)
  }
}

pub fn lines_total_chars(lines: List(Line)) -> Int {
  list.fold(lines, 0, fn(total, line) { total + string.length(line.content) })
}

// ************************************************************
// ************************************************************
// last_to_first_concatenation
// ************************************************************

fn lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
  l1: List(Line),
  l2: List(Line),
) -> List(Line) {
  let assert [first1, ..rest1] = l1
  let assert [first2, ..rest2] = l2
  pour(rest1, [Line(first1.blame, first1.content <> first2.content), ..rest2])
}

pub fn last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed(
  list_of_lists: List(List(Line)),
) -> List(Line) {
  case list_of_lists {
    [] ->
      panic as "sorry plz find another way don't like returning empty List(Line)"
    [one] -> one
    [next_to_last, last] ->
      lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
        next_to_last,
        last,
      )
    [first, ..rest] ->
      lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
        first,
        last_to_first_concatenation_in_list_list_of_lines_where_all_but_last_list_are_already_reversed(
          rest,
        ),
      )
  }
}

pub fn t_t_last_to_first_concatenation(node1: VXML, node2: VXML) -> VXML {
  let assert T(blame1, lines1) = node1
  let assert T(_, lines2) = node2
  T(
    blame1,
    lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
      lines1 |> list.reverse,
      lines2,
    ),
  )
}

pub fn last_to_first_concatenation_in_list_list_lines(
  l: List(List(Line)),
) -> List(Line) {
  case l {
    [] ->
      panic as "sorry plz find another way don't like returning empty List(Line)"
    [lines1] -> lines1
    [lines1, lines2] ->
      lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
        lines1 |> list.reverse,
        lines2,
      )
    [lines1, ..rest] ->
      lines_last_to_first_concatenation_where_first_lines_are_already_reversed(
        lines1 |> list.reverse,
        last_to_first_concatenation_in_list_list_lines(rest),
      )
  }
}

fn last_to_first_concatenation_internal(
  remaining: List(VXML),
  already_done: List(VXML),
  current_t: Option(VXML),
) {
  case remaining {
    [] ->
      case current_t {
        None -> already_done |> list.reverse
        Some(t) -> [t, ..already_done] |> list.reverse
      }
    [V(..) as first, ..rest] ->
      case current_t {
        None ->
          last_to_first_concatenation_internal(
            rest,
            [first, ..already_done],
            None,
          )
        Some(t) ->
          last_to_first_concatenation_internal(
            rest,
            [first, t, ..already_done],
            None,
          )
      }
    [T(..) as first, ..rest] ->
      case current_t {
        None ->
          last_to_first_concatenation_internal(rest, already_done, Some(first))
        Some(t) ->
          last_to_first_concatenation_internal(
            rest,
            already_done,
            Some(t_t_last_to_first_concatenation(t, first)),
          )
      }
  }
}

pub fn last_to_first_concatenation(vxmls: List(VXML)) -> List(VXML) {
  last_to_first_concatenation_internal(vxmls, [], None)
}

// ************************************************************
// plain concatenation
// ************************************************************

fn nonempty_list_t_plain_concatenation(nodes: List(VXML)) -> VXML {
  let assert [first, ..] = nodes
  let assert T(blame, _) = first
  let all_lines = {
    nodes
    |> list.map(fn(node) {
      let assert T(_, blamed_lines) = node
      blamed_lines
    })
    |> list.flatten
  }
  T(blame, all_lines)
}

pub fn plain_concatenation_in_list(nodes: List(VXML)) -> List(VXML) {
  nodes
  |> eo.discriminate(is_t)
  |> eo.group_eithers
  |> eo.map_resolve(
    fn(either: List(VXML)) -> VXML {
      nonempty_list_t_plain_concatenation(either)
    },
    fn(or: VXML) -> VXML { or },
  )
}

pub fn delete_singleton_empty_lines_in_list(nodes: List(VXML)) -> List(VXML) {
  list.filter(nodes, fn(node) {
    case node {
      T(_, [Line(_, "")]) -> False
      _ -> True
    }
  })
}

// ************************************************************
// t
// ************************************************************

pub fn is_t_and_text_contains(vxml: VXML, content: String) -> Bool {
  case vxml {
    T(_, lines) -> lines_contain(lines, content)
    _ -> False
  }
}

pub fn total_chars(
  // yeah yeah it's not t-... ...relax a bit...
  vxml: VXML,
) -> Int {
  case vxml {
    T(_, lines) -> lines_total_chars(lines)

    V(_, _, _, children) ->
      list.fold(children, 0, fn(total, child) { total + total_chars(child) })
  }
}

pub fn t_remove_starting_empty_lines(vxml: VXML) -> Option(VXML) {
  let assert T(blame, lines) = vxml
  let lines = lines_remove_starting_empty_lines(lines)
  case lines {
    [] -> None
    _ -> Some(T(blame, lines))
  }
}

pub fn t_remove_ending_empty_lines(vxml: VXML) -> Option(VXML) {
  let assert T(blame, lines) = vxml
  let lines =
    lines_remove_starting_empty_lines(lines |> list.reverse) |> list.reverse
  case lines {
    [] -> None
    _ -> Some(T(blame, lines))
  }
}

pub fn t_trim_start(node: VXML) -> Option(VXML) {
  let assert T(blame, lines) = node
  case lines_trim_start(lines) {
    [] -> None
    lines -> Some(T(blame, lines))
  }
}

pub fn t_trim_end(node: VXML) -> Option(VXML) {
  let assert T(blame, lines) = node
  case reversed_lines_trim_end(lines |> list.reverse) {
    [] -> None
    lines -> Some(T(blame, lines |> list.reverse))
  }
}

pub fn t_extract_starting_spaces(node: VXML) -> #(Option(VXML), VXML) {
  let assert T(blame, lines) = node
  let assert [first, ..rest] = lines
  case extract_trim_start(first.content) {
    #("", _) -> #(None, node)
    #(spaces, not_spaces) -> #(
      Some(T(first.blame, [Line(first.blame, spaces)])),
      T(blame, [Line(first.blame, not_spaces), ..rest]),
    )
  }
}

pub fn t_extract_ending_spaces(node: VXML) -> #(Option(VXML), VXML) {
  let assert T(blame, lines) = node
  let assert [first, ..rest] = lines |> list.reverse
  case extract_trim_end(first.content) {
    #("", _) -> #(None, node)
    #(spaces, not_spaces) -> #(
      Some(T(first.blame, [Line(first.blame, spaces)])),
      T(blame, [Line(first.blame, not_spaces), ..rest] |> list.reverse),
    )
  }
}

pub fn t_start_insert_line(vxml: VXML, line: Line) -> VXML {
  let assert T(blame, lines) = vxml
  T(blame, [line, ..lines])
}

pub fn t_end_insert_line(vxml: VXML, line: Line) -> VXML {
  let assert T(blame, lines) = vxml
  T(blame, list.append(lines, [line]))
}

pub fn t_start_insert_text(vxml: VXML, text: String) -> VXML {
  let assert T(blame, lines) = vxml
  let assert [Line(blame_first, content_first), ..other_lines] = lines
  T(blame, [Line(blame_first, text <> content_first), ..other_lines])
}

pub fn t_end_insert_text(vxml: VXML, text: String) -> VXML {
  let assert T(blame, lines) = vxml
  let assert [Line(blame_last, content_last), ..other_lines] =
    lines |> list.reverse
  T(
    blame,
    [Line(blame_last, content_last <> text), ..other_lines]
      |> list.reverse,
  )
}

/// "word" == "non-whitespace" == empty string if string ends with
/// whitespace
///
/// returns: -> #(everything_before, after_last_space)
fn break_out_last_word(input: String) -> #(String, String) {
  case input |> string.reverse |> string.split_once(" ") {
    Ok(#(yoro, rest)) -> #(
      { " " <> rest } |> string.reverse,
      yoro |> string.reverse,
    )
    _ -> #("", input)
  }
}

/// "word" == "non-whitespace" == empty string if string
/// starts with whitespace
///
/// returns: -> #(before_first_space, everything_afterwards)
pub fn break_out_first_word(input: String) -> #(String, String) {
  case input |> string.split_once(" ") {
    Ok(#(yoro, rest)) -> #(yoro, " " <> rest)
    _ -> #(input, "")
  }
}

/// "word" == "non-whitespace" == empty string if node
/// ends with whitespace
///
/// returns -> #(
///   node leftover with last word taken out,
///   Option(new T(..) containing last word),
/// )
pub fn extract_last_word_from_t_node_if_t(vxml: VXML) -> #(VXML, Option(VXML)) {
  case vxml {
    V(..) -> #(vxml, None)
    T(blame, contents) -> {
      let reversed = contents |> list.reverse
      let assert [last, ..rest] = reversed
      case break_out_last_word(last.content) {
        #(_, "") -> #(vxml, None)
        #(before_last_word, last_word) -> {
          let contents =
            [Line(last.blame, before_last_word), ..rest]
            |> list.reverse
          #(
            T(blame, contents),
            Some(T(last.blame, [Line(last.blame, last_word)])),
          )
        }
      }
    }
  }
}

/// "word" == "non-whitespace" == empty string if node
/// starts with whitespace
///
/// returns -> #(
///   Option(new T(..) containing first word),
///   node leftover with word taken out,
/// )
pub fn extract_first_word_from_t_node_if_t(
  vxml: VXML,
) -> #(Option(VXML), VXML) {
  case vxml {
    V(..) -> #(None, vxml)
    T(blame, contents) -> {
      let assert [first, ..rest] = contents
      case break_out_first_word(first.content) {
        #("", _) -> #(None, vxml)
        #(first_word, after_first_word) -> {
          let contents = [Line(first.blame, after_first_word), ..rest]
          #(
            Some(T(first.blame, [Line(first.blame, first_word)])),
            T(blame, contents),
          )
        }
      }
    }
  }
}

// ************************************************************
// v
// ************************************************************

pub fn v_attrs_constructor(
  blame: Blame,
  tag: String,
  attrs: List(#(String, String)),
) -> VXML {
  let attrs = list.map(attrs, fn(pair) { Attr(blame, pair.0, pair.1) })
  V(blame, tag, attrs, [])
}

pub fn v_set_tag(v: VXML, tag: String) -> VXML {
  let assert V(..) = v
  V(..v, tag: tag)
}

pub fn v_extract_starting_spaces(node: VXML) -> #(Option(VXML), VXML) {
  let assert V(blame, tag, attrs, children) = node
  case children {
    [T(..) as first, ..rest] -> {
      case t_extract_starting_spaces(first) {
        #(None, _) -> #(None, node)
        #(Some(guy), first) -> #(
          Some(guy),
          V(blame, tag, attrs, [first, ..rest]),
        )
      }
    }
    _ -> #(None, node)
  }
}

pub fn v_extract_ending_spaces(node: VXML) -> #(Option(VXML), VXML) {
  let assert V(blame, tag, attrs, children) = node
  case children |> list.reverse {
    [T(..) as first, ..rest] -> {
      case t_extract_ending_spaces(first) {
        #(None, _) -> #(None, node)
        #(Some(guy), first) -> #(
          Some(guy),
          V(blame, tag, attrs, [first, ..rest] |> list.reverse),
        )
      }
    }
    _ -> #(None, node)
  }
}

pub fn v_trim_start(node: VXML) -> VXML {
  let assert V(_, _, _, children) = node
  case children {
    [T(..) as first, ..rest] -> {
      case t_trim_start(first) {
        None -> v_trim_start(V(..node, children: rest))
        Some(guy) -> V(..node, children: [guy, ..rest])
      }
    }
    _ -> node
  }
}

pub fn v_trim_end(node: VXML) -> VXML {
  let assert V(_, _, _, children) = node
  case children |> list.reverse {
    [T(..) as first, ..rest] -> {
      case t_trim_end(first) {
        None -> v_trim_end(V(..node, children: rest |> list.reverse))
        Some(guy) -> V(..node, children: [guy, ..rest] |> list.reverse)
      }
    }
    _ -> node
  }
}

pub fn v_remove_starting_empty_lines(node: VXML) -> VXML {
  let assert V(_, _, _, children) = node
  case children {
    [T(..) as first, ..rest] -> {
      case t_remove_starting_empty_lines(first) {
        None -> v_remove_starting_empty_lines(V(..node, children: rest))
        Some(guy) -> V(..node, children: [guy, ..rest])
      }
    }
    _ -> node
  }
}

pub fn v_remove_ending_empty_lines(node: VXML) -> VXML {
  let assert V(_, _, _, children) = node
  case children |> list.reverse {
    [T(..) as first, ..rest] -> {
      case t_remove_ending_empty_lines(first) {
        None ->
          v_remove_ending_empty_lines(V(..node, children: rest |> list.reverse))
        Some(guy) -> V(..node, children: [guy, ..rest] |> list.reverse)
      }
    }
    _ -> node
  }
}

pub fn v_start_insert_line(vxml: VXML, line: Line) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children {
    [T(..) as first, ..rest] -> [t_start_insert_line(first, line), ..rest]
    _ -> [T(blame, [line]), ..children]
  }
  V(..vxml, children: children)
}

pub fn v_end_insert_line(vxml: VXML, line: Line) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children |> list.reverse {
    [T(..) as first, ..rest] -> [t_end_insert_line(first, line), ..rest]
    _ -> [T(blame, [line]), ..children]
  }
  V(..vxml, children: children |> list.reverse)
}

pub fn v_start_insert_text(vxml: VXML, text: String) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children {
    [T(..) as first, ..rest] -> [t_start_insert_text(first, text), ..rest]
    _ -> [T(blame, [Line(blame, text)]), ..children]
  }
  V(..vxml, children: children)
}

pub fn v_end_insert_text(vxml: VXML, text: String) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children |> list.reverse {
    [T(..) as first, ..rest] -> [t_end_insert_text(first, text), ..rest]
    _ -> [T(blame, [Line(blame, text)]), ..children]
  }
  V(..vxml, children: children |> list.reverse)
}

pub fn v_get_children(vxml: VXML) -> List(VXML) {
  let assert V(_, _, _, children) = vxml
  children
}

pub fn v_get_tag(vxml: VXML) -> String {
  let assert V(_, tag, _, _) = vxml
  tag
}

pub fn v_prepend_attr(vxml: VXML, attr: Attr) -> VXML {
  let assert V(_, _, attrs, _) = vxml
  V(..vxml, attrs: [attr, ..attrs])
}

pub fn v_prepend_unique_key_attr(vxml: VXML, attr: Attr) -> Result(VXML, Nil) {
  case v_has_attr_with_key(vxml, attr.key) {
    True -> Error(Nil)
    False -> Ok(v_prepend_attr(vxml, attr))
  }
}

pub fn v_prepend_child(vxml: VXML, child: VXML) -> VXML {
  let assert V(_, _, _, children) = vxml
  V(..vxml, children: [child, ..children])
}

pub fn append_if_not_present(items: List(a), item: a) -> List(a) {
  case list.contains(items, item) {
    True -> items
    False -> list.append(items, [item])
  }
}

pub fn pour_before_first_in_list(
  nodes: List(VXML),
  to_insert: List(VXML),
  before: String,
) -> List(VXML) {
  pour_before_first(nodes, to_insert, is_v_and_tag_equals(_, before))
}

pub fn insert_child_before_first_in_list(
  nodes: List(VXML),
  child: VXML,
  before: String,
) -> List(VXML) {
  insert_before_first(nodes, child, is_v_and_tag_equals(_, before))
}

pub fn v_pour_before_first(
  vxml: VXML,
  to_insert: List(VXML),
  before: String,
) -> VXML {
  let assert V(_, _, _, children) = vxml
  V(..vxml, children: pour_before_first_in_list(children, to_insert, before))
}

pub fn v_set_attr(vxml: VXML, blame: Blame, key: String, val: String) -> VXML {
  let assert V(_, _, attrs, _) = vxml
  V(..vxml, attrs: attrs_set(attrs, blame, key, val))
}

pub fn v_first_attr_with_key(vxml: VXML, key: String) -> Option(Attr) {
  let assert V(_, _, attrs, _) = vxml
  attrs_first_with_key(attrs, key)
}

pub fn v_val_of_first_attr_with_key(vxml: VXML, key: String) -> Option(String) {
  let assert V(_, _, attrs, _) = vxml
  attrs_val_first_with_key(attrs, key)
}

pub fn v_attrs_with_key(vxml: VXML, key: String) -> List(Attr) {
  let assert V(_, _, attrs, _) = vxml
  attrs |> attrs_with_key(key)
}

pub fn v_has_attr_with_key(vxml: VXML, key: String) -> Bool {
  let assert V(_, _, attrs, _) = vxml
  attrs_have_key(attrs, key)
}

pub fn is_v_and_has_attr_with_key(vxml: VXML, key: String) -> Bool {
  case vxml {
    V(..) -> v_has_attr_with_key(vxml, key)
    _ -> False
  }
}

pub fn v_has_key_val(vxml: VXML, key: String, val: String) -> Bool {
  let assert V(_, _, attrs, _) = vxml
  attrs_have_key_val(attrs, key, val)
}

pub fn v_extract_children(
  vxml: VXML,
  condition: fn(VXML) -> Bool,
) -> #(VXML, List(VXML)) {
  let assert V(_, _, _, children) = vxml
  let #(extracted, left) = list.partition(children, condition)
  #(V(..vxml, children: left), extracted)
}

pub fn v_filter_children(
  vxml: VXML,
  condition: fn(VXML) -> Bool,
) -> List(VXML) {
  let assert V(_, _, _, children) = vxml
  list.filter(children, condition)
}

pub fn v_children_with_tag(vxml: VXML, tag: String) -> List(VXML) {
  v_filter_children(vxml, is_v_and_tag_equals(_, tag))
}

pub fn v_children_with_tags(vxml: VXML, tags: List(String)) -> List(VXML) {
  v_filter_children(vxml, fn(node) {
    tags |> list.any(is_v_and_tag_equals(node, _))
  })
}

pub fn v_children_with_class(vxml: VXML, class: String) -> List(VXML) {
  v_filter_children(vxml, is_v_and_has_class(_, class))
}

pub fn v_tag_is_one_of(vxml: VXML, tags: List(String)) -> Bool {
  let assert V(_, tag, _, _) = vxml
  list.contains(tags, tag)
}

pub fn v_unique_child(
  vxml: VXML,
  tag: String,
) -> Result(VXML, DesugaringError) {
  case v_children_with_tag(vxml, tag) {
    [one] -> Ok(one)
    [] ->
      Error(DesugaringError(vxml.blame, "did not find '" <> tag <> "' element"))
    [_, second, ..] ->
      Error(DesugaringError(
        second.blame,
        "more than one '" <> tag <> "' element",
      ))
  }
}

pub fn v_unique_child_with_singleton_error(
  vxml: VXML,
  tag: String,
) -> Result(VXML, SingletonError) {
  case v_children_with_tag(vxml, tag) {
    [one] -> Ok(one)
    [] -> Error(LessThanOne)
    _ -> Error(MoreThanOne)
  }
}

pub fn first_with_tag(nodes: List(VXML), tag: String) -> Option(VXML) {
  case nodes {
    [V(_, t, _, _) as first, ..] if t == tag -> Some(first)
    [_, ..rest] -> first_with_tag(rest, tag)
    [] -> None
  }
}

pub fn v_first_child_with_tag(vxml: VXML, tag: String) -> Option(VXML) {
  let assert V(_, _, _, children) = vxml
  first_with_tag(children, tag)
}

pub fn v_replace_children_with(vxml: VXML, children: List(VXML)) -> VXML {
  case vxml {
    V(..) -> V(..vxml, children: children)
    _ -> vxml
  }
}

pub fn v_append_classes(node: VXML, classes: String) -> VXML {
  let assert V(blame, _, attrs, _) = node
  V(..node, attrs: attrs_append_classes(attrs, blame, classes))
}

pub fn v_append_classes_if(
  node: VXML,
  classes: String,
  condition: fn(VXML) -> Bool,
) -> VXML {
  case condition(node) {
    True -> v_append_classes(node, classes)
    False -> node
  }
}

pub fn v_assert_pop_attr(vxml: VXML, key: String) -> #(VXML, Attr) {
  let assert V(b, t, a, c) = vxml
  let assert #([unique_guy_with_key], other_guys) =
    list.partition(a, fn(b) { b.key == key })
  #(V(b, t, other_guys, c), unique_guy_with_key)
}

pub fn v_assert_pop_attr_val(vxml: VXML, key: String) -> #(VXML, String) {
  let #(vxml, Attr(_, _, val)) = v_assert_pop_attr(vxml, key)
  #(vxml, val)
}

pub fn v_has_class(vxml: VXML, class: String) -> Bool {
  let assert V(_, _, attrs, _) = vxml
  attrs_have_class(attrs, class)
}

type InfoHTMLPiece {
  Id(blame: Blame, payload: String)
  Class(blame: Blame, payload: String)
  Style(blame: Blame, payload: String)
}

fn split_while(
  s: splitter.Splitter,
  suffix: String,
  blame: Blame,
) -> #(String, List(#(Blame, String, String))) {
  let #(before, sep, after) = splitter.split(s, suffix)
  use _ <- on.stay(case sep {
    "" -> on.Return(#(before, []))
    _ -> on.Stay(Nil)
  })
  let b1 = bl.advance(blame, string.length(before))
  let b2 = bl.advance(b1, string.length(sep))
  let #(u, others) = split_while(s, after, b2)
  #(before, [#(b1, sep, u), ..others])
}

fn info_html_pieces(
  s: splitter.Splitter,
  suffix: String,
  blame: Blame,
) -> #(String, List(InfoHTMLPiece)) {
  let #(tag, pieces) = split_while(s, suffix, blame)
  let pieces =
    list.map(pieces, fn(p) {
      case p {
        #(b, ".", payload) -> {
          case string.contains(payload, ":") {
            True -> Style(b, payload)
            False -> Class(b, payload)
          }
        }
        #(b, "#", payload) -> Id(b, payload)
        _ -> panic
      }
    })
  #(tag, pieces)
}

pub fn html_info_shorthand_to_attrs(
  blame: Blame,
  info: String,
) -> Result(
  #(
    Option(Attr),
    // language
    Option(Attr),
    // id
    Option(Attr),
    // class
    Option(Attr),
    // style
  ),
  String,
) {
  assert info == string.trim(info)
  assert info != ""
  let s = splitter.new([".", "#"])
  let #(language, pieces) = info_html_pieces(s, info, blame)
  let #(ids, classes, styles) =
    list.fold(pieces, #([], [], []), fn(acc, p) {
      case p {
        Id(..) -> #([p, ..acc.0], acc.1, acc.2)
        Class(..) -> #(acc.0, [p, ..acc.1], acc.2)
        Style(..) -> #(acc.0, acc.1, [p, ..acc.2])
      }
    })
  let language = case language {
    "" -> None
    _ -> Some(Attr(blame, "language", language))
  }
  use id <- on.ok(case ids {
    [] -> Ok(None)
    [one] -> Ok(Some(Attr(one.blame, "id", one.payload)))
    _ -> Error("duplicate HTML id (two '#' in 'info' string)")
  })
  let class = case classes {
    [] -> None
    [first, ..] -> {
      let val =
        list.map(classes, fn(d) { d.payload |> string.trim })
        |> list.reverse
        |> string.join(" ")
      Some(Attr(first.blame, "class", val))
    }
  }
  let style = case styles {
    [] -> None
    [first, ..] -> {
      let val =
        list.map(styles, fn(d) { d.payload |> string.trim })
        |> list.reverse
        |> string.join(";")
      Some(Attr(first.blame, "style", val))
    }
  }
  Ok(#(language, id, class, style))
}

// ************************************************************
// constructors, including from_tag & expand_selector_shorthand
// ************************************************************

pub type SelectorError {
  EmptyTag
  InvalidTag
  InvalidKey
}

fn expand_selector_split_while(
  s: splitter.Splitter,
  suffix: String,
) -> #(String, List(#(String, String))) {
  let #(before, delimiter, after) = splitter.split(s, suffix)
  use _ <- on.stay(case delimiter {
    "" -> on.Return(#(before, []))
    _ -> on.Stay(Nil)
  })
  let #(payload, others) = expand_selector_split_while(s, after)
  #(before, [#(delimiter, payload), ..others])
}

pub fn expand_selector_shorthand(
  shorthand: String,
) -> Result(VXML, SelectorError) {
  let s = splitter.new([".", "#", "&"])
  let #(tag, addenda) = expand_selector_split_while(s, shorthand)
  let blame = bl.Ext([], "expand_selector_shorthand")

  use _ <- on.stay(case tag == "" {
    True -> on.Return(Error(EmptyTag))
    False -> on.Stay(Nil)
  })

  use <- on.false_true(valid_tag(tag), fn() { Error(InvalidTag) })

  let addendum_to_attr = fn(addendum: #(String, String)) -> Attr {
    case addendum.0 {
      "." -> Attr(blame, "class", addendum.1)
      "#" -> Attr(blame, "id", addendum.1)
      "&" ->
        case string.split_once(addendum.1, "=") {
          Ok(#(bef, aft)) -> Attr(blame, bef, aft)
          _ -> Attr(blame, addendum.1, "")
        }
      _ -> panic as "unexpected selector shorthand delimiter"
    }
  }

  let attrs =
    list.map(addenda, addendum_to_attr)
    |> merge_attrs

  Ok(V(blame, tag, attrs, []))
}

pub fn from_tag(blame: Blame, tag: String) -> Result(VXML, DesugaringError) {
  case valid_tag(tag) {
    False -> Error(DesugaringError(blame, "invalid VXML tag: '" <> tag <> "'"))
    True -> Ok(V(blame, tag, [], []))
  }
}

// ************************************************************
// attrs
// ************************************************************

pub fn keys(attrs: List(Attr)) -> List(String) {
  attrs |> list.map(fn(attr) { attr.key })
}

pub fn attrs_delete(attrs: List(Attr), key: String) -> List(Attr) {
  attrs |> list.filter(fn(x) { x.key != key })
}

pub fn attrs_have_key(attrs: List(Attr), key: String) -> Bool {
  list.any(attrs, fn(x) { x.key == key })
}

pub fn attrs_have_key_val(attrs: List(Attr), key: String, val: String) -> Bool {
  list.any(attrs, fn(x) { x.key == key && x.val == val })
}

pub fn string_pair_to_attr(pair: #(String, String), blame: Blame) -> Attr {
  Attr(blame, pair.0, pair.1)
}

pub fn string_pairs_to_attrs(
  pairs: List(#(String, String)),
  blame: Blame,
) -> List(Attr) {
  pairs
  |> list.map(string_pair_to_attr(_, blame))
}

pub fn attrs_have_class(attrs: List(Attr), class: String) -> Bool {
  case attrs {
    [] -> False
    [first, ..rest] ->
      case first {
        Attr(_, "class", val) ->
          val
          |> string.split(" ")
          |> list.contains(class)
        _ -> attrs_have_class(rest, class)
      }
  }
}

pub fn attrs_with_key(attrs: List(Attr), key: String) -> List(Attr) {
  list.filter(attrs, fn(x) { x.key == key })
}

pub fn attrs_unique_key_or_none(
  attrs: List(Attr),
  key: String,
) -> Result(Option(Attr), DesugaringError) {
  case attrs_with_key(attrs, key) {
    [one] -> Ok(Some(one))
    [] -> Ok(None)
    [_, second, ..] ->
      Error(DesugaringError(second.blame, "non-unique key: " <> key))
  }
}

pub fn attrs_val_of_unique_key(
  attrs: List(Attr),
  key: String,
  blame: Blame,
) -> Result(String, DesugaringError) {
  case attrs_with_key(attrs, key) {
    [one] -> Ok(one.val)
    [] -> Error(DesugaringError(blame, "missing attr: '" <> key <> "'"))
    [_, second, ..] ->
      Error(DesugaringError(second.blame, "non-unique key: " <> key))
  }
}

pub fn attrs_extract_key_occurrences(
  attrs: List(Attr),
  key: String,
) -> #(List(Attr), List(Attr)) {
  list.partition(attrs, fn(attr) { attr.key == key })
}

pub fn attrs_extract_key_val(
  attrs: List(Attr),
  key: String,
  val: String,
) -> #(List(Attr), List(Attr)) {
  list.partition(attrs, fn(attr) { attr.key == key && attr.val == val })
}

pub fn attrs_extract_first(
  attrs: List(Attr),
  key: String,
) -> #(Option(Attr), List(Attr)) {
  case attrs {
    [Attr(_, attr_key, _) as first, ..more] if attr_key == key -> #(
      Some(first),
      more,
    )
    [first, ..more] -> {
      let #(z, q) = attrs_extract_first(more, key)
      #(z, [first, ..q])
    }
    [] -> #(None, [])
  }
}

pub fn attrs_extract_unique_key_or_none(
  attrs: List(Attr),
  key: String,
) -> Result(#(Option(Attr), List(Attr)), DesugaringError) {
  use #(extracted, remaining) <- on.ok(
    list.try_fold(attrs, #(None, []), fn(acc, attr) {
      case attr.key == key {
        False -> Ok(#(acc.0, [attr, ..acc.1]))
        True ->
          case acc.0 {
            None -> Ok(#(Some(attr), acc.1))
            _ -> Error(DesugaringError(attr.blame, "duplicate key: " <> key))
          }
      }
    }),
  )

  let attrs = case extracted {
    None -> attrs
    _ -> remaining |> list.reverse
  }

  Ok(#(extracted, attrs))
}

pub fn attrs_set(
  attrs: List(Attr),
  blame: Blame,
  key: String,
  val: String,
) -> List(Attr) {
  let #(attrs, found) =
    list.fold(attrs, #([], False), fn(acc, attr) {
      case attr.key == key {
        False -> #([attr, ..acc.0], acc.1)
        True -> {
          case acc.1 {
            True -> {
              let msg =
                "attrs_set found second occurrence of key '" <> key <> "'"
              panic as msg
            }
            False -> #([Attr(..attr, val: val), ..acc.0], True)
          }
        }
      }
    })

  case found {
    True -> attrs |> list.reverse
    False -> [Attr(blame, key, val), ..attrs] |> list.reverse
  }
}

pub fn attrs_first_with_key(attrs: List(Attr), key: String) -> Option(Attr) {
  case list.find(attrs, fn(b) { b.key == key }) {
    Error(Nil) -> None
    Ok(thing) -> Some(thing)
  }
}

pub fn attrs_val_first_with_key(
  attrs: List(Attr),
  key: String,
) -> Option(String) {
  case list.find(attrs, fn(b) { b.key == key }) {
    Error(Nil) -> None
    Ok(thing) -> Some(thing.val)
  }
}

pub fn attrs_val_first_with_key_expected(
  attrs: List(Attr),
  key: String,
  blame: Blame,
) -> Result(String, DesugaringError) {
  case list.find(attrs, fn(b) { b.key == key }) {
    Ok(attr) -> Ok(attr.val)
    _ -> Error(DesugaringError(blame, "expected '" <> key <> "' key"))
  }
}

pub fn replace_attr_val(attr: Attr, from: String, to: String) -> Attr {
  case attr.val == from {
    True -> Attr(..attr, val: to)
    False -> attr
  }
}

pub fn attrs_replace_val(
  attrs: List(Attr),
  from: String,
  to: String,
) -> List(Attr) {
  list.map(attrs, replace_attr_val(_, from, to))
}

// ************************************************************
// validation
// ************************************************************

pub fn valid_tag(tag: String) -> Bool {
  vxml.validate_tag(tag) |> result.is_ok
}

pub fn invalid_tag(tag: String) -> Bool {
  !valid_tag(tag)
}

// ************************************************************
// is_
// ************************************************************

pub fn is_t(node: VXML) -> Bool {
  case node {
    T(..) -> True
    _ -> False
  }
}

pub fn is_v(node: VXML) -> Bool {
  case node {
    V(..) -> True
    _ -> False
  }
}

pub fn is_v_and_tag_equals(vxml: VXML, tag: String) -> Bool {
  case vxml {
    V(_, t, _, _) -> t == tag
    _ -> False
  }
}

pub fn is_v_and_tag_not_equals(vxml: VXML, tag: String) -> Bool {
  case vxml {
    V(_, t, _, _) -> t != tag
    _ -> False
  }
}

pub fn is_v_and_tag_is_one_of(vxml: VXML, tags: List(String)) -> Bool {
  case vxml {
    V(_, t, _, _) -> list.contains(tags, t)
    _ -> False
  }
}

pub fn is_v_and_tag_is_not_one_of(vxml: VXML, tags: List(String)) -> Bool {
  case vxml {
    V(_, t, _, _) -> !list.contains(tags, t)
    _ -> False
  }
}

pub fn is_t_or_is_one_of(node: VXML, tags: List(String)) -> Bool {
  case node {
    V(_, t, _, _) -> list.contains(tags, t)
    _ -> True
  }
}

pub fn is_v_and_has_class(vxml: VXML, class: String) -> Bool {
  case vxml {
    V(_, _, attrs, _) -> attrs_have_class(attrs, class)
    _ -> False
  }
}

pub fn vxml_digest(vxml: VXML) -> String {
  case vxml {
    T(..) -> "T(..)"
    V(_, tag, _, _) -> "V(_, " <> tag <> ", _, _)"
  }
}

// ************************************************************
// style
// ************************************************************

pub fn style_extract_unique_key_or_none(
  style: String,
  key: String,
  blame: Blame,
) -> Result(#(Option(String), String), DesugaringError) {
  let key_vals = assert_split_style(style)

  use #(extracted, remaining) <- on.ok(
    list.try_fold(key_vals, #(None, []), fn(acc, kv) {
      case kv.0 == key {
        False -> Ok(#(acc.0, [kv, ..acc.1]))
        True ->
          case acc.0 {
            None -> Ok(#(Some(kv.1), acc.1))
            _ ->
              Error(DesugaringError(blame, "duplicate style property: " <> key))
          }
      }
    }),
  )

  let style = case extracted {
    None -> style
    _ -> remaining |> list.reverse |> compose_style
  }

  Ok(#(extracted, style))
}

pub fn optional_style_extract_unique_key_or_none(
  style_attr: Option(Attr),
  key: String,
) -> Result(#(Option(String), Option(Attr)), DesugaringError) {
  case style_attr {
    None -> Ok(#(None, None))
    Some(Attr(blame, k, style)) -> {
      assert k == "style"
      use #(val, style) <- on.ok(style_extract_unique_key_or_none(
        style,
        key,
        blame,
      ))
      let style_attr = case style == "" {
        True -> None
        False -> Some(Attr(blame, "style", style))
      }
      Ok(#(val, style_attr))
    }
  }
}

pub fn compose_style(keyvals: List(#(String, String))) -> String {
  list.map(keyvals, fn(kv) { kv.0 <> ":" <> kv.1 })
  |> string.join(";")
}

pub fn assert_split_style(style: String) -> List(#(String, String)) {
  style
  |> string.split(";")
  |> list.map(fn(s) {
    case string.split_once(s, ":") {
      Ok(#(key, val)) -> Some(#(string.trim(key), string.trim(val)))
      _ -> {
        assert string.trim(s) == ""
        None
      }
    }
  })
  |> option.values
}

pub fn merge_styles(a: String, b: String) -> String {
  // *
  // styles of b overwrite styles of a
  // *
  let all_a = a |> assert_split_style
  list.fold(b |> assert_split_style, all_a, insert_in_list_pair_as_dict)
  |> compose_style
}

pub fn attrs_merge_styles(
  attrs: List(Attr),
  blame: Blame,
  styles: String,
) -> List(Attr) {
  let #(index, new_attr) =
    list.index_fold(attrs, #(-1, Attr(blame, "", "")), fn(acc, attr, i) {
      case acc.0, attr.key {
        -1, "style" -> #(i, Attr(..attr, val: merge_styles(attr.val, styles)))
        _, _ -> acc
      }
    })
  case index >= 0 {
    True -> list_set(attrs, index, new_attr)
    False -> list.append(attrs, [Attr(blame, "style", styles)])
  }
}

pub fn attrs_merge_prepend_styles(
  attrs: List(Attr),
  blame: Blame,
  styles: String,
) -> List(Attr) {
  let #(index, new_attr) =
    list.index_fold(attrs, #(-1, Attr(blame, "", "")), fn(acc, attr, i) {
      case acc.0, attr.key {
        -1, "style" -> #(i, Attr(..attr, val: merge_styles(attr.val, styles)))
        _, _ -> acc
      }
    })
  case index >= 0 {
    True -> list_set(attrs, index, new_attr)
    False -> [Attr(blame, "style", styles), ..attrs]
  }
}

// ************************************************************
// class
// ************************************************************

pub fn remove_class(classes: String, class: String) -> String {
  classes
  |> string.split(" ")
  |> list.filter(fn(c) { c != class })
  |> string.join(" ")
}

pub fn merge_classes(a: String, b: String) -> String {
  let all_a = a |> string.split(" ")
  let all_b = b |> string.split(" ")
  list.fold(all_b, all_a |> list.reverse, fn(acc, b) {
    case list.contains(acc, b) {
      True -> acc
      False -> [b, ..acc]
    }
  })
  |> list.reverse
  |> string.join(" ")
}

pub fn attrs_append_classes(
  attrs: List(Attr),
  blame: Blame,
  classes: String,
) -> List(Attr) {
  let #(index, new_attr) =
    list.index_fold(attrs, #(-1, Attr(blame, "", "")), fn(acc, attr, i) {
      case acc.0, attr.key {
        -1, "class" -> #(i, Attr(..attr, val: merge_classes(attr.val, classes)))
        _, _ -> acc
      }
    })
  case index >= 0 {
    True -> list_set(attrs, index, new_attr)
    False -> list.append(attrs, [Attr(blame, "class", classes)])
  }
}

pub fn substitute_in_class_attr(
  attrs: List(Attr),
  from: String,
  to: String,
) -> List(Attr) {
  list.map(attrs, fn(attr) {
    case attr.key == "class" {
      False -> attr
      True ->
        Attr(..attr, val: case string.contains(attr.val, to) {
          True -> remove_class(attr.val, from)
          // if 'to' is already there we just remove the 'from'
          False -> string.replace(attr.val, from, to)
          // ...otherwise we substitute
        })
    }
  })
}

pub fn remove_in_class_attr(
  attrs: List(Attr),
  to_be_removed: String,
) -> List(Attr) {
  list.fold(attrs, [], fn(acc, attr) {
    case attr.key == "class" {
      False -> [attr, ..acc]
      True -> {
        let new_val = remove_class(attr.val, to_be_removed)
        assert new_val == string.trim(new_val)
        case new_val == "" {
          True -> acc
          False -> [Attr(attr.blame, "class", new_val), ..acc]
        }
      }
    }
  })
  |> list.reverse
}

pub fn supplement_in_class_attr(
  attrs: List(Attr),
  if_this_is_there: String,
  then_add: String,
) -> List(Attr) {
  list.map(attrs, fn(attr) {
    case attr.key == "class" {
      False -> attr
      True ->
        Attr(..attr, val: case string.contains(attr.val, if_this_is_there) {
          True ->
            case string.contains(attr.val, then_add) {
              False -> attr.val <> " " <> then_add
              True -> attr.val
            }
          False -> attr.val
        })
    }
  })
}

pub fn merge_attrs(attrs: List(Attr)) -> List(Attr) {
  let acc =
    list.fold(attrs, #(None, None, None, []), fn(acc, attr) {
      case attr.key {
        "id" ->
          case acc.0 {
            None -> #(Some(attr), acc.1, acc.2, acc.3)
            Some(_) -> panic as "two 'id' keys"
          }
        "class" ->
          case acc.1 {
            None -> #(acc.0, Some(attr), acc.2, acc.3)
            Some(guy) -> #(
              acc.0,
              Some(Attr(..guy, val: merge_classes(guy.val, attr.val))),
              acc.2,
              acc.3,
            )
          }
        "style" ->
          case acc.2 {
            None -> #(acc.0, acc.1, Some(attr), acc.3)
            Some(guy) -> #(
              acc.0,
              acc.1,
              Some(Attr(..guy, val: merge_styles(guy.val, attr.val))),
              acc.3,
            )
          }
        _ -> #(acc.0, acc.1, acc.2, [attr, ..acc.3])
      }
    })
  [
    acc.2,
    acc.1,
    acc.0,
  ]
  |> option.values
  |> pour(acc.3 |> list.reverse)
}

// ************************************************************
// iteration
// ************************************************************

pub fn v_map(vxmls: List(VXML), f: fn(VXML) -> VXML) -> List(VXML) {
  list.map(vxmls, fn(vxml) {
    case vxml {
      T(..) -> vxml
      V(..) -> f(vxml)
    }
  })
}

pub fn t_map(vxmls: List(VXML), f: fn(VXML) -> VXML) -> List(VXML) {
  list.map(vxmls, fn(vxml) {
    case vxml {
      T(..) -> f(vxml)
      V(..) -> vxml
    }
  })
}

// ************************************************************
// AssertiveTest zone
// ************************************************************

@internal
pub type AssertiveTest {
  AssertiveTest(
    constructor: fn() -> Desugarer,
    source: String,
    // VXML String
    expected: String,
    // VXML String
  )
}

@internal
pub type AssertiveTestCollection {
  AssertiveTestCollection(
    desugarer_name: String,
    tests: fn() -> List(AssertiveTest),
  )
}

@internal
pub type AssertiveTestDataNoParam {
  AssertiveTestDataNoParam(source: String, expected: String)
}

@internal
pub type AssertiveTestData(a) {
  AssertiveTestData(param: a, source: String, expected: String)
}

@internal
pub type AssertiveTestDataNoParamWithOutside {
  AssertiveTestDataNoParamWithOutside(
    outside: List(String),
    source: String,
    expected: String,
  )
}

@internal
pub type AssertiveTestDataWithOutside(a) {
  AssertiveTestDataWithOutside(
    param: a,
    outside: List(String),
    source: String,
    expected: String,
  )
}

@internal
pub type FirstDifferentLine =
  Int

@internal
pub type AssertiveTestError {
  VXMLParseError(vxml.VXMLParseError)
  VXMLSerializationError(vxml.VXMLSerializationError)
  TestDesugaringError(DesugaringError)
  InequalityError(
    name: String,
    output: VXML,
    expected: VXML,
    where: FirstDifferentLine,
  )
  NonMatchingDesugarerName(String)
}

fn remove_minimum_indent(s: String) -> String {
  let lines =
    s |> string.split("\n") |> list.filter(fn(line) { string.trim(line) != "" })

  let minimum_indent =
    lines
    |> list.map(fn(line) {
      string.length(line) - string.length(string.trim_start(line))
    })
    |> list.sort(int.compare)
    |> list.first
    |> result.unwrap(0)

  lines
  |> list.map(fn(line) { line |> string.drop_start(minimum_indent) })
  |> string.join("\n")
}

@internal
pub fn assertive_test_collection_from_data_no_param(
  name: String,
  datas: List(AssertiveTestDataNoParam),
  constructor: fn() -> Desugarer,
) -> AssertiveTestCollection {
  AssertiveTestCollection(desugarer_name: name, tests: fn() -> List(
    AssertiveTest,
  ) {
    list.map(datas, fn(data) {
      AssertiveTest(
        constructor: constructor,
        source: data.source |> remove_minimum_indent,
        expected: data.expected |> remove_minimum_indent,
      )
    })
  })
}

@internal
pub fn assertive_test_collection_from_data(
  name: String,
  datas: List(AssertiveTestData(a)),
  constructor: fn(a) -> Desugarer,
) -> AssertiveTestCollection {
  AssertiveTestCollection(desugarer_name: name, tests: fn() -> List(
    AssertiveTest,
  ) {
    list.map(datas, fn(data) {
      AssertiveTest(
        constructor: fn() { constructor(data.param) },
        source: data.source |> remove_minimum_indent,
        expected: data.expected |> remove_minimum_indent,
      )
    })
  })
}

@internal
pub fn assertive_test_collection_from_data_no_param_with_outside(
  name: String,
  datas: List(AssertiveTestDataNoParamWithOutside),
  constructor: fn(List(String)) -> Desugarer,
) -> AssertiveTestCollection {
  AssertiveTestCollection(desugarer_name: name, tests: fn() -> List(
    AssertiveTest,
  ) {
    list.map(datas, fn(data) {
      AssertiveTest(
        constructor: fn() { constructor(data.outside) },
        source: data.source |> remove_minimum_indent,
        expected: data.expected |> remove_minimum_indent,
      )
    })
  })
}

@internal
pub fn assertive_test_collection_from_data_with_outside(
  name: String,
  datas: List(AssertiveTestDataWithOutside(a)),
  constructor: fn(a, List(String)) -> Desugarer,
) -> AssertiveTestCollection {
  AssertiveTestCollection(desugarer_name: name, tests: fn() -> List(
    AssertiveTest,
  ) {
    list.map(datas, fn(data) {
      AssertiveTest(
        constructor: fn() { constructor(data.param, data.outside) },
        source: data.source |> remove_minimum_indent,
        expected: data.expected |> remove_minimum_indent,
      )
    })
  })
}

// ************************************************************
// Desugarer types
// ************************************************************

pub type DesugaringError {
  DesugaringError(blame: Blame, message: String)
}

pub type DesugaringWarning {
  DesugaringWarning(blame: Blame, message: String)
}

pub type DesugarerTransform =
  fn(VXML) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError)

/// One named VXML -> VXML transformation step.
pub type Desugarer {
  Desugarer(
    name: String,
    stringified_param: Option(String),
    stringified_outside: Option(String),
    transform: DesugarerTransform,
  )
}

// ************************************************************
// ************************************************************
// Pipeline
// ************************************************************

/// The ordered VXML -> VXML transformation stage, not the full render loop.
pub type Pipeline =
  List(Desugarer)
