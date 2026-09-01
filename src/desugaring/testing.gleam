import desugaring/assertive_testing
import desugaring/core
import gleam/io
import gleam/list
import gleam/string

pub type AssertiveTest =
  core.AssertiveTest

pub type AssertiveTestCollection =
  core.AssertiveTestCollection

pub type AssertiveTestData(a) =
  core.AssertiveTestData(a)

pub type AssertiveTestDataNoParam =
  core.AssertiveTestDataNoParam

pub type AssertiveTestDataWithOutside(a) =
  core.AssertiveTestDataWithOutside(a)

pub type AssertiveTestDataNoParamWithOutside =
  core.AssertiveTestDataNoParamWithOutside

pub type AssertiveTestError =
  core.AssertiveTestError

pub type AssertiveTestResults {
  AssertiveTestResults(
    desugarer_name: String,
    results: List(Result(Nil, AssertiveTestError)),
  )
}

pub fn data(param param: a, source source: String, expected expected: String) {
  core.AssertiveTestData(param, source, expected)
}

pub fn data_no_param(source source: String, expected expected: String) {
  core.AssertiveTestDataNoParam(source, expected)
}

pub fn data_with_outside(
  param param: a,
  outside outside: List(String),
  source source: String,
  expected expected: String,
) {
  core.AssertiveTestDataWithOutside(param, outside, source, expected)
}

pub fn data_no_param_with_outside(
  outside outside: List(String),
  source source: String,
  expected expected: String,
) {
  core.AssertiveTestDataNoParamWithOutside(outside, source, expected)
}

pub fn collection(
  name name: String,
  data data: List(AssertiveTestData(a)),
  constructor constructor: fn(a) -> core.Desugarer,
) {
  core.assertive_test_collection_from_data(name, data, constructor)
}

pub fn collection_no_param(
  name name: String,
  data data: List(AssertiveTestDataNoParam),
  constructor constructor: fn() -> core.Desugarer,
) {
  core.assertive_test_collection_from_data_no_param(name, data, constructor)
}

pub fn collection_with_outside(
  name name: String,
  data data: List(AssertiveTestDataWithOutside(a)),
  constructor constructor: fn(a, List(String)) -> core.Desugarer,
) {
  core.assertive_test_collection_from_data_with_outside(name, data, constructor)
}

pub fn collection_no_param_with_outside(
  name name: String,
  data data: List(AssertiveTestDataNoParamWithOutside),
  constructor constructor: fn(List(String)) -> core.Desugarer,
) {
  core.assertive_test_collection_from_data_no_param_with_outside(
    name,
    data,
    constructor,
  )
}

pub fn run_test(name: String, assertive_test: AssertiveTest) {
  assertive_testing.run_assertive_test(name, assertive_test)
}

pub fn run(
  collections: List(AssertiveTestCollection),
) -> List(AssertiveTestResults) {
  list.map(collections, fn(collection) {
    AssertiveTestResults(
      collection.desugarer_name,
      collection.tests()
        |> list.map(run_test(collection.desugarer_name, _)),
    )
  })
}

pub fn all_passed(results: List(AssertiveTestResults)) -> Bool {
  list.all(results, fn(group) {
    list.all(group.results, fn(result) {
      case result {
        Ok(Nil) -> True
        Error(_) -> False
      }
    })
  })
}

/// Run some or all tests from a desugarer collection registry.
///
/// An empty list of names selects every collection. Names may optionally end
/// in `.gleam`.
pub fn test_desugarers(
  collection_builders: List(fn() -> AssertiveTestCollection),
  requested_names: List(String),
) -> Result(Nil, String) {
  let result = test_desugarers_content(collection_builders, requested_names)
  io.println("")
  result
}

/// Run local desugarer tests without closing the surrounding output block.
pub fn test_desugarers_content(
  collection_builders: List(fn() -> AssertiveTestCollection),
  requested_names: List(String),
) -> Result(Nil, String) {
  let requested_names = list.map(requested_names, without_gleam_extension)
  assertive_testing.run_assertive_desugarer_tests_content(
    collection_builders,
    requested_names,
  )
}

fn without_gleam_extension(name: String) -> String {
  case string.ends_with(name, ".gleam") {
    True -> string.drop_end(name, 6)
    False -> name
  }
}
