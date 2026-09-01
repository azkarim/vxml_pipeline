import desugaring/core.{
  type LatexDelimiterPair, type LatexDelimiterSingleton, type Pipeline,
  BackslashClosingParenthesis, BackslashClosingSquareBracket,
  BackslashOpeningParenthesis, BackslashOpeningSquareBracket, BeginAlign,
  BeginAlignStar, BeginEnvironment, DoubleDollarSingleton, EndAlign,
  EndAlignStar, EndEnvironment, SingleDollarSingleton,
}
import desugaring/desugarers as dl
import desugaring/split_replacement as sr
import gleam/list
import gleam/string
import vxml.{type VXML, Attr, V}

// Regex-escape a LaTeX environment name for a split-rule pattern.
// only `*` needs escaping (braces are literal in the regex flavor used here, as
// evidenced by the hand-written align / align* splitters below)
fn regex_escape_environment_name(name: String) -> String {
  string.replace(name, "*", "\\*")
}

type MathKind {
  InlineMath
  DisplayMath
}

// ************************************************************
// math delimiter stuff
// ************************************************************

type LiteralDelimiterSplitData {
  LiteralDelimiterSplitData(
    splitter: String,
    escaped_splitter_replacement: String,
    replacement: sr.SplitReplacement,
    tag: String,
  )
}

type DelimiterPosition {
  SymmetricDelimiter
  OpeningDelimiter
  ClosingDelimiter
}

type DelimiterData {
  DelimiterData(
    literal: String,
    regexp: String,
    tag: String,
    position: DelimiterPosition,
    requires_unescaped_prefix: Bool,
  )
}

fn delimiter_data(delimiter: LatexDelimiterSingleton) -> DelimiterData {
  case delimiter {
    DoubleDollarSingleton ->
      DelimiterData("$$", "\\$\\$", "DoubleDollar", SymmetricDelimiter, True)
    SingleDollarSingleton ->
      DelimiterData("$", "\\$", "SingleDollar", SymmetricDelimiter, True)
    BackslashOpeningParenthesis ->
      DelimiterData("\\(", "\\\\\\(", "LatexOpeningPar", OpeningDelimiter, True)
    BackslashClosingParenthesis ->
      DelimiterData("\\)", "\\\\\\)", "LatexClosingPar", ClosingDelimiter, True)
    BackslashOpeningSquareBracket ->
      DelimiterData("\\[", "\\\\\\[", "LatexOpeningBra", OpeningDelimiter, True)
    BackslashClosingSquareBracket ->
      DelimiterData("\\]", "\\\\\\]", "LatexClosingBra", ClosingDelimiter, True)
    BeginAlign ->
      DelimiterData(
        "\\begin{align}",
        "\\\\begin{align}",
        "BeginAlign",
        OpeningDelimiter,
        False,
      )
    EndAlign ->
      DelimiterData(
        "\\end{align}",
        "\\\\end{align}",
        "EndAlign",
        ClosingDelimiter,
        False,
      )
    BeginAlignStar ->
      DelimiterData(
        "\\begin{align*}",
        "\\\\begin{align\\*}",
        "BeginAlignStar",
        OpeningDelimiter,
        False,
      )
    EndAlignStar ->
      DelimiterData(
        "\\end{align*}",
        "\\\\end{align\\*}",
        "EndAlignStar",
        ClosingDelimiter,
        False,
      )
    BeginEnvironment(name) ->
      DelimiterData(
        "\\begin{" <> name <> "}",
        "\\\\begin{" <> regex_escape_environment_name(name) <> "}",
        "BeginEnv:" <> name,
        OpeningDelimiter,
        False,
      )
    EndEnvironment(name) ->
      DelimiterData(
        "\\end{" <> name <> "}",
        "\\\\end{" <> regex_escape_environment_name(name) <> "}",
        "EndEnv:" <> name,
        ClosingDelimiter,
        False,
      )
  }
}

fn delimiter_replacement(data: DelimiterData) -> sr.SplitReplacement {
  case data.position {
    SymmetricDelimiter -> sr.Tag(data.tag)
    OpeningDelimiter -> sr.TagThenText(data.tag, data.literal)
    ClosingDelimiter -> sr.TextThenTag(data.tag, data.literal)
  }
}

fn literal_delimiter_split_data(
  delimiter: LatexDelimiterSingleton,
) -> LiteralDelimiterSplitData {
  let data = delimiter_data(delimiter)
  LiteralDelimiterSplitData(
    splitter: data.literal,
    escaped_splitter_replacement: "\\" <> data.literal,
    replacement: delimiter_replacement(data),
    tag: data.tag,
  )
}

type RegexpDelimiterSplitData {
  RegexpDelimiterSplitData(
    rule: sr.RegexpSplitRule,
    tag: String,
    delimiter_text: String,
  )
}

fn regexp_delimiter_split_data(
  delimiter: LatexDelimiterSingleton,
) -> RegexpDelimiterSplitData {
  let data = delimiter_data(delimiter)
  let replacement = delimiter_replacement(data)
  let rule = case data.requires_unescaped_prefix {
    True ->
      sr.unescaped_regexp_split_rule(
        pattern: data.regexp,
        replacement: replacement,
      )
    False ->
      sr.regexp_split_rule(pattern: data.regexp, replacement: replacement)
  }
  RegexpDelimiterSplitData(rule, data.tag, data.literal)
}

fn delimiter_pair_pipeline(
  pair: LatexDelimiterPair,
  wrapper: String,
  unbridgeable: List(String),
  forbidden: List(String),
) -> Pipeline {
  let #(opening, closing) = core.opening_and_closing_singletons_for_pair(pair)
  case opening == closing {
    True -> {
      let LiteralDelimiterSplitData(
        splitter,
        escaped_splitter_replacement,
        replacement,
        tag,
      ) = literal_delimiter_split_data(opening)
      [
        dl.naive_unescaped_split_and_replace__outside(
          #(splitter, escaped_splitter_replacement, replacement),
          forbidden,
        ),
        dl.pair(#(tag, tag, wrapper, unbridgeable)),
        dl.fold_into_text(#(tag, splitter)),
      ]
    }
    False -> {
      let RegexpDelimiterSplitData(opening_rule, opening_tag, opening_text) =
        regexp_delimiter_split_data(opening)
      let RegexpDelimiterSplitData(closing_rule, closing_tag, closing_text) =
        regexp_delimiter_split_data(closing)
      [
        dl.regex_split_and_replace__outside(opening_rule, forbidden),
        dl.regex_split_and_replace__outside(closing_rule, forbidden),
        dl.pair(#(opening_tag, closing_tag, wrapper, unbridgeable)),
        dl.fold_into_text(#(opening_tag, opening_text)),
        dl.fold_into_text(#(closing_tag, closing_text)),
      ]
    }
  }
}

fn create_math_or_mathblock_elements(
  parsed: List(LatexDelimiterPair),
  produced: LatexDelimiterPair,
  backup: LatexDelimiterPair,
  kind: MathKind,
  unbridgeable: List(String),
) -> Pipeline {
  let produced = core.opening_and_closing_string_for_pair(produced)
  let backup = core.opening_and_closing_string_for_pair(backup)

  let #(tag, delimiters) = case kind {
    DisplayMath -> #("MathBlock", core.latex_strippable_display_delimiters())
    InlineMath -> #("Math", core.latex_inline_delimiters())
  }

  let strip_existing = [dl.strip_delimiters_inside(#(tag, delimiters))]

  let create_tags =
    parsed
    |> list.map(
      delimiter_pair_pipeline(_, tag, unbridgeable, [
        "Math",
        "MathBlock",
        "pre",
      ]),
    )
    |> list.flatten

  let reinsert = case kind {
    DisplayMath -> [
      dl.trim("MathBlock"),
      dl.insert_on_own_line_start_end(#("MathBlock", produced)),
    ]
    InlineMath -> [
      dl.trim("Math"),
      dl.insert_text_start_end_if_else(
        #("Math", produced, backup, core.descendant_text_does_not_contain(
          _,
          produced.0,
        )),
      ),
    ]
  }

  [
    strip_existing,
    create_tags,
    reinsert,
  ]
  |> list.flatten
}

pub fn create_mathblock_elements(
  parsed: List(LatexDelimiterPair),
  produced: LatexDelimiterPair,
  unbridgeable_tags: List(String),
) -> Pipeline {
  create_math_or_mathblock_elements(
    parsed,
    produced,
    produced,
    DisplayMath,
    unbridgeable_tags,
  )
}

pub fn create_math_elements(
  parsed: List(LatexDelimiterPair),
  produced: LatexDelimiterPair,
  backup: LatexDelimiterPair,
  unbridgeable_tags: List(String),
) -> Pipeline {
  create_math_or_mathblock_elements(
    parsed,
    produced,
    backup,
    InlineMath,
    unbridgeable_tags,
  )
}

// ************************************************************
// generic symmetric & asymmetric delim splitting
// ************************************************************

pub fn symmetric_delimiter_pipeline(
  delimiter_pattern: String,
  delimiter_text: String,
  tag: String,
  forbidden: List(String),
) -> Pipeline {
  let opening_rule =
    sr.regexp_split_rule_for_groups([
      #("[\\s]", sr.Keep),
      #(delimiter_pattern, sr.Tag("OpeningSymmetricDelim")),
      #("[^\\s\\]})]|$", sr.Keep),
    ])

  let opening_or_closing_rule =
    sr.regexp_split_rule_for_groups([
      #("[^\\s]|^", sr.Keep),
      #(
        sr.unescaped_suffix(delimiter_pattern),
        sr.Tag("OpeningOrClosingSymmetricDelim"),
      ),
      #("[^\\s\\]})]|$", sr.Keep),
    ])

  let closing_rule =
    sr.regexp_split_rule_for_groups([
      #("[^\\s\\[{(]|^", sr.Keep),
      #(sr.unescaped_suffix(delimiter_pattern), sr.Tag("ClosingSymmetricDelim")),
      #("[\\s\\]})]", sr.Keep),
    ])

  [
    dl.regex_split_and_replace__outside(opening_or_closing_rule, forbidden),
    dl.regex_split_and_replace__outside(opening_rule, forbidden),
    dl.regex_split_and_replace__outside(closing_rule, forbidden),
    dl.pair_list_list(#(
      ["OpeningSymmetricDelim", "OpeningOrClosingSymmetricDelim"],
      ["ClosingSymmetricDelim", "OpeningOrClosingSymmetricDelim"],
      tag,
    )),
    dl.fold_into_text__batch([
      #("OpeningSymmetricDelim", delimiter_text),
      #("ClosingSymmetricDelim", delimiter_text),
      #("OpeningOrClosingSymmetricDelim", delimiter_text),
    ]),
  ]
}

pub fn asymmetric_delimiter_pipeline(
  opening_pattern: String,
  closing_pattern: String,
  opening_text: String,
  closing_text: String,
  tag: String,
  unbridgeable_tags: List(String),
  forbidden: List(String),
) -> Pipeline {
  let opening_rule =
    sr.regexp_split_rule_for_groups([
      #("[\\s]|^", sr.Keep),
      #(opening_pattern, sr.Tag("OpeningAsymmetricDelim")),
      #("[^\\s]|$", sr.Keep),
    ])

  let closing_rule =
    sr.regexp_split_rule_for_groups([
      #("[^\\s]|^", sr.Keep),
      #(closing_pattern, sr.Tag("ClosingAsymmetricDelim")),
      #("[\\s]|$", sr.Keep),
    ])

  [
    dl.regex_split_and_replace__outside(opening_rule, forbidden),
    dl.regex_split_and_replace__outside(closing_rule, forbidden),
    dl.pair(#(
      "OpeningAsymmetricDelim",
      "ClosingAsymmetricDelim",
      tag,
      unbridgeable_tags,
    )),
    dl.fold_into_text(#("OpeningAsymmetricDelim", opening_text)),
    dl.fold_into_text(#("ClosingAsymmetricDelim", closing_text)),
  ]
}

// ************************************************************
// permissive symmetric delimiter splitting
// ************************************************************

pub fn permissive_symmetric_delimiter_pipeline(
  delimiter_pattern: String,
  delimiter_text: String,
  tag: String,
  unbridgeable_tags: List(String),
  forbidden: List(String),
) -> Pipeline {
  let opening_or_closing_rule =
    sr.unescaped_regexp_split_rule(
      pattern: delimiter_pattern,
      replacement: sr.Tag("OpeningOrClosingSymmetricDelim"),
    )
  [
    dl.regex_split_and_replace__outside(opening_or_closing_rule, forbidden),
    dl.pair(#(
      "OpeningOrClosingSymmetricDelim",
      "OpeningOrClosingSymmetricDelim",
      tag,
      unbridgeable_tags,
    )),
    dl.fold_into_text(#("OpeningOrClosingSymmetricDelim", delimiter_text)),
  ]
}

// ************************************************************
// annotated backticks
// ************************************************************

pub fn annotated_backtick_pipeline(
  tag: String,
  annotation_key: String,
  unbridgeable_tags: List(String),
  forbidden: List(String),
) -> Pipeline {
  let text_folder = fn(v: VXML) -> String {
    let assert V(_, _, [Attr(_, z, value)], _) = v
    assert z == annotation_key
    "`{" <> value <> "}"
  }
  let start_tag = "AnnotatedBackticksOpening"
  let end_tag = "AnnotatedBackticksClosing"
  let start_splitter = sr.unescaped_regexp_split_rule("`", sr.Tag(start_tag))
  let end_splitter =
    sr.regexp_split_rule_for_groups([
      #("`{", sr.Discard),
      #(
        "[a-zA-Z0-9\\-\\.#_]*",
        sr.TagWithSegmentAsValue(end_tag, annotation_key),
      ),
      #("}", sr.Discard),
    ])
  [
    [
      dl.regex_split_and_replace__outside(end_splitter, forbidden),
      dl.regex_split_and_replace__outside(start_splitter, forbidden),
      dl.pair(#(start_tag, end_tag, "AnnotatedBackticks", unbridgeable_tags)),
      dl.fold_into_text(#("AnnotatedBackticksOpening", "`")),
      dl.fold_custom_into_text(#("AnnotatedBackticksClosing", text_folder)),
    ],
    case tag == "AnnotatedBackticks" {
      True -> []
      False -> [dl.rename(#("AnnotatedBackticks", tag))]
    },
  ]
  |> list.flatten
}

// ************************************************************
// markdown-style links
// ************************************************************

pub fn markdown_link_pipeline(
  unbridgeable_tags: List(String),
  forbidden: List(String),
) -> Pipeline {
  let text_folder = fn(v: VXML) -> String {
    let assert V(_, _, [Attr(_, "href", value)], _) = v
    "]\\(" <> value <> "\\)"
  }
  let start_tag = "MDLinkOpening"
  let end_tag = "MDLinkClosing"
  let start_splitter = sr.unescaped_regexp_split_rule("\\[", sr.Tag(start_tag))
  [
    dl.markdown_link_closing_handrolled_splitter__outside(end_tag, forbidden),
    dl.regex_split_and_replace__outside(start_splitter, forbidden),
    dl.pair(#(start_tag, end_tag, "MDLink", unbridgeable_tags)),
    dl.fold_into_text(#("MDLinkOpening", "[")),
    dl.fold_custom_into_text(#("MDLinkClosing", text_folder)),
    dl.rename(#("MDLink", "a")),
  ]
}

// ************************************************************
// clean up after splitting
// ************************************************************

pub fn split_replacement_cleanup() -> Pipeline {
  [
    dl.concatenate_text_nodes(),
    dl.delete_text_nodes_with_singleton_empty_line(),
  ]
}
