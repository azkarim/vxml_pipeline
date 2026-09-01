import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import splitter.{type Splitter}
import vxml.{type VXML, Attr, T, V}
import vxml/blame.{type Blame} as bl

pub const name = "tokenize_href_surroundings"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Tokenizes text surrounding href targets so later link
/// rewrites can operate safely.
pub fn constructor() -> Desugarer {
  let assert Ok(inner) = param_to_inner_param(Nil)
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(inner),
  )
}

const had_href_child = Attr(bl.Des([], name, 28), "had_href_child", "true")

fn param_to_inner_param(_param: Param) -> Result(InnerParam, DesugaringError) {
  let opening_parenthesis_splitter: Splitter =
    splitter.new([" ", "(", "[", "—"])
  Ok(opening_parenthesis_splitter)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = fn(vxml) { nodemap(inner, vxml) }
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(opening_parenthesis_splitter: Splitter, vxml: VXML) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, attrs, children) -> {
      case list.any(children, core.is_v_and_has_attr_with_key(_, "href")) {
        False -> vxml
        True -> {
          let attrs = [had_href_child, ..attrs]
          let children =
            list.flat_map(children, fn(vxml) {
              tokenize_if_t_or_has_href_attr_and_recurse(
                opening_parenthesis_splitter,
                vxml,
              )
            })
          V(..vxml, attrs: attrs, children: children)
        }
      }
    }
  }
}

fn tokenize_if_t_or_has_href_attr_and_recurse(
  opening_parenthesis_splitter: Splitter,
  vxml: VXML,
) -> List(VXML) {
  case vxml {
    T(_, _) -> tokenize_t(opening_parenthesis_splitter, vxml)
    V(_, _, attrs, children) ->
      case core.attrs_have_key(attrs, "href") {
        True -> [
          V(
            ..vxml,
            children: list.flat_map(children, fn(vxml) {
              tokenize_if_t_or_has_href_attr_and_recurse(
                opening_parenthesis_splitter,
                vxml,
              )
            }),
          ),
        ]
        False -> [vxml]
      }
  }
}

fn tokenize_t(
  opening_parenthesis_splitter: Splitter,
  vxml: VXML,
) -> List(VXML) {
  let assert T(blame, lines) = vxml
  lines
  |> list.index_map(fn(line, i) {
    tokenize_string_acc(
      opening_parenthesis_splitter,
      [],
      line.blame,
      line.content,
    )
    |> list.prepend(case i == 0 {
      True -> start_node(line.blame)
      False -> newline_node(line.blame)
    })
  })
  |> list.flatten
  |> list.append([end_node(blame)])
}

fn tokenize_string_acc(
  opening_parenthesis_splitter: Splitter,
  past_tokens: List(VXML),
  current_blame: Blame,
  leftover: String,
) -> List(VXML) {
  case splitter.split(opening_parenthesis_splitter, leftover) {
    #(_, "", _) ->
      case leftover == "" {
        True -> past_tokens |> list.reverse
        False ->
          [word_node(current_blame, leftover), ..past_tokens] |> list.reverse
      }
    #("", " ", after) ->
      tokenize_string_acc(
        opening_parenthesis_splitter,
        [space_node(current_blame), ..past_tokens],
        bl.advance(current_blame, 1),
        after,
      )
    #(before, " ", after) ->
      tokenize_string_acc(
        opening_parenthesis_splitter,
        [
          space_node(current_blame),
          word_node(current_blame, before),
          ..past_tokens
        ],
        bl.advance(current_blame, string.length(before) + 1),
        after,
      )
    #("", non_space_puncutation, after) -> {
      tokenize_string_acc(
        opening_parenthesis_splitter,
        [word_node(current_blame, non_space_puncutation), ..past_tokens],
        bl.advance(current_blame, 1),
        after,
      )
    }
    #(before, non_space_punctuation, after) ->
      tokenize_string_acc(
        opening_parenthesis_splitter,
        [
          word_node(current_blame, before),
          word_node(current_blame, non_space_punctuation),
          ..past_tokens
        ],
        bl.advance(current_blame, string.length(before) + 1),
        after,
      )
  }
}

fn word_node(blame: Blame, word: String) {
  V(blame, "__OneWord", [Attr(blame, "val", word)], [])
}

fn space_node(blame: Blame) {
  V(blame, "__OneSpace", [], [])
}

fn start_node(blame: Blame) {
  V(blame, "__StartTokenizedT", [], [])
}

fn newline_node(blame: Blame) {
  V(blame, "__OneNewLine", [], [])
}

fn end_node(blame: Blame) {
  V(blame, "__EndTokenizedT", [], [])
}

type Param =
  Nil

type InnerParam =
  Splitter

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    testing.data_no_param(
      source: "
            <> testing
              <> zz
                href=bla
                <>
                  'first line'
                  'second line'
                <>
                  'third line'

                <> inside
                  <>
                    'some text'
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=bla
                <> __StartTokenizedT
                <> __OneWord
                  val=first
                <> __OneSpace
                <> __OneWord
                  val=line
                <> __OneNewLine
                <> __OneWord
                  val=second
                <> __OneSpace
                <> __OneWord
                  val=line
                <> __EndTokenizedT
                <> __StartTokenizedT
                <> __OneWord
                  val=third
                <> __OneSpace
                <> __OneWord
                  val=line
                <> __EndTokenizedT
                <> inside
                  <>
                    'some text'
      ",
    ),
    testing.data_no_param(
      source: "
            <> testing
              <> zz
                href=true
                <>
                  'first  line'
                  'second  '
                  '   line'
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=true
                <> __StartTokenizedT
                <> __OneWord
                  val=first
                <> __OneSpace
                <> __OneSpace
                <> __OneWord
                  val=line
                <> __OneNewLine
                <> __OneWord
                  val=second
                <> __OneSpace
                <> __OneSpace
                <> __OneNewLine
                <> __OneSpace
                <> __OneSpace
                <> __OneSpace
                <> __OneWord
                  val=line
                <> __EndTokenizedT
      ",
    ),
    testing.data_no_param(
      source: "
            <> testing
              <> zz
                href=cx
                <>
                  '(Note'
                  ''
                  'third line'
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=cx
                <> __StartTokenizedT
                <> __OneWord
                  val=(
                <> __OneWord
                  val=Note
                <> __OneNewLine
                <> __OneNewLine
                <> __OneWord
                  val=third
                <> __OneSpace
                <> __OneWord
                  val=line
                <> __EndTokenizedT
      ",
    ),
    testing.data_no_param(
      source: "
            <> testing
              <> zz
                href=cx
                <>
                  '[Note'
                  ''
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=cx
                <> __StartTokenizedT
                <> __OneWord
                  val=[
                <> __OneWord
                  val=Note
                <> __OneNewLine
                <> __EndTokenizedT
      ",
    ),
    testing.data_no_param(
      source: "
            <> testing
              <> zz
                href=cx
                <>
                  '—Note'
                  ''
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=cx
                <> __StartTokenizedT
                <> __OneWord
                  val=—
                <> __OneWord
                  val=Note
                <> __OneNewLine
                <> __EndTokenizedT
      ",
    ),
    testing.data_no_param(
      source: "
            <> testing
              <> zz
                href=cx
                <>
                  ''
                  ''
      ",
      expected: "
            <> testing
              had_href_child=true
              <> zz
                href=cx
                <> __StartTokenizedT
                <> __OneNewLine
                <> __EndTokenizedT
      ",
    ),
    testing.data_no_param(
      source: "
            <> testing
              <> zz
                <>
                  ''
                  ''
      ",
      expected: "
            <> testing
              <> zz
                <>
                  ''
                  ''
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
