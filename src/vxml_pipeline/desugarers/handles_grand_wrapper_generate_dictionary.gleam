import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Regexp, Match}
import gleam/string
import on
import vxml.{type Attr, type VXML, Attr, V}
import vxml/blame.{type Blame} as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/handle_syntax
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

fn handle_elements(state: State) -> List(VXML) {
  state.handles
  |> dict.map_values(fn(key, value) {
    let #(decorators, page, value, id, path, _) = value
    let page = case page {
      True -> "true"
      False -> "false"
    }
    V(
      desugarer_blame(24),
      "Handle",
      [
        Attr(desugarer_blame(27), "name", key),
        Attr(desugarer_blame(28), "decorators", decorators),
        Attr(desugarer_blame(29), "page", page),
        Attr(desugarer_blame(30), "value", handle_syntax.encode_value(value)),
        Attr(desugarer_blame(32), "id", id),
        Attr(desugarer_blame(33), "path", path),
      ],
      [],
    )
  })
  |> dict.values
}

fn try_read_handle(
  attr: Attr,
  inner: InnerParam,
) -> Result(#(String, String, Bool, String), DesugaringError) {
  assert attr.key == "handle"
  case regexp.scan(inner.handle_regexp, attr.val) {
    [Match(_, [Some(name), value]), ..] -> {
      let value = option.unwrap(value, "")
      let #(name, decorators) = case string.split_once(name, "#") {
        Ok(#(name, decorators)) -> #(name, "#" <> decorators)
        Error(_) -> #(name, "")
      }
      let page =
        decorators
        |> string.split("#")
        |> list.contains("page")
      Ok(#(name, decorators, page, value))
    }
    _ ->
      Error(DesugaringError(
        attr.blame,
        "handle attr not in form <name> <<value>>; found: “" <> attr.val <> "”",
      ))
  }
}

fn try_insert_handle(
  handles: HandlesDict,
  name: String,
  decorators: String,
  page: Bool,
  value: String,
  id: String,
  path: String,
  blame: Blame,
) -> Result(HandlesDict, DesugaringError) {
  case dict.get(handles, name) {
    Ok(entry) ->
      Error(DesugaringError(
        blame,
        "redefinition of '"
          <> name
          <> "' (previously defined at "
          <> bl.blame_digest(entry.5)
          <> ")",
      ))
    Error(_) ->
      Ok(
        dict.insert(handles, name, #(decorators, page, value, id, path, blame)),
      )
  }
}

fn attrs_fold(
  not_handles_acc: List(Attr),
  remaining: List(Attr),
  handles: HandlesDict,
  path: String,
  id: String,
  inner: InnerParam,
) -> Result(#(HandlesDict, List(Attr)), DesugaringError) {
  use first, rest <- on.empty_nonempty(remaining, fn() {
    Ok(#(handles, not_handles_acc |> list.reverse))
  })

  case first.key {
    "handle" -> {
      use #(name, decorators, page, value) <- on.ok(try_read_handle(
        first,
        inner,
      ))
      use handles <- on.ok(try_insert_handle(
        handles,
        name,
        decorators,
        page,
        value,
        id,
        path,
        first.blame,
      ))
      attrs_fold(not_handles_acc, rest, handles, path, id, inner)
    }

    _ -> attrs_fold([first, ..not_handles_acc], rest, handles, path, id, inner)
  }
}

fn check_no_handles(attrs: List(Attr)) -> Result(List(Nil), DesugaringError) {
  list.try_map(attrs, fn(attr) {
    case attr.key {
      "handle" -> {
        Error(DesugaringError(
          attr.blame,
          "no page path at handle '" <> attr.val <> "'",
        ))
      }
      _ -> Ok(Nil)
    }
  })
}

fn update_path(state: State, node: VXML, inner: InnerParam) -> State {
  let assert V(_, _, _, _) = node
  case core.v_first_attr_with_key(node, inner.path_key) {
    Some(Attr(_, _, value)) -> State(..state, path: Some(value))
    None -> state
  }
}

fn t_transform(
  vxml: VXML,
  state: State,
) -> Result(#(VXML, State), DesugaringError) {
  Ok(#(vxml, state))
}

fn on_enter(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(_, _, attrs, _) = vxml
  let state = update_path(state, vxml, inner)
  case state.path {
    None -> {
      use _ <- on.ok(check_no_handles(attrs))
      Ok(#(vxml, state))
    }
    Some(path) -> {
      case list.any(attrs, fn(attr) { attr.key == "handle" }) {
        False -> Ok(#(vxml, state))
        True -> {
          use id <- on.none_some(core.v_first_attr_with_key(vxml, "id"), fn() {
            Error(DesugaringError(
              vxml.blame,
              "element with a handle attr has no id attr; run handles_add_ids first",
            ))
          })
          use #(handles, attrs) <- on.ok(attrs_fold(
            [],
            attrs,
            state.handles,
            path,
            id.val,
            inner,
          ))
          Ok(#(V(..vxml, attrs: attrs), State(..state, handles: handles)))
        }
      }
    }
  }
}

fn on_exit(
  vxml: VXML,
  ancestors: List(VXML),
  original_state: State,
  state: State,
) -> Result(#(VXML, State), DesugaringError) {
  let state = State(..state, path: original_state.path)
  case ancestors {
    [] -> {
      let grand_wrapper =
        V(
          desugarer_blame(164),
          "GrandWrapper",
          [],
          list.append(handle_elements(state), [vxml]),
        )
      Ok(#(grand_wrapper, state))
    }
    _ -> Ok(#(vxml, state))
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToOneEnterExitStatefulNodemap(State) =
    n2t.FancyOneToOneEnterExitStatefulNodemap(
      on_enter: fn(vxml, _, _, _, _, state) { on_enter(vxml, state, inner) },
      on_exit: fn(vxml, ancestors, _, _, _, original_state, latest_state) {
        on_exit(vxml, ancestors, original_state, latest_state)
      },
      on_text: fn(vxml, _, _, _, _, state) { t_transform(vxml, state) },
    )
  n2t.fancy_one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(
    nodemap,
    State(dict.new(), None),
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let assert Ok(handle_regexp) =
    regexp.from_string(
      "^(" <> handle_syntax.decorated_name_pattern <> ") <<(.*)>>$",
    )
  Ok(InnerParam(path_key: param, handle_regexp: handle_regexp))
}

type HandlesDict =
  Dict(
    String,
    #(
      // Decorators copied from the definition token.
      String,
      // Whether the handle links to `#page` by default.
      Bool,
      // String value of the handle.
      String,
      // Handle id on the page.
      String,
      // Page path for the handle.
      String,
      // Blame of the handle definition.
      Blame,
    ),
  )

type State {
  State(handles: HandlesDict, path: Option(String))
}

// Key of the attribute holding the local path.
type Param =
  String

type InnerParam {
  InnerParam(path_key: String, handle_regexp: Regexp)
}

pub const name = "handles_grand_wrapper_generate_dictionary"

fn desugarer_blame(line_no: Int) {
  bl.Des([], name, line_no)
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️🏖️

/// Traverses the tree. Expects `handle` attrs to be in the form:
///
/// `handle=<name> <<value>>`
///
/// Wraps the root in `GrandWrapper` and moves handle definitions
/// into structured `Handle` children carrying `name`, `decorators`,
/// `page`, `value`, `id`, and `path` attributes. Decorators are
/// preserved without interpretation except for deriving `page`.
///
/// Leaves `id` attrs in place and does not add `id` attrs to `GrandWrapper`.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: "local_path",
      source: "
        <> root
          <> ChapterChapter
            local_path=./ch1.html
            <>
              'some text'
            <> Math
              handle=super-name <<AA| with spaces  >>
              id=_23-super-id
              <>
                '$x^2 + b^2$'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=super-name
            decorators=
            page=false
            value=<<AA| with spaces  >>
            id=_23-super-id
            path=./ch1.html
          <> root
            <> ChapterChapter
              local_path=./ch1.html
              <>
                'some text'
              <> Math
                id=_23-super-id
                <>
                  '$x^2 + b^2$'
      ",
    ),
    testing.data(
      param: "local_path",
      source: "
        <> root
          <> ChapterChapter
            local_path=./ch2.html
            <>
              'some text'
            <> Math
              handle=other-name#page <<BB>>
              id=_24-other-id
              <>
                '$y^2$'
      ",
      expected: "
        <> GrandWrapper
          <> Handle
            name=other-name
            decorators=#page
            page=true
            value=<<BB>>
            id=_24-other-id
            path=./ch2.html
          <> root
            <> ChapterChapter
              local_path=./ch2.html
              <>
                'some text'
              <> Math
                id=_24-other-id
                <>
                  '$y^2$'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
