import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type Attr, type VXML, Attr, V}

pub const name = "ensure_attribute_value_starts_with_prefix"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Completes the configured prefix on matching attribute
/// values while preserving an existing overlapping suffix.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Attribute key.
    String,
    // Required prefix.
    String,
  )

type PrefixesAndSuffixes =
  List(#(String, String))

type InnerParam {
  InnerParam(key: String, prefixes_and_suffixes: PrefixesAndSuffixes)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, prefix_suffix_list(param.1)))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, _, attrs, _) ->
      V(..vxml, attrs: list.map(attrs, update_attr(_, inner)))
    _ -> vxml
  }
}

fn update_attr(attr: Attr, inner: InnerParam) -> Attr {
  case inner.key == attr.key {
    True ->
      Attr(
        ..attr,
        val: add_prefix_of_first_matching_suffix(
          attr.val,
          inner.prefixes_and_suffixes,
        ),
      )
    _ -> attr
  }
}

fn add_prefix_of_first_matching_suffix(
  value: String,
  prefixes_suffixes: PrefixesAndSuffixes,
) -> String {
  case prefixes_suffixes {
    [] -> panic
    [#(a, b), ..rest] ->
      case string.starts_with(value, b) {
        True -> a <> value
        False -> add_prefix_of_first_matching_suffix(value, rest)
      }
  }
}

fn prefix_suffix_list(s: String) -> PrefixesAndSuffixes {
  prefix_suffix_list_acc("", string.split(s, ""))
}

fn prefix_suffix_list_acc(
  acc: String,
  chars: List(String),
) -> PrefixesAndSuffixes {
  case chars {
    [] -> [#(acc, "")]
    [first, ..rest] -> {
      let others = prefix_suffix_list_acc(acc <> first, rest)
      [#(acc, chars |> string.join("")), ..others]
    }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
