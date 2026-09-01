import desugaring/core
import gleam/list
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame} as bl

pub type SplitReplacement {
  Keep
  Discard
  DropLastCharacter
  Tag(String)
  TagWithSegmentAsValue(String, String)
  TagWithSegmentChild(String)
  TagThenText(String, String)
  TextThenTag(String, String)
}

pub type CaptureGroupReplacement {
  CaptureGroupReplacement(pattern: String, replacement: SplitReplacement)
}

pub type RegexpSplitRule {
  RegexpSplitRule(regexp: Regexp, capture_groups: List(CaptureGroupReplacement))
}

pub fn regexp_split_rule_to_string(rule: RegexpSplitRule) -> String {
  rule.capture_groups
  |> list.map(fn(group) {
    ins(group.pattern) <> " -> " <> ins(group.replacement)
  })
  |> core.list_string_stringifier
}

fn replacement_nodes(
  blame: Blame,
  segment: String,
  replacement: SplitReplacement,
) -> List(VXML) {
  case replacement {
    Discard -> []
    Keep -> [
      T(blame, [Line(blame, segment)]),
    ]
    DropLastCharacter -> [
      T(blame, [Line(blame, string.drop_end(segment, 1))]),
    ]
    Tag(tag) -> [
      V(blame, tag, [], []),
    ]
    TagWithSegmentAsValue(tag, key) -> [
      V(blame, tag, [Attr(blame, key, segment)], []),
    ]
    TagWithSegmentChild(tag) -> [
      V(blame, tag, [], [T(blame, [Line(blame, segment)])]),
    ]
    TagThenText(tag, txt) -> [
      V(blame, tag, [], []),
      T(blame, [Line(blame, txt)]),
    ]
    TextThenTag(tag, txt) -> [
      T(blame, [Line(blame, txt)]),
      V(blame, tag, [], []),
    ]
  }
}

type RegexSplitState {
  RegexSplitState(
    blame: Blame,
    remaining_groups: List(CaptureGroupReplacement),
    reversed_nodes: List(VXML),
  )
}

fn regexp_segments_to_nodes(
  blame: Blame,
  segments: List(String),
  rule: RegexpSplitRule,
) -> List(VXML) {
  let capture_group_count = list.length(rule.capture_groups)
  let split_cycle_length = capture_group_count + 1
  let segments = case list.length(segments) % split_cycle_length {
    // Erlang's regexp splitter omits an empty final segment when the match
    // reaches the end of the string. Restore it so every match has the same
    // capture-group layout.
    0 -> list.append(segments, [""])
    1 -> segments
    _ -> panic as "unexpected regexp capture-group layout"
  }

  let reversed =
    list.index_fold(
      segments,
      RegexSplitState(blame, [], []),
      fn(state, segment, index) {
        let RegexSplitState(blame, remaining_groups, reversed_nodes) = state
        let capture_group_index = index % split_cycle_length - 1
        let #(replacement, remaining_groups) = case capture_group_index == -1 {
          True -> #(Keep, rule.capture_groups)
          False -> {
            let assert [group, ..remaining_groups] = remaining_groups
            #(group.replacement, remaining_groups)
          }
        }
        let nodes = replacement_nodes(blame, segment, replacement)
        RegexSplitState(
          blame: bl.advance(blame, string.length(segment)),
          remaining_groups: remaining_groups,
          reversed_nodes: core.pour(nodes, reversed_nodes),
        )
      },
    )
    |> fn(state) { state.reversed_nodes }

  reversed
  |> list.reverse
  |> core.last_to_first_concatenation
}

fn apply_regexp_split_rule_to_line(
  line: Line,
  rule: RegexpSplitRule,
) -> List(VXML) {
  case regexp.split(rule.regexp, line.content) {
    [_] -> [T(line.blame, [line])]
    splits -> regexp_segments_to_nodes(line.blame, splits, rule)
  }
}

// *****************
// Nodemap API
// *****************

pub fn apply_regexp_split_rule(
  vxml: VXML,
  rule: RegexpSplitRule,
) -> List(VXML) {
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) -> {
      lines
      |> list.map(apply_regexp_split_rule_to_line(_, rule))
      |> list.flatten
      |> core.plain_concatenation_in_list
    }
  }
}

fn apply_regexp_split_rule_to_nodes(
  nodes: List(VXML),
  rule: RegexpSplitRule,
) -> List(VXML) {
  nodes
  |> list.map(apply_regexp_split_rule(_, rule))
  |> list.flatten
}

pub fn apply_regexp_split_rules(
  vxml: VXML,
  rules: List(RegexpSplitRule),
) -> List(VXML) {
  list.fold(rules, [vxml], apply_regexp_split_rule_to_nodes)
}

// *****************
// RegexpSplitRule constructor helpers API
// *****************

pub const regex_prefix_to_make_unescaped = "(?<!\\\\)(?:(?:\\\\\\\\)*)"

pub fn unescaped_suffix(suffix: String) -> String {
  regex_prefix_to_make_unescaped <> "(?:" <> suffix <> ")"
}

/// Wraps a regular-expression fragment in a capturing group.
///
/// The fragment must not contain capturing groups of its own. Use
/// noncapturing groups (`(?:...)`) inside the fragment instead.
pub fn parenthesize(s: String) -> String {
  "(" <> s <> ")"
}

/// Constructs a split rule for an unescaped regular-expression suffix.
///
/// `pattern` must not contain capturing groups. Use noncapturing groups
/// (`(?:...)`) inside it instead.
pub fn unescaped_regexp_split_rule(
  pattern pattern: String,
  replacement replacement: SplitReplacement,
) -> RegexpSplitRule {
  // the (even-length) backslash run in front of the delimiter gets its own
  // capture group and is Kept, rather than being swallowed together with the
  // delimiter: that is what lets "\\_" keep its literal backslash while the
  // "_" still counts as a live delimiter
  let assert Ok(re) =
    { parenthesize(regex_prefix_to_make_unescaped) <> parenthesize(pattern) }
    |> regexp.from_string
  RegexpSplitRule(regexp: re, capture_groups: [
    CaptureGroupReplacement(regex_prefix_to_make_unescaped, Keep),
    CaptureGroupReplacement(pattern, replacement),
  ])
}

/// Constructs a single-group regular-expression split rule.
///
/// `pattern` must not contain capturing groups. Use noncapturing groups
/// (`(?:...)`) inside it instead.
pub fn regexp_split_rule(
  pattern pattern: String,
  replacement replacement: SplitReplacement,
) -> RegexpSplitRule {
  let assert Ok(re) = regexp.from_string(pattern |> parenthesize)
  let group = CaptureGroupReplacement(pattern, replacement)
  RegexpSplitRule(regexp: re, capture_groups: [group])
}

/// Constructs a split rule from adjacent capture-group instructions.
///
/// The regular-expression fragment in each pair must not contain capturing
/// groups. Use noncapturing groups (`(?:...)`) inside the fragments instead.
pub fn regexp_split_rule_for_groups(
  pairs: List(#(String, SplitReplacement)),
) -> RegexpSplitRule {
  let pattern =
    list.map(pairs, fn(pair) { parenthesize(pair.0) }) |> string.join("")
  let assert Ok(re) = regexp.from_string(pattern)
  let capture_groups =
    list.map(pairs, fn(pair) { CaptureGroupReplacement(pair.0, pair.1) })
  RegexpSplitRule(regexp: re, capture_groups: capture_groups)
}

// length of the run of backslashes at the very end of a string
fn trailing_backslash_run(s: String) -> Int {
  case string.ends_with(s, "\\") {
    False -> 0
    True ->
      s
      |> string.to_graphemes
      |> list.reverse
      |> list.take_while(fn(grapheme) { grapheme == "\\" })
      |> list.length
  }
}

pub fn remaining_unescaped_splits(
  splits: List(String),
  escaped_splitter_replacement: String,
) -> List(String) {
  case splits {
    [] -> panic
    [_] -> splits
    [first, ..rest] -> {
      // the delimiter is escaped only if the backslash run in front of it
      // has ODD length: "\$" is escaped, but "\\$" is a literal backslash
      // followed by a LIVE delimiter
      case trailing_backslash_run(first) % 2 == 1 {
        False -> [
          first,
          ..remaining_unescaped_splits(rest, escaped_splitter_replacement)
        ]
        True -> {
          let assert [second, ..rest] =
            remaining_unescaped_splits(rest, escaped_splitter_replacement)
          [
            { first |> string.drop_end(1) }
              <> escaped_splitter_replacement
              <> second,
            ..rest
          ]
        }
      }
    }
  }
}

fn naive_unescaped_split_content(
  blame: Blame,
  content: String,
  splitter: String,
  escaped_splitter_replacement: String,
  instruction: SplitReplacement,
) -> List(VXML) {
  let splits =
    string.split(content, splitter)
    |> remaining_unescaped_splits(escaped_splitter_replacement)
    |> list.intersperse(splitter)

  let reversed =
    list.index_fold(splits, #(blame, []), fn(acc, split, index) {
      let #(b, reversed) = acc
      let this_instruction = case index % 2 == 0 {
        True -> Keep
        False -> instruction
      }
      let vxmls = replacement_nodes(b, split, this_instruction)
      let reversed = core.pour(vxmls, reversed)
      let b = bl.advance(b, string.length(split))
      #(b, reversed)
    })
    |> core.pair_2nd

  reversed
  |> list.reverse
  |> core.last_to_first_concatenation
}

fn naive_unescaped_split_line(
  line: Line,
  splitter: String,
  escaped_splitter_replacement: String,
  replacement: SplitReplacement,
) -> List(VXML) {
  case string.contains(line.content, splitter) {
    False -> [T(line.blame, [line])]
    True ->
      naive_unescaped_split_content(
        line.blame,
        line.content,
        splitter,
        escaped_splitter_replacement,
        replacement,
      )
  }
}

// *****************
// naive_unescaped Nodemap API
// *****************

pub fn naive_unescaped_split_node(
  vxml: VXML,
  splitter: String,
  escaped_splitter_replacement: String,
  replacement: SplitReplacement,
) -> List(VXML) {
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) -> {
      lines
      |> list.map(naive_unescaped_split_line(
        _,
        splitter,
        escaped_splitter_replacement,
        replacement,
      ))
      |> list.flatten
      |> core.plain_concatenation_in_list
    }
  }
}
