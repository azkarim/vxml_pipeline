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

pub const name = "tokenize_text_children_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Tokenizes text children of elements that satisfy the
/// configured condition.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let opening_punctuation_splitter: Splitter =
    splitter.new([" ", "(", "[", "—"])
  Ok(#(param, opening_punctuation_splitter))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, _, children) ->
      case inner.0(vxml) {
        False -> vxml
        True -> {
          let children =
            list.map(children, fn(vxml) { tokenize_if_t(inner.1, vxml) })
            |> list.flatten
          V(..vxml, children: children)
        }
      }
  }
}

fn tokenize_if_t(
  opening_punctuation_splitter: Splitter,
  vxml: VXML,
) -> List(VXML) {
  case vxml {
    T(_, _) -> tokenize_t(opening_punctuation_splitter, vxml)
    _ -> [vxml]
  }
}

fn tokenize_t(
  opening_punctuation_splitter: Splitter,
  vxml: VXML,
) -> List(VXML) {
  let assert T(blame, lines) = vxml
  lines
  |> list.index_map(fn(line, i) {
    tokenize_string_acc(
      opening_punctuation_splitter,
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
  opening_punctuation_splitter: Splitter,
  past_tokens: List(VXML),
  current_blame: Blame,
  leftover: String,
) -> List(VXML) {
  case splitter.split(opening_punctuation_splitter, leftover) {
    #(_, "", _) ->
      case leftover == "" {
        True -> past_tokens |> list.reverse
        False ->
          [word_node(current_blame, leftover), ..past_tokens] |> list.reverse
      }
    #("", " ", after) ->
      tokenize_string_acc(
        opening_punctuation_splitter,
        [space_node(current_blame), ..past_tokens],
        bl.advance(current_blame, 1),
        after,
      )
    #(before, " ", after) ->
      tokenize_string_acc(
        opening_punctuation_splitter,
        [
          space_node(current_blame),
          word_node(current_blame, before),
          ..past_tokens
        ],
        bl.advance(current_blame, string.length(before) + 1),
        after,
      )
    #("", non_space_punctuation, after) ->
      tokenize_string_acc(
        opening_punctuation_splitter,
        [word_node(current_blame, non_space_punctuation), ..past_tokens],
        bl.advance(current_blame, 1),
        after,
      )
    #(before, non_space_punctuation, after) ->
      tokenize_string_acc(
        opening_punctuation_splitter,
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
  V(blame, "__OneWord", [Attr(desugarer_blame(38), "val", word)], [])
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
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
  fn(VXML) -> Bool

type InnerParam =
  #(Param, Splitter)

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  let test_param = fn(vxml) {
    let assert V(_, t, _, _) = vxml
    t == "a"
  }
  [
    testing.data(
      param: test_param,
      source: "
                <> testing
                  <> a
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
                  <> a
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
    testing.data(
      param: test_param,
      source: "
            <> testing
              <> a
                <>
                  'first  line'
                  'second  '
                  '   line'
      ",
      expected: "
            <> testing
              <> a
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
    testing.data(
      param: test_param,
      source: "
            <> testing
              <> a
                <>
                  ''
                  ''
      ",
      expected: "
            <> testing
              <> a
                <> __StartTokenizedT
                <> __OneNewLine
                <> __EndTokenizedT
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
