import gleam/list
import gleam/regexp.{type Regexp}
import on
import vxml.{type Attr, type VXML, Attr, V}
import vxml/blame as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "sigil_counters_prepend_incrementing_attribute__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends temporary counter-increment instruction attrs to
/// matching elements. Repeated target tags are allowed and cause
/// every associated instruction to be prepended in list order.
/// The named counters must already be in scope. Run
/// `sigil_counters_substitute__outside` afterward, then delete the temporary
/// `_` attrs when they are no longer useful for inspection.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: core.list_param_stringifier(param),
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Target tag.
      String,
      // Counter name.
      String,
    ),
  )

type InnerParam =
  List(#(String, Attr))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(counter_name_regexp) = regexp.from_string("^[A-Za-z]+$")
  list.try_map(param, prepare_one(_, counter_name_regexp))
}

fn prepare_one(
  pair: #(String, String),
  counter_name_regexp: Regexp,
) -> Result(#(String, Attr), DesugaringError) {
  let #(target_tag, counter_name) = pair
  use <- on.false_true(core.valid_tag(target_tag), fn() {
    Error(DesugaringError(
      bl.no_blame,
      "invalid target tag name '" <> target_tag <> "'",
    ))
  })
  use <- on.false_true(regexp.check(counter_name_regexp, counter_name), fn() {
    Error(DesugaringError(
      bl.no_blame,
      "counter name must contain only ASCII letters; found '"
        <> counter_name
        <> "'",
    ))
  })
  Ok(#(
    target_tag,
    Attr(
      authoring.blame(name, 75),
      "_",
      counter_name <> " ::++" <> counter_name,
    ),
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, attrs, _) -> {
      let increment_attrs =
        inner
        |> list.filter(fn(pair) { pair.0 == tag })
        |> list.map(fn(pair) { pair.1 })

      case increment_attrs {
        [] -> vxml
        _ -> V(..vxml, attrs: list.append(increment_attrs, attrs))
      }
    }
    _ -> vxml
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [
        #("Section", "SectionCounter"),
        #("Exercise", "ExerciseCounter"),
        #("Section", "PageCounter"),
      ],
      source: "
                  <> root
                    <> Section
                      title=Introduction
                      <> Exercise
                        title=First exercise
                    <> Other
                ",
      expected: "
                  <> root
                    <> Section
                      _=SectionCounter ::++SectionCounter
                      _=PageCounter ::++PageCounter
                      title=Introduction
                      <> Exercise
                        _=ExerciseCounter ::++ExerciseCounter
                        title=First exercise
                    <> Other
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
