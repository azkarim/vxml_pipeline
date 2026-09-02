import gleam/list
import gleam/option.{None, Some}
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import on
import vxml.{type Attr, type VXML, Attr, T, V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneStatefulNodemap(Int) = fn(vxml, state) {
    nodemap(vxml, state, inner)
  }
  n2t.one_to_one_stateful_nodemap_2_desugarer_transform(nodemap, 0)
}

fn nodemap(
  node: VXML,
  counter: Int,
  inner: InnerParam,
) -> Result(#(VXML, Int), DesugaringError) {
  case node {
    T(_, _) -> Ok(#(node, counter))

    V(_, _, attrs, _) -> {
      let handle_attrs =
        attrs
        |> list.filter(fn(att) { string.starts_with(att.key, "handle") })

      use _, _ <- on.empty_nonempty(handle_attrs, fn() { Ok(#(node, counter)) })

      let assert #(V(_, _, attrs, _) as node, counter, id) =
        ensure_has_id_attr(node, counter)

      let assert True = id != ""
      let assert True = id == string.trim(id)

      use attrs <- on.ok(
        attrs
        |> list.try_map(fn(attr) {
          case attr.key == "handle" {
            False -> Ok(attr)
            True -> {
              use #(handle_name, handle_value) <- on.ok(parse_handle(
                attr,
                inner,
              ))
              Ok(
                Attr(
                  ..attr,
                  val: handle_name
                    <> " "
                    <> handle_syntax.encode_value(handle_value),
                ),
              )
            }
          }
        }),
      )

      Ok(#(V(..node, attrs: attrs), counter))
    }
  }
}

fn parse_handle(
  attr: Attr,
  inner: InnerParam,
) -> Result(#(String, String), DesugaringError) {
  case regexp.scan(inner, attr.val) {
    [regexp.Match(_, [Some(handle_name), handle_value]), ..] ->
      Ok(#(handle_name, option.unwrap(handle_value, "")))
    _ ->
      Error(DesugaringError(
        attr.blame,
        "handle attr must have form <name> <<value>>; found: “"
          <> attr.val
          <> "”",
      ))
  }
}

fn ensure_has_id_attr(vxml: VXML, counter: Int) -> #(VXML, Int, String) {
  let assert V(_, _, _, _) = vxml
  case core.v_first_attr_with_key(vxml, "id") {
    Some(attr) -> #(vxml, counter, attr.val)
    None -> {
      let counter = counter + 1
      let id = "_" <> ins(counter) <> "_h.a.i_"
      let attrs = list.append(vxml.attrs, [Attr(vxml.blame, "id", id)])
      #(V(..vxml, attrs: attrs), counter, id)
    }
  }
}

type InnerParam =
  Regexp

fn param_to_inner_param() -> InnerParam {
  let assert Ok(regexp) =
    regexp.from_string(
      "^(" <> handle_syntax.decorated_name_pattern <> ") <<(.*)>>$",
    )
  regexp
}

pub const name = "handles_add_ids"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// For each node that has an attr of key
/// 'handle':
///
/// 1. generates a unique id attr added to the
///    node, if not already present
///
/// 2. parses each 'handle' attr value in the
///    form
/// ```
/// handle=handle_name <<handle_value>>
/// ```
///    and replaces this key-value pair with
/// ```
/// handle=handle_name <<handle_value>>
/// ```
///    The id is stored only in the element's sibling
///    `id=` attribute. The value envelope preserves
///    boundary whitespace.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(param_to_inner_param()),
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
          <> Section
            handle=section:name <<value | with trailing spaces  >>
      ",
      expected: "
        <> root
          <> Section
            handle=section:name <<value | with trailing spaces  >>
            id=_1_h.a.i_
      ",
    ),
    testing.data_no_param(
      source: "
        <> root
          <> Section
            handle=section:name <<>>
            id=existing-id
      ",
      expected: "
        <> root
          <> Section
            handle=section:name <<>>
            id=existing-id
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
