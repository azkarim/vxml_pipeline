//// Pipeline fragments for converting delimited text into VXML elements.
////
//// Each function returns a `Pipeline` that can be inserted into an application
//// pipeline. The `outside` argument follows the package's `__outside`
//// convention: delimiters inside subtrees whose tags occur in that list are
//// left untouched. `unbridgeable` prevents an opening delimiter from pairing
//// with a closing delimiter across an intervening element whose tag occurs in
//// that list.
////
//// Delimiters are normally not paired across paragraph boundaries. Before
//// paragraphs have been wrapped in their own elements, those boundaries should
//// therefore be represented by explicit elements and included in
//// `unbridgeable`. Writerly-derived pipelines typically operate on VXML of
//// this form:
////
//// ```vxml
//// <> root
////   <>
////     'first paragraph with _an opening delimiter'
////   <> WriterlyBlankLine
////   <>
////     'second paragraph with a closing delimiter_'
//// ```
////
//// With `"WriterlyBlankLine"` included in `unbridgeable`, the two
//// underscores cannot form a pair. Distinct paragraphs should not instead be
//// represented as adjacent sibling text nodes: no element would then exist for
//// the pairing machinery to recognize as a boundary. Once paragraphs have
//// been wrapped in separate elements, their parent-child structure provides
//// the boundary and the explicit blank-line elements may be removed.

import gleam/list
import gleam/string
import vxml.{type VXML, Attr, V}
import vxml_pipeline/core.{
  type LatexDelimiterPair, type LatexDelimiterSingleton, type Pipeline,
  BackslashClosingParenthesis, BackslashClosingSquareBracket,
  BackslashOpeningParenthesis, BackslashOpeningSquareBracket, BeginAlign,
  BeginAlignStar, BeginEnvironment, DoubleDollarSingleton, EndAlign,
  EndAlignStar, EndEnvironment, SingleDollarSingleton,
}
import vxml_pipeline/desugarers as dl
import vxml_pipeline/split_replacement as sr

// Regex-escape a LaTeX environment name for a split-rule pattern.
// Only `*` needs escaping in a name. The braces around it are escaped by the
// callers: Erlang's PCRE reads a bare `{` as a literal, but JavaScript's
// unicode-mode regexes reject it.
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
        "\\\\begin\\{align\\}",
        "BeginAlign",
        OpeningDelimiter,
        False,
      )
    EndAlign ->
      DelimiterData(
        "\\end{align}",
        "\\\\end\\{align\\}",
        "EndAlign",
        ClosingDelimiter,
        False,
      )
    BeginAlignStar ->
      DelimiterData(
        "\\begin{align*}",
        "\\\\begin\\{align\\*\\}",
        "BeginAlignStar",
        OpeningDelimiter,
        False,
      )
    EndAlignStar ->
      DelimiterData(
        "\\end{align*}",
        "\\\\end\\{align\\*\\}",
        "EndAlignStar",
        ClosingDelimiter,
        False,
      )
    BeginEnvironment(name) ->
      DelimiterData(
        "\\begin{" <> name <> "}",
        "\\\\begin\\{" <> regex_escape_environment_name(name) <> "\\}",
        "BeginEnv:" <> name,
        OpeningDelimiter,
        False,
      )
    EndEnvironment(name) ->
      DelimiterData(
        "\\end{" <> name <> "}",
        "\\\\end\\{" <> regex_escape_environment_name(name) <> "\\}",
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
  outside: List(String),
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
          outside,
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
        dl.regex_split_and_replace__outside(opening_rule, outside),
        dl.regex_split_and_replace__outside(closing_rule, outside),
        dl.pair(#(opening_tag, closing_tag, wrapper, unbridgeable)),
        dl.fold_into_text(#(opening_tag, opening_text)),
        dl.fold_into_text(#(closing_tag, closing_text)),
      ]
    }
  }
}

fn math_pipeline(
  recognized_delimiters: List(LatexDelimiterPair),
  output_delimiter: LatexDelimiterPair,
  fallback_output_delimiter: LatexDelimiterPair,
  kind: MathKind,
  unbridgeable: List(String),
  outside: List(String),
) -> Pipeline {
  let output_delimiter =
    core.opening_and_closing_string_for_pair(output_delimiter)
  let fallback_output_delimiter =
    core.opening_and_closing_string_for_pair(fallback_output_delimiter)

  let #(tag, delimiters) = case kind {
    DisplayMath -> #("MathBlock", core.latex_strippable_display_delimiters())
    InlineMath -> #("Math", core.latex_inline_delimiters())
  }

  let create_tags =
    recognized_delimiters
    |> list.map(
      delimiter_pair_pipeline(_, tag, unbridgeable, [
        "Math",
        "MathBlock",
        ..outside
      ]),
    )
    |> list.flatten

  // Strip after parsing so this applies both to Math/MathBlock nodes already
  // present in the input and to nodes created from delimiters just above.
  // Environment delimiters are intentionally absent from `delimiters` and
  // therefore remain available to MathJax inside the produced display pair.
  let strip_delimiters = [dl.strip_delimiters_inside(#(tag, delimiters))]

  let reinsert = case kind {
    DisplayMath -> [
      dl.trim("MathBlock"),
      dl.insert_on_own_line_start_end(#("MathBlock", output_delimiter)),
    ]
    InlineMath -> [
      dl.trim("Math"),
      dl.insert_text_start_end_if_else(
        #(
          "Math",
          output_delimiter,
          fallback_output_delimiter,
          core.descendant_text_does_not_contain(_, output_delimiter.0),
        ),
      ),
    ]
  }

  [
    create_tags,
    strip_delimiters,
    reinsert,
  ]
  |> list.flatten
}

/// Returns a pipeline that converts the recognized LaTeX display delimiters
/// into `MathBlock` elements.
///
/// Existing and newly created `MathBlock` elements have recognized delimiters
/// removed, their contents trimmed, and `output_delimiter` inserted on its own
/// opening and closing lines. Delimiters belonging to named LaTeX environments
/// remain inside the resulting `MathBlock` for MathJax to interpret.
pub fn math_block_pipeline(
  recognized_delimiters: List(LatexDelimiterPair),
  output_delimiter: LatexDelimiterPair,
  unbridgeable: List(String),
  outside: List(String),
) -> Pipeline {
  math_pipeline(
    recognized_delimiters,
    output_delimiter,
    output_delimiter,
    DisplayMath,
    unbridgeable,
    outside,
  )
}

/// Returns a pipeline that converts the recognized LaTeX inline delimiters
/// into `Math` elements.
///
/// Existing and newly created `Math` elements have recognized delimiters
/// removed and their contents trimmed. They are wrapped in `output_delimiter`
/// unless that delimiter already occurs in their text, in which case
/// `fallback_output_delimiter` is used.
pub fn inline_math_pipeline(
  recognized_delimiters: List(LatexDelimiterPair),
  output_delimiter: LatexDelimiterPair,
  fallback_output_delimiter: LatexDelimiterPair,
  unbridgeable: List(String),
  outside: List(String),
) -> Pipeline {
  math_pipeline(
    recognized_delimiters,
    output_delimiter,
    fallback_output_delimiter,
    InlineMath,
    unbridgeable,
    outside,
  )
}

// ************************************************************
// generic symmetric & asymmetric delim splitting
// ************************************************************

/// Returns a boundary-aware pipeline for symmetric inline delimiters.
///
/// `delimiter_pattern` is a regular-expression pattern. Opening and closing
/// occurrences are classified using their neighboring whitespace and
/// punctuation. Paired occurrences become an element named `output_tag`;
/// unmatched occurrences are restored as `delimiter_text`.
pub fn boundary_aware_symmetric_delimiter_pipeline(
  delimiter_pattern: String,
  delimiter_text: String,
  output_tag: String,
  outside: List(String),
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
    dl.regex_split_and_replace__outside(opening_or_closing_rule, outside),
    dl.regex_split_and_replace__outside(opening_rule, outside),
    dl.regex_split_and_replace__outside(closing_rule, outside),
    dl.pair_list_list(#(
      ["OpeningSymmetricDelim", "OpeningOrClosingSymmetricDelim"],
      ["ClosingSymmetricDelim", "OpeningOrClosingSymmetricDelim"],
      output_tag,
    )),
    dl.fold_into_text__batch([
      #("OpeningSymmetricDelim", delimiter_text),
      #("ClosingSymmetricDelim", delimiter_text),
      #("OpeningOrClosingSymmetricDelim", delimiter_text),
    ]),
  ]
}

/// Returns a boundary-aware pipeline for distinct opening and closing
/// delimiters.
///
/// `opening_pattern` and `closing_pattern` are regular-expression patterns.
/// Matched pairs become elements named `output_tag`; unmatched delimiter
/// elements are restored as `opening_text` and `closing_text`.
pub fn asymmetric_delimiter_pipeline(
  opening_pattern: String,
  closing_pattern: String,
  opening_text: String,
  closing_text: String,
  output_tag: String,
  unbridgeable: List(String),
  outside: List(String),
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
    dl.regex_split_and_replace__outside(opening_rule, outside),
    dl.regex_split_and_replace__outside(closing_rule, outside),
    dl.pair(#(
      "OpeningAsymmetricDelim",
      "ClosingAsymmetricDelim",
      output_tag,
      unbridgeable,
    )),
    dl.fold_into_text(#("OpeningAsymmetricDelim", opening_text)),
    dl.fold_into_text(#("ClosingAsymmetricDelim", closing_text)),
  ]
}

// ************************************************************
// permissive symmetric delimiter splitting
// ************************************************************

/// Returns a pipeline that treats every unescaped match of a symmetric
/// delimiter as a possible opening or closing delimiter.
///
/// Unlike `boundary_aware_symmetric_delimiter_pipeline`, this function imposes
/// no neighboring whitespace or punctuation rules. `delimiter_pattern` is a
/// regular-expression pattern. Paired occurrences become an element named
/// `output_tag`; unmatched occurrences are restored as `delimiter_text`.
pub fn permissive_symmetric_delimiter_pipeline(
  delimiter_pattern: String,
  delimiter_text: String,
  output_tag: String,
  unbridgeable: List(String),
  outside: List(String),
) -> Pipeline {
  let opening_or_closing_rule =
    sr.unescaped_regexp_split_rule(
      pattern: delimiter_pattern,
      replacement: sr.Tag("OpeningOrClosingSymmetricDelim"),
    )
  [
    dl.regex_split_and_replace__outside(opening_or_closing_rule, outside),
    dl.pair(#(
      "OpeningOrClosingSymmetricDelim",
      "OpeningOrClosingSymmetricDelim",
      output_tag,
      unbridgeable,
    )),
    dl.fold_into_text(#("OpeningOrClosingSymmetricDelim", delimiter_text)),
  ]
}

// ************************************************************
// annotated backticks
// ************************************************************

/// Returns a pipeline that converts annotated backtick spans into VXML
/// elements.
///
/// For example, with `output_tag` set to `"span"` and `annotation_key` set to
/// `"class"`, `` `marked`{manual-color} `` becomes a `span` whose `class`
/// attribute is `manual-color` and whose text is `marked`. Unpaired syntax is
/// restored as text.
pub fn annotated_backtick_pipeline(
  output_tag: String,
  annotation_key: String,
  unbridgeable: List(String),
  outside: List(String),
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
      #("`\\{", sr.Discard),
      #(
        "[a-zA-Z0-9\\-\\.#_]*",
        sr.TagWithSegmentAsValue(end_tag, annotation_key),
      ),
      #("\\}", sr.Discard),
    ])
  [
    [
      dl.regex_split_and_replace__outside(end_splitter, outside),
      dl.regex_split_and_replace__outside(start_splitter, outside),
      dl.pair(#(start_tag, end_tag, "AnnotatedBackticks", unbridgeable)),
      dl.fold_into_text(#("AnnotatedBackticksOpening", "`")),
      dl.fold_custom_into_text(#("AnnotatedBackticksClosing", text_folder)),
    ],
    case output_tag == "AnnotatedBackticks" {
      True -> []
      False -> [dl.rename(#("AnnotatedBackticks", output_tag))]
    },
  ]
  |> list.flatten
}

// ************************************************************
// markdown-style links
// ************************************************************

/// Returns a pipeline that converts Markdown-style `[text](target)` links into
/// `a` elements having `target` as their `href` attribute.
///
/// Unmatched opening and closing syntax is restored as text.
pub fn markdown_link_pipeline(
  unbridgeable: List(String),
  outside: List(String),
) -> Pipeline {
  let text_folder = fn(v: VXML) -> String {
    let assert V(_, _, [Attr(_, "href", value)], _) = v
    "]\\(" <> value <> "\\)"
  }
  let start_tag = "MDLinkOpening"
  let end_tag = "MDLinkClosing"
  let start_splitter = sr.unescaped_regexp_split_rule("\\[", sr.Tag(start_tag))
  [
    dl.markdown_link_closing_handrolled_splitter__outside(end_tag, outside),
    dl.regex_split_and_replace__outside(start_splitter, outside),
    dl.pair(#(start_tag, end_tag, "MDLink", unbridgeable)),
    dl.fold_into_text(#("MDLinkOpening", "[")),
    dl.fold_custom_into_text(#("MDLinkClosing", text_folder)),
    dl.rename(#("MDLink", "a")),
  ]
}

// ************************************************************
// clean up after splitting
// ************************************************************

/// Returns a cleanup pipeline for use after one or more delimiter pipelines.
///
/// Delimiter recognition splits text around every recognized delimiter. Once
/// the temporary delimiter elements have been paired and folded, empty text
/// nodes can remain at the boundaries between generated elements. For example,
/// running italic, bold, and Markdown-link pipelines over:
///
/// ```text
/// _one_*two*[three](target) tail _
/// ```
///
/// produces the following intermediate VXML. The final unmatched underscore is
/// ordinary text, while the empty text nodes are splitting artifacts:
///
/// ```vxml
/// <> root
///   <>
///     ''
///   <> i
///     <>
///       'one'
///   <>
///     ''
///   <> b
///     <>
///       'two'
///   <>
///     ''
///   <> a
///     href=target
///     <>
///       'three'
///   <>
///     ' tail _'
/// ```
///
/// This cleanup pipeline concatenates adjacent text nodes and removes text
/// nodes containing exactly one empty line. The result is:
///
/// ```vxml
/// <> root
///   <> i
///     <>
///       'one'
///   <> b
///     <>
///       'two'
///   <> a
///     href=target
///     <>
///       'three'
///   <>
///     ' tail _'
/// ```
///
/// Cleanup can run once after a consecutive group of delimiter pipelines; it
/// does not need to follow each one individually. As described in the module
/// documentation, significant text boundaries must still be represented by
/// intervening elements or by separate parent elements. Otherwise,
/// concatenating adjacent text nodes could erase a boundary that exists only in
/// the caller's interpretation of the tree.
pub fn delimiter_cleanup_pipeline() -> Pipeline {
  [
    dl.concatenate_text_nodes(),
    dl.delete_text_nodes_with_singleton_empty_line(),
  ]
}
