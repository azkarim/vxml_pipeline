//// Test data, collections, and runners for desugarers.
////
//// Assertive tests describe a complete VXML transformation as source and
//// expected VXML strings. A collection binds those cases to one desugarer
//// constructor. The runner parses both strings, applies the desugarer, and
//// compares the resulting VXML while presenting blame-aware diagnostics.

import gleam/io
import gleam/list
import gleam/string
import vxml_pipeline/assertive_testing
import vxml_pipeline/core

/// One executable desugarer test.
pub type AssertiveTest =
  core.AssertiveTest

/// A named collection of tests belonging to one desugarer.
pub type AssertiveTestCollection =
  core.AssertiveTestCollection

/// Source, expected output, and parameter data for a parameterized desugarer.
pub type AssertiveTestData(a) =
  core.AssertiveTestData(a)

/// Source and expected output data for a parameterless desugarer.
pub type AssertiveTestDataNoParam =
  core.AssertiveTestDataNoParam

/// Test data for a parameterized `__outside` desugarer.
pub type AssertiveTestDataWithOutside(a) =
  core.AssertiveTestDataWithOutside(a)

/// Test data for a parameterless `__outside` desugarer.
pub type AssertiveTestDataNoParamWithOutside =
  core.AssertiveTestDataNoParamWithOutside

/// A parse, transformation, or comparison failure from one assertive test.
pub type AssertiveTestError =
  core.AssertiveTestError

/// Results for all tests belonging to one desugarer.
pub type AssertiveTestResults {
  AssertiveTestResults(
    desugarer_name: String,
    results: List(Result(Nil, AssertiveTestError)),
  )
}

/// Defines one test case for a parameterized desugarer.
pub fn data(param param: a, source source: String, expected expected: String) {
  core.AssertiveTestData(param, source, expected)
}

/// Defines one test case for a parameterless desugarer.
pub fn data_no_param(source source: String, expected expected: String) {
  core.AssertiveTestDataNoParam(source, expected)
}

/// Defines one test case for a parameterized `__outside` desugarer.
pub fn data_with_outside(
  param param: a,
  outside outside: List(String),
  source source: String,
  expected expected: String,
) {
  core.AssertiveTestDataWithOutside(param, outside, source, expected)
}

/// Defines one test case for a parameterless `__outside` desugarer.
pub fn data_no_param_with_outside(
  outside outside: List(String),
  source source: String,
  expected expected: String,
) {
  core.AssertiveTestDataNoParamWithOutside(outside, source, expected)
}

/// Builds a named test collection for a parameterized desugarer constructor.
pub fn collection(
  name name: String,
  data data: List(AssertiveTestData(a)),
  constructor constructor: fn(a) -> core.Desugarer,
) {
  core.assertive_test_collection_from_data(name, data, constructor)
}

/// Builds a named test collection for a parameterless desugarer constructor.
pub fn collection_no_param(
  name name: String,
  data data: List(AssertiveTestDataNoParam),
  constructor constructor: fn() -> core.Desugarer,
) {
  core.assertive_test_collection_from_data_no_param(name, data, constructor)
}

/// Builds a named test collection for a parameterized `__outside` constructor.
pub fn collection_with_outside(
  name name: String,
  data data: List(AssertiveTestDataWithOutside(a)),
  constructor constructor: fn(a, List(String)) -> core.Desugarer,
) {
  core.assertive_test_collection_from_data_with_outside(name, data, constructor)
}

/// Builds a named test collection for a parameterless `__outside` constructor.
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

/// Runs one already-constructed assertive test.
pub fn run_test(name: String, assertive_test: AssertiveTest) {
  assertive_testing.run_assertive_test(name, assertive_test)
}

/// Runs every test in each supplied collection without printing a summary.
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

/// Returns whether every result in every supplied collection passed.
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
