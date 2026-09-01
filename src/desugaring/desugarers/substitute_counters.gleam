import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Regexp}
import gleam/result
import gleam/string.{inspect as ins}
import on
import roman
import vxml.{type Attr, type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame}

type CounterType {
  Arabic
  Lowercase
  Uppercase
  LowercaseRoman
  UppercaseRoman
  Unary(String)
}

type CounterInfo {
  CounterInfo(counter_type: CounterType, value: Int, step: Int)
}

type CounterDict =
  Dict(String, CounterInfo)

type State =
  CounterDict

type StringAndRegexVersion {
  StringAndRegexVersion(string: String, regex_string: String)
}

const loud = StringAndRegexVersion(string: "::", regex_string: "::")

const soft = StringAndRegexVersion(string: "..", regex_string: "\\.\\.")

const increment = StringAndRegexVersion(string: "++", regex_string: "\\+\\+")

const decrement = StringAndRegexVersion(string: "--", regex_string: "--")

const no_change = StringAndRegexVersion(string: "øø", regex_string: "øø")

/// Base-26 expansion of a nonnegative integer.
fn to_base_26(n: Int) -> List(Int) {
  case n {
    0 -> [0]
    _ -> do_base_26(n, [])
  }
}

fn do_base_26(n: Int, acc: List(Int)) -> List(Int) {
  case n {
    0 -> acc
    _ -> do_base_26(n / 26, [n % 26, ..acc])
  }
}

fn update_info(info: CounterInfo, mutation: String) -> CounterInfo {
  case mutation {
    _ if mutation == increment.string ->
      CounterInfo(..info, value: info.value + info.step)
    _ if mutation == decrement.string ->
      CounterInfo(..info, value: info.value - info.step)
    _ if mutation == no_change.string -> info
    _ -> {
      panic as "bad mutation"
    }
  }
}

fn render_info(info: CounterInfo) -> String {
  case info.counter_type {
    Arabic -> ins(info.value)
    UppercaseRoman ->
      roman.int_to_roman(info.value)
      |> option.unwrap([])
      |> roman.roman_to_string()
      |> string.uppercase
    LowercaseRoman ->
      roman.int_to_roman(info.value)
      |> option.unwrap([])
      |> roman.roman_to_string()
    Unary(c) -> string.repeat(c, info.value)
    Uppercase -> {
      to_base_26(info.value - 1)
      |> list.map(fn(d) {
        let assert Ok(cp) = string.utf_codepoint(d + 65)
        cp
      })
      |> string.from_utf_codepoints
    }
    Lowercase -> {
      to_base_26(info.value - 1)
      |> list.map(fn(d) {
        let assert Ok(cp) = string.utf_codepoint(d + 97)
        cp
      })
      |> string.from_utf_codepoints
    }
  }
}

fn process_regexp_groups(
  blame: Blame,
  counters: CounterDict,
  loudness: String,
  change: String,
  counter_name: String,
) -> Result(#(String, CounterDict), DesugaringError) {
  use info <- on.error_ok(dict.get(counters, counter_name), fn(_) {
    Error(DesugaringError(blame, "undefined counter: " <> counter_name))
  })
  let info = update_info(info, change)
  let render = case loudness {
    _ if loudness == loud.string -> render_info(info)
    _ if loudness == soft.string -> ""
    _ -> panic
  }
  Ok(#(render, dict.insert(counters, counter_name, info)))
}

fn process_splits(
  blame: Blame,
  already_processed: List(String),
  counters: CounterDict,
  splits: List(String),
) -> Result(#(List(String), CounterDict), DesugaringError) {
  let assert [first, ..splits] = splits
  case splits {
    [] -> Ok(#([first, ..already_processed], counters))
    [loudness, change, counter_name, ..splits] -> {
      use #(render, counters) <- on.ok(process_regexp_groups(
        blame,
        counters,
        loudness,
        change,
        counter_name,
      ))
      process_splits(
        blame,
        [render, first, ..already_processed],
        counters,
        splits,
      )
    }
    _ -> panic
  }
}

fn process_string(
  blame: Blame,
  content: String,
  counters: CounterDict,
  inner: InnerParam,
) -> Result(#(String, CounterDict), DesugaringError) {
  use <- on.true_false(content == "", fn() { Ok(#("", counters)) })
  let splits = regexp.split(inner, content)
  use #(strings, counters) <- on.ok(process_splits(blame, [], counters, splits))
  Ok(#(strings |> list.reverse |> string.join(""), counters))
}

fn update_lines(
  lines: List(Line),
  counters: CounterDict,
  inner: InnerParam,
) -> Result(#(List(Line), CounterDict), DesugaringError) {
  // nb: tried doing an early-return test here on
  // 'lines' to improve speed, didn't help much
  lines
  |> list.try_fold(#([], counters), fn(acc, line) {
    let #(lines, counters) = acc
    use #(content, counters) <- on.ok(process_string(
      line.blame,
      line.content,
      counters,
      inner,
    ))
    Ok(#([Line(..line, content: content), ..lines], counters))
  })
  |> result.map(fn(acc) { #(acc.0 |> list.reverse, acc.1) })
}

fn take_existing_counters(
  current: CounterDict,
  new: CounterDict,
) -> CounterDict {
  new
  |> dict.filter(fn(k, _) { dict.has_key(current, k) })
}

fn parse_counter_definition_attr_value(
  blame: Blame,
  counter_type: CounterType,
  value: String,
) -> Result(#(String, CounterInfo), DesugaringError) {
  let splits =
    string.split(value, " ")
    |> list.filter(fn(s) { s != "" })

  use counter_name, rest <- on.empty_nonempty(splits, fn() {
    Error(DesugaringError(blame, "counter must have a name"))
  })

  use #(counter_type, rest) <- on.ok(case counter_type {
    Unary(_) ->
      case rest {
        [first, ..rest] -> Ok(#(Unary(first), rest))
        [] -> Error(DesugaringError(blame, "unary counter missing 1-value"))
      }
    _ -> Ok(#(counter_type, rest))
  })

  use starting_value, rest <- on.empty_nonempty(rest, fn() {
    Ok(#(counter_name, CounterInfo(counter_type, 0, 1)))
  })

  use starting_value <- on.error_ok(int.parse(starting_value), fn(_) {
    Error(DesugaringError(blame, "counter starting value must be a number"))
  })

  use step, rest <- on.empty_nonempty(rest, fn() {
    Ok(#(counter_name, CounterInfo(counter_type, starting_value, 1)))
  })

  use step <- on.error_ok(int.parse(step), fn(_) {
    Error(DesugaringError(blame, "counter step size must be a number"))
  })

  case list.is_empty(rest) {
    True -> Ok(#(counter_name, CounterInfo(counter_type, starting_value, step)))
    False ->
      Error(DesugaringError(
        blame,
        "extra arguments found after <counter_name> <starting_value> <step_value>",
      ))
  }
}

fn attr_key_is_counter(key: String) -> Result(Option(_), CounterType) {
  case key {
    "counter" -> Error(Arabic)
    "counter-lowercase" -> Error(Lowercase)
    "counter-uppercase" -> Error(Uppercase)
    "counter-roman-lowercase" -> Error(LowercaseRoman)
    "counter-roman-uppercase" -> Error(UppercaseRoman)
    "counter-unary" -> Error(Unary(""))
    _ -> Ok(None)
  }
}

fn read_counter_definition(
  attr: Attr,
) -> Result(Option(#(String, CounterInfo)), DesugaringError) {
  use counter_type <- on.error(attr_key_is_counter(attr.key))

  use #(counter_name, counter_info) <- on.ok(
    parse_counter_definition_attr_value(attr.blame, counter_type, attr.val),
  )

  Ok(Some(#(counter_name, counter_info)))
}

fn fancy_one_attr_processor(
  attr: Attr,
  counters: CounterDict,
  inner: InnerParam,
) -> Result(#(Attr, CounterDict), DesugaringError) {
  let Attr(blame, original_key, val) = attr

  use #(key, counters) <- on.ok(process_string(
    blame,
    original_key,
    counters,
    inner,
  ))

  let assert True = key == string.trim(key)

  use <- on.true_false(key == "", fn() {
    Error(DesugaringError(
      blame,
      "empty key after processing counters; original key: '"
        <> original_key
        <> "'",
    ))
  })

  use #(val, counters) <- on.ok(process_string(blame, val, counters, inner))

  Ok(#(Attr(blame, key, val), counters))
}

fn fancy_attr_processor(
  already_processed: List(Attr),
  yet_to_be_processed: List(Attr),
  counters: CounterDict,
  inner: InnerParam,
) -> Result(#(List(Attr), CounterDict), DesugaringError) {
  use next, rest <- on.empty_nonempty(yet_to_be_processed, fn() {
    Ok(#(already_processed |> list.reverse, counters))
  })

  use #(next, counters) <- on.ok(fancy_one_attr_processor(next, counters, inner))

  use new_counter <- on.ok(read_counter_definition(next))
  let counters = case new_counter {
    None -> counters
    Some(#(key, value)) -> dict.insert(counters, key, value)
  }

  let already_processed = [next, ..already_processed]

  fancy_attr_processor(already_processed, rest, counters, inner)
}

fn on_enter(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(b, t, attrs, c) = vxml
  let counters = state

  use #(attrs, counters) <- on.ok(fancy_attr_processor(
    [],
    attrs,
    counters,
    inner,
  ))

  Ok(#(V(b, t, attrs, c), counters))
}

fn on_text(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert T(blame, lines) = vxml
  let counters = state
  use #(lines, updated_counters) <- on.ok(update_lines(lines, counters, inner))
  #(T(blame, lines), updated_counters)
  |> Ok
}

fn on_exit(
  vxml: VXML,
  state_before: State,
  state_after: State,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(blame, tag, attrs, children) = vxml
  let counters_before = state_before
  let counters_after = state_after
  let counters = take_existing_counters(counters_before, counters_after)
  Ok(#(V(blame, tag, attrs, children), counters))
}

fn counter_regex() -> Regexp {
  let assert Ok(re) =
    {
      "("
      <> loud.regex_string
      <> "|"
      <> soft.regex_string
      <> ")("
      <> increment.regex_string
      <> "|"
      <> decrement.regex_string
      <> "|"
      <> no_change.regex_string
      <> ")(\\w+)"
    }
    |> regexp.from_string

  re
}

fn inner_param_to_transform(inner: InnerParam) -> core.DesugarerTransform {
  let nodemap: n2t.OneToOneEnterExitStatefulNodemap(State) =
    n2t.OneToOneEnterExitStatefulNodemap(
      on_enter: fn(vxml, state) { on_enter(vxml, state, inner) },
      on_exit: on_exit,
      on_text: fn(vxml, state) { on_text(vxml, state, inner) },
    )
  n2t.one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(
    nodemap,
    dict.from_list([]),
  )
}

type InnerParam =
  Regexp

pub const name = "substitute_counters"

// fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Substitutes strings of the form
///
///          (::|..)(++|--|øø)<counterName>
///
/// inside text lines and attribute values by string
/// value of the counter, while incrementing/decrementing
/// counters along the way.
///
/// The counter must have initialized by the time
/// it's used or else a DesugaringError will occur.
///
/// E.g., here is a correct use of a counter:
///
/// <> Chapter
///     counter=SectionCounter
///     <> Section
///         number=::--SectionCounter
///
/// After the desugarer is run, this would become:
///
/// <> Chapter
///     counter=SectionCounter
///     <> Section
///         number=-1
///
/// The second capturing group (++|--|øø)
/// determines whether a counter is incremented,
/// decremented, or kept equal at a point (according
/// to its step size), whereas the first capturing
/// group determines the string value of the counter
/// is echoed '::' or silenced '..', i.e., inserted
/// or not into the document at that point. In
/// partuclar, a counter of the form
///
///        ..øø<counterName>
///
/// has no effect on the document.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(counter_regex()),
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
                  counter=QCounter -3
                  <>
                    'aa::--QCounter;bb'
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  <>
                    'aa-4;bb'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter=QCounter -3
                  <>
                    '::--QCounter;..--QCounter'
                    '..--QCounter;::--QCounter'
                    'GooseMan..--QCounter;::--QCounter;..--QCounter;..--QCounter.::--QCounter@hoverboard'
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  <>
                    '-4;'
                    ';-7'
                    'GooseMan;-9;;.-12@hoverboard'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter=QCounter -3
                  <>
                    '::++QCounter ..øøQCounter'
                    '::--QCounter'
                    '::++QCounter.::++QCounter K..øøQCounter&W'
                ",
      expected: "
                <> root
                  counter=QCounter -3
                  <>
                    '-2 '
                    '-3'
                    '-2.-1 K&W'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter=my_counter 5 2
                  <>
                    '::++my_counter'
                    '::--my_counter'
                    '::++my_counter.::++my_counter'
                ",
      expected: "
                <> root
                  counter=my_counter 5 2
                  <>
                    '7'
                    '5'
                    '7.9'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter=TestCounter -1
                  <>
                    '::++TestCounter'
                    '::--TestCounter::--TestCounter'
                ",
      expected: "
                <> root
                  counter=TestCounter -1
                  <>
                    '0'
                    '-1-2'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter-uppercase=ChapCtr
                  <>
                    '::++ChapCtr'
                    '::++ChapCtr'
                    '::++ChapCtr'
                ",
      expected: "
                <> root
                  counter-uppercase=ChapCtr
                  <>
                    'A'
                    'B'
                    'C'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter-lowercase=SecCtr
                  <>
                    '::++SecCtr'
                    '::++SecCtr'
                    '::++SecCtr'
                ",
      expected: "
                <> root
                  counter-lowercase=SecCtr
                  <>
                    'a'
                    'b'
                    'c'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter-roman-uppercase=RomCtr
                  <>
                    '::++RomCtr'
                    '::++RomCtr'
                    '::++RomCtr'
                    '::++RomCtr'
                ",
      expected: "
                <> root
                  counter-roman-uppercase=RomCtr
                  <>
                    'I'
                    'II'
                    'III'
                    'IV'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter-roman-lowercase=RomCtr
                  <>
                    '::++RomCtr'
                    '::++RomCtr'
                    '::++RomCtr'
                    '::++RomCtr'
                ",
      expected: "
                <> root
                  counter-roman-lowercase=RomCtr
                  <>
                    'i'
                    'ii'
                    'iii'
                    'iv'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter-unary=StarCtr *
                  <>
                    '::++StarCtr'
                    '::++StarCtr'
                    '::++StarCtr'
                ",
      expected: "
                <> root
                  counter-unary=StarCtr *
                  <>
                    '*'
                    '**'
                    '***'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter-uppercase=AppCtr
                  <>
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                    '::++AppCtr'
                ",
      expected: "
                <> root
                  counter-uppercase=AppCtr
                  <>
                    'A'
                    'B'
                    'C'
                    'D'
                    'E'
                    'F'
                    'G'
                    'H'
                    'I'
                    'J'
                    'K'
                    'L'
                    'M'
                    'N'
                    'O'
                    'P'
                    'Q'
                    'R'
                    'S'
                    'T'
                    'U'
                    'V'
                    'W'
                    'X'
                    'Y'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter=QCounter  -3
                  <>
                    '::++QCounter'
                ",
      expected: "
                <> root
                  counter=QCounter  -3
                  <>
                    '-2'
                ",
    ),
    testing.data_no_param(
      source: "
                <> root
                  counter-unary=StarCtr  *
                  <>
                    '::++StarCtr'
                ",
      expected: "
                <> root
                  counter-unary=StarCtr  *
                  <>
                    '*'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
