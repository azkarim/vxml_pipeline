import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{None, Some}
import on
import vxml.{type VXML, V}
import writerly

pub const name = "expand_info_attribute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Expands HTML `info` shorthand into language, id, class,
/// and style attributes on the configured element tags. Writerly's
/// `WriterlyCodeBlockInfoString` encoding is accepted as an alias.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(String)

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  nodemap |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, _) -> {
      case list.contains(inner, tag) {
        False -> Ok(vxml)
        True -> {
          use #(info, attrs) <- on.ok(core.attrs_extract_unique_key_or_none(
            attrs,
            "info",
          ))
          use #(writerly_info, attrs) <- on.ok(
            core.attrs_extract_unique_key_or_none(
              attrs,
              writerly.code_block_info_string_attribute_key,
            ),
          )
          use info <- on.ok(case info, writerly_info {
            Some(_), Some(_) ->
              Error(DesugaringError(
                blame,
                "both 'info' and 'WriterlyCodeBlockInfoString' attributes",
              ))
            Some(info), None -> Ok(Some(info))
            None, Some(info) -> Ok(Some(info))
            None, None -> Ok(None)
          })
          use info <- on.none_some(info, fn() { Ok(vxml) })
          use #(language, id, class, style) <- on.error_ok(
            core.html_info_shorthand_to_attrs(info.blame, info.val),
            fn(msg) { Error(DesugaringError(blame, msg)) },
          )
          use attrs <- on.ok(case attrs {
            [] -> Ok([language, id, class, style] |> option.values)
            _ -> {
              let mergeable = [id, class, style] |> option.values
              let attrs = case mergeable {
                [] -> attrs
                _ -> core.merge_attrs(list.append(attrs, mergeable))
              }
              case language {
                None -> Ok(attrs)
                Some(language) ->
                  case core.attrs_first_with_key(attrs, "language") {
                    None -> Ok([language, ..attrs])
                    Some(x) ->
                      case x.val == language.val {
                        True -> Ok(attrs)
                        False ->
                          Error(DesugaringError(
                            blame,
                            "duplicate 'language' via info tag & pre-existing attribute",
                          ))
                      }
                  }
              }
            }
          })
          Ok(V(..vxml, attrs: attrs))
        }
      }
    }
    _ -> Ok(vxml)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: ["pre"],
      source: "
                <> root
                  <> pre
                    info=python.listing
                    <>
                      'plain code block'
                ",
      expected: "
                <> root
                  <> pre
                    language=python
                    class=listing
                    <>
                      'plain code block'
                ",
    ),
    testing.data(
      param: ["pre"],
      source: "
                <> root
                  <> pre
                    info=python.listing#bob
                    <>
                      'plain code block'
                ",
      expected: "
                <> root
                  <> pre
                    language=python
                    id=bob
                    class=listing
                    <>
                      'plain code block'
                ",
    ),
    testing.data(
      param: ["pre"],
      source: "
                <> root
                  <> pre
                    info=python.listing#bob.background-color:taupe
                    <>
                      'plain code block'
                ",
      expected: "
                <> root
                  <> pre
                    language=python
                    id=bob
                    class=listing
                    style=background-color:taupe
                    <>
                      'plain code block'
                ",
    ),
    testing.data(
      param: ["pre"],
      source: "
                <> root
                  <> pre
                    info=.listing
                    <>
                      'plain code block'
                ",
      expected: "
                <> root
                  <> pre
                    class=listing
                    <>
                      'plain code block'
                ",
    ),
    testing.data(
      param: ["pre"],
      source: "
                <> root
                  <> pre
                    WriterlyCodeBlockInfoString=python.listing
                    <>
                      'plain code block'
                ",
      expected: "
                <> root
                  <> pre
                    language=python
                    class=listing
                    <>
                      'plain code block'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
