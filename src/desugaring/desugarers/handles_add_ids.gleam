import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{None, Some}
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, Attr, T, V}

fn inner_param_to_transform(_: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneStatefulNodemap(Int) = nodemap
  n2t.one_to_one_stateful_nodemap_2_desugarer_transform(nodemap, 0)
}

fn nodemap(node: VXML, counter: Int) -> Result(#(VXML, Int), DesugaringError) {
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
              use #(handle_name, handle_value) <- on.ok(
                case string.split_once(attr.val |> core.normalize_spaces, " ") {
                  Ok(#(first, second)) -> {
                    case
                      string.contains(first, "|")
                      || string.contains(second, "|")
                    {
                      True ->
                        Error(DesugaringError(
                          attr.blame,
                          "handle value contains splitting charachter '|'",
                        ))
                      False -> Ok(#(first, second))
                    }
                  }
                  Error(_) -> Ok(#(attr.val, ""))
                },
              )
              Ok(
                Attr(
                  ..attr,
                  val: handle_name <> "|" <> handle_value <> "|" <> id,
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
  Nil

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
/// handle=handle_name [handle_value]
/// ```
///    where the handle_value string is an optional
///    string separated from handle_name that may or
///    may not be present, and replaces this key-value
///    pair with
/// ```
/// handle=handle_name|handle_value|id
/// ```
///    while using the empty string for 'handle_value',
///    if not present
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(Nil),
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
