import colours
import desugaring/core.{
  type AssertiveTest, type AssertiveTestCollection, type AssertiveTestError,
  InequalityError, NonMatchingDesugarerName, TestDesugaringError, VXMLParseError,
  VXMLSerializationError,
}
import gleam/io
import gleam/list
import gleam/result
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML}
import vxml/io_lines.{OutputLine} as io_l

fn first_different_line(c: Int, l1: List(a), l2: List(a)) -> Int {
  case l1, l2 {
    [], [] -> panic
    [], [_, ..] -> c
    [_, ..], [] -> c
    [l1_first, ..l1], [l2_first, ..l2] ->
      case l1_first != l2_first {
        True -> c
        False -> first_different_line(c + 1, l1, l2)
      }
  }
}

@internal
pub fn run_assertive_test(
  name: String,
  tst: AssertiveTest,
) -> Result(Nil, AssertiveTestError) {
  let desugarer = tst.constructor()
  use <- on.true_false(name != desugarer.name, fn() {
    Error(NonMatchingDesugarerName(desugarer.name))
  })
  use vxmls <- on.ok(
    vxml.parse_string(tst.source, "tst.source", True)
    |> result.map_error(fn(e) { VXMLParseError(e) }),
  )
  let assert [input] = vxmls
  use vxmls <- on.ok(
    vxml.parse_string(tst.expected, "tst.expect", True)
    |> result.map_error(fn(e) { VXMLParseError(e) }),
  )
  let assert [expected] = vxmls
  use #(output, _) <- on.ok(
    desugarer.transform(input)
    |> result.map_error(fn(e) { TestDesugaringError(e) }),
  )
  use output_string <- on.ok(
    vxml.vxml_to_string(output)
    |> result.map_error(fn(e) { VXMLSerializationError(e) }),
  )
  use expected_string <- on.ok(
    vxml.vxml_to_string(expected)
    |> result.map_error(fn(e) { VXMLSerializationError(e) }),
  )
  case output_string == expected_string {
    True -> Ok(Nil)
    False ->
      Error(InequalityError(
        desugarer.name,
        output,
        expected,
        first_different_line(
          0,
          output_string |> string.split("\n"),
          expected_string |> string.split("\n"),
        ),
      ))
  }
}

@internal
pub fn highlight_and_echo(vxml: VXML, above: Int, banner: String) -> Nil {
  case vxml.vxml_to_output_lines(vxml) {
    Error(error) -> io.println(ins(error))
    Ok(lines) ->
      lines
      |> list.index_map(fn(line, i) {
        case i >= above {
          False -> line
          True -> OutputLine(..line, suffix: colours.fgred(line.suffix))
        }
      })
      |> io_l.output_lines_table(banner, 0)
      |> io.println
  }
}

@internal
pub fn run_and_announce_results(
  last_was_failure: Bool,
  test_group: AssertiveTestCollection,
  tst: AssertiveTest,
  number: Int,
  total: Int,
) -> Bool {
  case run_assertive_test(test_group.desugarer_name, tst) {
    Ok(Nil) -> {
      io.print("✅")
      False
    }
    Error(error) -> {
      io.print(case last_was_failure {
        True -> ""
        False -> "\n"
      })
      io.print("❌ test " <> ins(number) <> " of " <> ins(total) <> " failed:")
      case error {
        InequalityError(_, obtained, expected, first_different) -> {
          io.println(" obtained != expected:")
          obtained |> highlight_and_echo(first_different, "obtained")
          expected |> highlight_and_echo(first_different, "expected")
        }
        _ -> io.println(ins(error))
      }
      True
    }
  }
}

fn indicator(b: Bool) -> Int {
  case b {
    False -> 0
    True -> 1
  }
}

fn run_assertive_test_collection(test_group: AssertiveTestCollection) -> Bool {
  let tests = test_group.tests()
  let total = list.length(tests)
  use <- on.true(total > 0)
  io.print(test_group.desugarer_name <> " ")
  let #(_, num_failures, _) =
    list.fold(tests, #(0, 0, False), fn(acc, tst) {
      let #(num_success, num_failures, last_was_failure) = acc
      let failure =
        run_and_announce_results(
          last_was_failure,
          test_group,
          tst,
          acc.0 + acc.1 + 1,
          total,
        )
      let failure01 = indicator(failure)
      #(num_success + 1 - failure01, num_failures + failure01, failure)
    })
  case list.length(tests) == 1 {
    True -> io.println(" (1 assertive test)")
    False -> io.println(" (" <> ins(total) <> " assertive tests)")
  }
  num_failures > 0
}

/// Run selected tests from the supplied desugarer collection registry.
///
/// An empty list of names selects every collection.
@internal
pub fn run_assertive_desugarer_tests(
  collection_builders: List(fn() -> AssertiveTestCollection),
  names: List(String),
) -> Result(Nil, String) {
  let result = run_assertive_desugarer_tests_content(collection_builders, names)
  io.println("")
  result
}

/// Run selected tests without closing the surrounding output block.
@internal
pub fn run_assertive_desugarer_tests_content(
  collection_builders: List(fn() -> AssertiveTestCollection),
  names: List(String),
) -> Result(Nil, String) {
  let collections =
    list.map(collection_builders, fn(constructor) { constructor() })

  let #(all, dont_have_tests) =
    list.fold(collections, #([], []), fn(acc, collection) {
      case list.is_empty(collection.tests()) {
        False -> #([collection, ..acc.0], acc.1)
        True -> #([collection, ..acc.0], [collection, ..acc.1])
      }
    })

  let tested_names = all |> list.map(fn(c) { c.desugarer_name })
  let collection_names = collections |> list.map(fn(c) { c.desugarer_name })

  let names = case names {
    [] -> tested_names
    _ -> names
  }

  let dont_have_tests =
    list.filter(dont_have_tests, fn(c) {
      list.contains(names, c.desugarer_name)
    })

  case dont_have_tests {
    [] -> Nil
    _ -> {
      io.println(
        ins(list.length(dont_have_tests)) <> " desugarers do not have tests:\n",
      )
      list.each(dont_have_tests |> list.reverse, fn(c) {
        io.println(" - " <> c.desugarer_name)
      })
      io.println("")
    }
  }

  let #(num_performed, num_failed) =
    list.fold(collections, #(0, 0), fn(acc, coll) {
      case
        {
          list.contains(names, coll.desugarer_name)
          && !list.is_empty(coll.tests())
        }
      {
        False -> acc
        True -> #(
          acc.0 + 1,
          acc.1 + indicator(run_assertive_test_collection(coll)),
        )
      }
    })

  case num_performed > 0 {
    True -> io.println("")
    False -> Nil
  }
  io.println(
    ins(num_performed)
    <> case num_performed == 1 {
      True -> " desugarer tested, "
      False -> " desugarers tested, "
    }
    <> ins(num_failed)
    <> case num_failed == 1 {
      True -> " failed"
      False -> " failures"
    },
  )

  let unknown_names =
    list.filter(names, fn(name) { !list.contains(collection_names, name) })

  case list.is_empty(unknown_names) {
    True -> Nil
    False -> {
      io.println("")
      io.println("could not find any test data for the following desugarers:")
      list.each(unknown_names, fn(name) { io.println(" - " <> name) })
    }
  }

  case num_failed, unknown_names {
    0, [] -> Ok(Nil)
    _, [name, ..] -> Error("No local desugarer named '" <> name <> "'.")
    _, _ -> Error("Local desugarer tests failed.")
  }
}
