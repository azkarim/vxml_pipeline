import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string.{inspect as ins}
import vxml.{type VXML, Attr, T, V}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

fn inner_param_to_transform() -> DesugarerTransform {
  fn(vxml) {
    let nodemap: n2t.OneToOneStatefulNodemap(State) = nodemap
    let transform =
      n2t.one_to_one_stateful_nodemap_2_desugarer_transform(
        nodemap,
        State(0, collect_ids(vxml, set.new())),
      )
    transform(vxml)
  }
}

fn collect_ids(vxml: VXML, ids: Set(String)) -> Set(String) {
  case vxml {
    T(_, _) -> ids
    V(_, _, attrs, children) -> {
      let ids = case core.attrs_first_with_key(attrs, "id") {
        Some(id) -> set.insert(ids, id.val)
        None -> ids
      }
      list.fold(children, ids, fn(ids, child) { collect_ids(child, ids) })
    }
  }
}

fn nodemap(
  node: VXML,
  state: State,
) -> Result(#(VXML, State), DesugaringError) {
  case node {
    T(_, _) -> Ok(#(node, state))

    V(_, _, attrs, _) -> {
      case list.any(attrs, fn(attr) { attr.key == "handle" }) {
        True -> Ok(ensure_has_id_attr(node, state))
        False -> Ok(#(node, state))
      }
    }
  }
}

fn next_unused_id(state: State) -> #(String, State) {
  let counter = state.counter + 1
  let id = "_" <> ins(counter) <> "_h.a.i_"
  case set.contains(state.ids, id) {
    True -> next_unused_id(State(..state, counter: counter))
    False -> #(id, State(counter, set.insert(state.ids, id)))
  }
}

fn ensure_has_id_attr(vxml: VXML, state: State) -> #(VXML, State) {
  let assert V(_, _, _, _) = vxml
  case core.v_first_attr_with_key(vxml, "id") {
    Some(_) -> #(vxml, state)
    None -> {
      let #(id, state) = next_unused_id(state)
      let attrs = list.append(vxml.attrs, [Attr(vxml.blame, "id", id)])
      #(V(..vxml, attrs: attrs), state)
    }
  }
}

type State {
  State(counter: Int, ids: Set(String))
}

pub const name = "writerly_handles_add_ids"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Adds a unique `id` attr to each element carrying an
/// exact `handle` attr, unless the element already has an id.
/// Generated ids avoid every existing id in the document.
/// The handle value is left untouched and is not validated.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
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
          <> Existing
            id=_1_h.a.i_
          <> Section
            handle=section:name
          <> ExistingHandle
            handle=existing
            id=_3_h.a.i_
          <> Chapter
            handle=chapter:name
      ",
      expected: "
        <> root
          <> Existing
            id=_1_h.a.i_
          <> Section
            handle=section:name
            id=_2_h.a.i_
          <> ExistingHandle
            handle=existing
            id=_3_h.a.i_
          <> Chapter
            handle=chapter:name
            id=_4_h.a.i_
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
    testing.data_no_param(
      source: "
        <> root
          <> Section
            handle=unvalidated payload
          <> Aside
            handleStyle=not-a-handle
      ",
      expected: "
        <> root
          <> Section
            handle=unvalidated payload
            id=_1_h.a.i_
          <> Aside
            handleStyle=not-a-handle
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
