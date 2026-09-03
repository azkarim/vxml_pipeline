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
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

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

/// Bijective base-26 digits for a positive integer.
fn to_alphabetic_digits(n: Int) -> List(Int) {
  case n {
    0 -> []
    _ -> do_alphabetic_digits(n, [])
  }
}

fn do_alphabetic_digits(n: Int, acc: List(Int)) -> List(Int) {
  case n {
    0 -> acc
    _ -> {
      let zero_based = n - 1
      do_alphabetic_digits(zero_based / 26, [zero_based % 26, ..acc])
    }
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

fn render_info(info: CounterInfo) -> Result(String, String) {
  case info.counter_type {
    Arabic -> Ok(ins(info.value))
    UppercaseRoman -> render_roman(info.value, True)
    LowercaseRoman -> render_roman(info.value, False)
    Unary(c) if info.value >= 0 -> Ok(string.repeat(c, info.value))
    Unary(_) -> Error("unary counters cannot render negative values")
    Uppercase -> render_alphabetic(info.value, 65)
    Lowercase -> render_alphabetic(info.value, 97)
  }
}

fn render_roman(value: Int, uppercase: Bool) -> Result(String, String) {
  case roman.int_to_roman(value) {
    Some(chars) -> {
      let rendered = roman.roman_to_string(chars)
      case uppercase {
        True -> Ok(string.uppercase(rendered))
        False -> Ok(rendered)
      }
    }
    None -> Error("Roman counters cannot render value " <> ins(value))
  }
}

fn render_alphabetic(
  value: Int,
  first_codepoint: Int,
) -> Result(String, String) {
  use <- on.false_true(value > 0, fn() {
    Error("alphabetic counters require a positive value; found " <> ins(value))
  })
  to_alphabetic_digits(value)
  |> list.map(fn(digit) {
    let assert Ok(codepoint) = string.utf_codepoint(digit + first_codepoint)
    codepoint
  })
  |> string.from_utf_codepoints
  |> Ok
}

fn process_regexp_groups(
  blame: Blame,
  counters: CounterDict,
  loudness: String,
  change: String,
  counter_name: String,
) -> Result(#(String, CounterDict), DesugaringError) {
  use <- on.false_true(counter_name != "", fn() {
    Error(DesugaringError(blame, "counter expression must have a name"))
  })
  use info <- on.error_ok(dict.get(counters, counter_name), fn(_) {
    Error(DesugaringError(blame, "undefined counter: " <> counter_name))
  })
  let info = update_info(info, change)
  use render <- on.ok(case loudness {
    _ if loudness == loud.string ->
      render_info(info)
      |> result.map_error(fn(message) { DesugaringError(blame, message) })
    _ if loudness == soft.string -> Ok("")
    _ -> panic
  })
  Ok(#(render, dict.insert(counters, counter_name, info)))
}

fn process_counter_candidate(
  blame: Blame,
  counters: CounterDict,
  backslashes: String,
  loudness: String,
  change: String,
  counter_name: String,
) -> Result(#(String, CounterDict), DesugaringError) {
  let backslash_count = string.length(backslashes)
  let preserved_backslashes = string.repeat("\\", backslash_count / 2)
  case backslash_count % 2 == 1 {
    True ->
      Ok(#(
        preserved_backslashes <> loudness <> change <> counter_name,
        counters,
      ))
    False -> {
      use #(rendered, counters) <- on.ok(process_regexp_groups(
        blame,
        counters,
        loudness,
        change,
        counter_name,
      ))
      Ok(#(preserved_backslashes <> rendered, counters))
    }
  }
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
    [backslashes, loudness, change, counter_name, ..splits] -> {
      use #(render, counters) <- on.ok(process_counter_candidate(
        blame,
        counters,
        backslashes,
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
  let splits = regexp.split(inner.counter_regexp, content)
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
  counter_name_regexp: Regexp,
) -> Result(#(String, CounterInfo), DesugaringError) {
  let splits =
    string.split(value, " ")
    |> list.filter(fn(s) { s != "" })

  use counter_name, rest <- on.empty_nonempty(splits, fn() {
    Error(DesugaringError(blame, "counter must have a name"))
  })

  use <- on.false_true(regexp.check(counter_name_regexp, counter_name), fn() {
    Error(DesugaringError(
      blame,
      "counter name must contain only ASCII letters; found '"
        <> counter_name
        <> "'",
    ))
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
  inner: InnerParam,
) -> Result(Option(#(String, CounterInfo)), DesugaringError) {
  use counter_type <- on.error(attr_key_is_counter(attr.key))

  use #(counter_name, counter_info) <- on.ok(
    parse_counter_definition_attr_value(
      attr.blame,
      counter_type,
      attr.val,
      inner.counter_name_regexp,
    ),
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

  use new_counter <- on.ok(read_counter_definition(next, inner))
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
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(blame, tag, attrs, children) = vxml
  use counters <- on.ok(restore_counter_scope(
    attrs,
    state_before,
    take_existing_counters(state_before, state_after),
    inner,
  ))
  Ok(#(V(blame, tag, attrs, children), counters))
}

fn restore_counter_scope(
  attrs: List(Attr),
  counters_before: CounterDict,
  counters_after: CounterDict,
  inner: InnerParam,
) -> Result(CounterDict, DesugaringError) {
  list.try_fold(attrs, counters_after, fn(counters, attr) {
    use definition <- on.ok(read_counter_definition(attr, inner))
    case definition {
      None -> Ok(counters)
      Some(#(counter_name, _)) ->
        case dict.get(counters_before, counter_name) {
          Ok(original) -> Ok(dict.insert(counters, counter_name, original))
          Error(_) -> Ok(dict.delete(counters, counter_name))
        }
    }
  })
}

fn counter_regex() -> Regexp {
  let assert Ok(re) =
    {
      "(\\\\*)("
      <> loud.regex_string
      <> "|"
      <> soft.regex_string
      <> ")("
      <> increment.regex_string
      <> "|"
      <> decrement.regex_string
      <> "|"
      <> no_change.regex_string
      <> ")([A-Za-z]*)"
    }
    |> regexp.from_string

  re
}

fn counter_name_regex() -> Regexp {
  let assert Ok(re) = regexp.from_string("^[A-Za-z]+$")
  re
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> core.DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneEnterExitStatefulNodemap(State) =
    n2t.EarlyReturnOneToOneEnterExitStatefulNodemap(
      on_enter: fn(vxml, state) {
        case vxml {
          V(_, tag, _, _) ->
            case list.contains(outside, tag) {
              True -> Ok(#(vxml, state, core.GoBack))
              False -> {
                use #(vxml, state) <- on.ok(on_enter(vxml, state, inner))
                Ok(#(vxml, state, core.Continue))
              }
            }
          _ -> {
            use #(vxml, state) <- on.ok(on_enter(vxml, state, inner))
            Ok(#(vxml, state, core.Continue))
          }
        }
      },
      on_exit: fn(vxml, before, after) {
        case vxml {
          V(_, tag, _, _) ->
            case list.contains(outside, tag) {
              True -> Ok(#(vxml, before))
              False -> on_exit(vxml, before, after, inner)
            }
          _ -> on_exit(vxml, before, after, inner)
        }
      },
      on_text: fn(vxml, state) { on_text(vxml, state, inner) },
    )
  n2t.early_return_one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(
    nodemap,
    dict.from_list([]),
  )
}

type InnerParam {
  InnerParam(counter_regexp: Regexp, counter_name_regexp: Regexp)
}

pub const name = "sigil_counters_substitute__outside"

// fn desugarer_blame(line_no: Int) { bl.Des([], name, line_no) }

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Substitutes strings of the form
///
///          (::|..)(++|--|øø)<counterName>
///
/// inside text lines and attribute values outside the listed
/// subtrees by the string value of the counter, while
/// incrementing/decrementing counters along the way.
///
/// Counter names must match `[A-Za-z]+`. A counter must have
/// been initialized by the time
/// it's used or else a DesugaringError will occur.
/// Definitions are scoped to the element carrying the
/// definition: a child may shadow an inherited counter,
/// and the inherited value is restored on leaving the child.
/// Mutations to an unshadowed inherited counter remain visible.
///
/// Alphabetic and Roman counters require positive values.
/// Unary counters require nonnegative values. Arabic counters
/// may have any integer value. Alphabetic counters use the
/// sequence A through Z, then AA, AB, and so forth.
///
/// Consecutive backslashes immediately before an expression
/// escape it by parity. An odd number leaves the expression
/// literal; an even number leaves it active. Each pair becomes
/// one literal backslash. The escaping backslash is removed.
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
/// particular, a counter of the form
///
///        ..øø<counterName>
///
/// has no effect on the document.
pub fn constructor(outside: List(String)) -> Desugarer {
  authoring.no_param_desugarer_with_outside(
    name: name,
    outside: outside,
    transform: fn(outside) {
      inner_param_to_transform(
        InnerParam(counter_regex(), counter_name_regex()),
        outside,
      )
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParamWithOutside) {
  [
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: ["pre"],
      source: "
                <> root
                  counter=Counter
                  <> pre
                    counter=bad-name
                    <>
                      '::++Counter'
                  <>
                    '::++Counter'
              ",
      expected: "
                <> root
                  counter=Counter
                  <> pre
                    counter=bad-name
                    <>
                      '::++Counter'
                  <>
                    '1'
              ",
    ),
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
      source: "
                <> root
                  counter=MyCounter 5 2
                  <>
                    '::++MyCounter'
                    '::--MyCounter'
                    '::++MyCounter.::++MyCounter'
                ",
      expected: "
                <> root
                  counter=MyCounter 5 2
                  <>
                    '7'
                    '5'
                    '7.9'
                ",
    ),
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
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
    testing.data_no_param_with_outside(
      outside: [],
      source: "
                <> root
                  counter-uppercase=Upper 24
                  counter-lowercase=Lower 24
                  <>
                    '::++Upper ::++Upper ::++Upper'
                    '::++Lower ::++Lower ::++Lower'
                ",
      expected: "
                <> root
                  counter-uppercase=Upper 24
                  counter-lowercase=Lower 24
                  <>
                    'Y Z AA'
                    'y z aa'
                ",
    ),
    testing.data_no_param_with_outside(
      outside: [],
      source: "
                <> root
                  counter=Scoped 10
                  <> Child
                    counter=Scoped 100
                    <>
                      'inside ::++Scoped'
                  <>
                    'outside ::++Scoped'
                ",
      expected: "
                <> root
                  counter=Scoped 10
                  <> Child
                    counter=Scoped 100
                    <>
                      'inside 101'
                  <>
                    'outside 11'
                ",
    ),
    testing.data_no_param_with_outside(
      outside: [],
      source: "
                <> root
                  counter=CounterName
                  <>
                    '::++CounterName_2'
                ",
      expected: "
                <> root
                  counter=CounterName
                  <>
                    '1_2'
                ",
    ),
    testing.data_no_param_with_outside(
      outside: [],
      source: "
                <> root
                  counter=Counter
                  <>
                    '\\::++Counter'
                    '\\\\::++Counter'
                    '\\\\\\::++Counter'
                    '\\\\\\\\::++Counter'
                    '\\::++Missing'
                    '\\::++'
                    '\\::--'
                    '\\::øø'
                    '\\..++'
                    '\\..--'
                    '\\..øø'
                ",
      expected: "
                <> root
                  counter=Counter
                  <>
                    '::++Counter'
                    '\\1'
                    '\\::++Counter'
                    '\\\\2'
                    '::++Missing'
                    '::++'
                    '::--'
                    '::øø'
                    '..++'
                    '..--'
                    '..øø'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param_with_outside(
    name,
    assertive_tests_data(),
    constructor,
  )
}
