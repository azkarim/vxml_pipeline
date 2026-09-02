import gleam/list
import gleam/option.{Some}
import gleam/regexp.{type Regexp, Match}
import gleam/result
import on
import vxml.{type Attr, type VXML, Attr, V}
import vxml/blame as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "writerly_handles_set_value__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends configured values to value-free handle attrs on
/// matching elements. Existing values remain unchanged. Repeated
/// target tags are allowed; the first configured value wins.
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
      // Handle value to append.
      String,
    ),
  )

type InnerParam {
  InnerParam(values_by_tag: List(#(String, String)), handle_regexp: Regexp)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  use _ <- result.try(
    list.try_each(param, fn(pair) {
      use <- on.false_true(core.valid_tag(pair.0), fn() {
        Error(DesugaringError(
          bl.no_blame,
          "invalid target tag name '" <> pair.0 <> "'",
        ))
      })
      Ok(Nil)
    }),
  )
  let assert Ok(handle_regexp) =
    regexp.from_string(
      "^(" <> handle_syntax.decorated_name_pattern <> ")(?: <<(.*)>>)?$",
    )
  Ok(InnerParam(param, handle_regexp))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, tag, attrs, _) -> {
      let values =
        inner.values_by_tag
        |> list.filter(fn(pair) { pair.0 == tag })
        |> list.map(fn(pair) { pair.1 })
      use attrs <- result.try(
        list.try_fold(values, attrs, fn(attrs, value) {
          list.try_map(attrs, map_attr(_, value, inner.handle_regexp))
        }),
      )
      Ok(V(..vxml, attrs: attrs))
    }
    _ -> Ok(vxml)
  }
}

fn map_attr(
  attr: Attr,
  value: String,
  handle_regexp: Regexp,
) -> Result(Attr, DesugaringError) {
  case attr.key {
    "handle" ->
      case regexp.scan(handle_regexp, attr.val) {
        [Match(_, [Some(_)]), ..] ->
          Ok(
            Attr(
              ..attr,
              val: attr.val <> " " <> handle_syntax.encode_value(value),
            ),
          )
        [Match(_, [Some(_), _]), ..] -> Ok(attr)
        _ -> Error(malformed_handle_error(attr))
      }
    _ -> Ok(attr)
  }
}

fn malformed_handle_error(attr: Attr) -> DesugaringError {
  DesugaringError(
    attr.blame,
    "handle attr must have form <name> or <name> <<value>>; found: “"
      <> attr.val
      <> "”",
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [
        #("Chapter", "first value"),
        #("Section", "section value"),
        #("Chapter", "ignored second value"),
      ],
      source: "
                  <> root
                    <> Chapter
                      handle=chapter
                      <> Section
                        handle=section
                    <> Chapter
                      handle=existing <<original value>>
                    <> Other
                      handle=untouched
                ",
      expected: "
                  <> root
                    <> Chapter
                      handle=chapter <<first value>>
                      <> Section
                        handle=section <<section value>>
                    <> Chapter
                      handle=existing <<original value>>
                    <> Other
                      handle=untouched
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
