import gleam/list
import gleam/option.{type Option, None, Some}
import on
import vxml.{type Attr, type VXML, V}
import vxml/blame as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "expand_emmet_like_attribute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Expands an Emmet-like shorthand attribute into a leading
/// value attribute plus HTML `id`, `class`, and `style` attrs.
/// At most one of the configured shorthand keys may be present.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(List(String), List(String), String)

type InnerParam {
  InnerParam(
    target_tags: List(String),
    shorthand_attribute_keys: List(String),
    leading_value_attribute_key: String,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(target_tags, shorthand_attribute_keys, leading_value_attribute_key) =
    param
  use <- on.false_true(shorthand_attribute_keys != [], fn() {
    Error(DesugaringError(
      bl.no_blame,
      "shorthand attribute keys cannot be empty",
    ))
  })
  use <- on.false_true(
    option.is_none(core.get_duplicate(shorthand_attribute_keys)),
    fn() {
      Error(DesugaringError(bl.no_blame, "duplicate shorthand attribute key"))
    },
  )
  use _ <- on.ok(list.try_each(shorthand_attribute_keys, validate_attribute_key))
  use _ <- on.ok(validate_attribute_key(leading_value_attribute_key))
  Ok(InnerParam(
    target_tags: target_tags,
    shorthand_attribute_keys: shorthand_attribute_keys,
    leading_value_attribute_key: leading_value_attribute_key,
  ))
}

fn validate_attribute_key(key: String) -> Result(Nil, DesugaringError) {
  case vxml.validate_key(key) {
    Ok(_) -> Ok(Nil)
    Error(_) ->
      Error(DesugaringError(
        bl.no_blame,
        "invalid VXML attribute key: '" <> key <> "'",
      ))
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  nodemap |> n2t.one_to_one_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, _) -> {
      case inner.target_tags == [] || list.contains(inner.target_tags, tag) {
        False -> Ok(vxml)
        True -> {
          let #(shorthand_attrs, attrs) =
            list.partition(attrs, fn(attr) {
              list.contains(inner.shorthand_attribute_keys, attr.key)
            })
          use shorthand <- on.ok(case shorthand_attrs {
            [] -> Ok(None)
            [one] -> Ok(Some(one))
            [_, second, ..] ->
              Error(DesugaringError(
                second.blame,
                "multiple Emmet-like shorthand attributes on one element",
              ))
          })
          use shorthand <- on.none_some(shorthand, fn() { Ok(vxml) })
          use #(leading_value, id, class, style) <- on.error_ok(
            core.html_info_shorthand_to_attrs(shorthand.blame, shorthand.val),
            fn(message) { Error(DesugaringError(shorthand.blame, message)) },
          )
          let leading_value =
            leading_value
            |> option.map(fn(attr) {
              vxml.Attr(..attr, key: inner.leading_value_attribute_key)
            })
          use attrs <- on.ok(merge_expanded_attrs(
            blame,
            attrs,
            leading_value,
            id,
            class,
            style,
            inner.leading_value_attribute_key,
          ))
          Ok(V(..vxml, attrs: attrs))
        }
      }
    }
    _ -> Ok(vxml)
  }
}

fn merge_expanded_attrs(
  blame: bl.Blame,
  attrs: List(Attr),
  leading_value: Option(Attr),
  id: Option(Attr),
  class: Option(Attr),
  style: Option(Attr),
  leading_value_attribute_key: String,
) -> Result(List(Attr), DesugaringError) {
  let mergeable = [id, class, style] |> option.values
  let attrs = case mergeable {
    [] -> attrs
    _ -> core.merge_attrs(list.append(attrs, mergeable))
  }
  case leading_value {
    None -> Ok(attrs)
    Some(leading_value) ->
      case core.attrs_first_with_key(attrs, leading_value_attribute_key) {
        None -> Ok([leading_value, ..attrs])
        Some(existing) if existing.val == leading_value.val -> Ok(attrs)
        Some(_) ->
          Error(DesugaringError(
            blame,
            "duplicate '"
              <> leading_value_attribute_key
              <> "' via shorthand and pre-existing attribute",
          ))
      }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  let param = #(
    ["pre"],
    ["WriterlyCodeBlockInfoStringPrefix", "info"],
    "language",
  )
  [
    testing.data(
      param: param,
      source: "
                <> root
                  <> pre
                    WriterlyCodeBlockInfoStringPrefix=python.listing#bob.background-color:taupe
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
      param: param,
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
      param: #(["pre"], ["annotation"], "dialect"),
      source: "
                <> root
                  <> pre
                    annotation=gleam.example
                ",
      expected: "
                <> root
                  <> pre
                    dialect=gleam
                    class=example
                ",
    ),
    testing.data(
      param: #([], ["annotation"], "dialect"),
      source: "
                <> root
                  <> AnyTag
                    annotation=gleam.example
                ",
      expected: "
                <> root
                  <> AnyTag
                    dialect=gleam
                    class=example
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
