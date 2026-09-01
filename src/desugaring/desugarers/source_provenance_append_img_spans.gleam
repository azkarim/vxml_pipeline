import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import filepath
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import on
import vxml.{type Attr, type VXML, Line, T, V}
import vxml/blame.{type Blame} as bl

pub const name = "source_provenance_append_img_spans"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends configured sibling spans containing image source
/// paths, including an optional path inherited from an
/// ancestor attribute.
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
    // Prefix joined to image source paths. A relative prefix
    // is relative to the process that consumes the paths,
    // normally from the project root.
    String,
    // Attribute containing an original image source path.
    String,
    // Tags from which the original-path attr is inherited.
    List(String),
    // Attributes for the outer sibling span.
    List(#(String, String)),
    // Attributes for each nested path span.
    List(#(String, String)),
  )

type InnerParam {
  InnerParam(
    source_path_prefix: String,
    original_path_key: String,
    original_path_tags: List(String),
    outer_span_attrs: List(Attr),
    path_span_attrs: List(Attr),
  )
}

type State =
  Option(String)

const b = bl.Des([], name, 47)

const br = V(b, "br", [], [])

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(
    source_path_prefix: param.0,
    original_path_key: param.1,
    original_path_tags: param.2,
    outer_span_attrs: core.string_pairs_to_attrs(param.3, b),
    path_span_attrs: core.string_pairs_to_attrs(param.4, b),
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToManyEnterExitStatefulNodemap(State) =
    n2t.OneToManyEnterExitStatefulNodemap(
      on_enter: fn(vxml, state) { v_before(vxml, state, inner) },
      on_exit: fn(vxml, original_state, latest_state) {
        v_after(vxml, inner, original_state, latest_state)
      },
      on_text: fn(vxml, _) { Ok(#([vxml], None)) },
    )
  nodemap
  |> n2t.one_to_many_enter_exit_stateful_nodemap_2_desugarer_transform(None)
}

fn v_before(
  vxml: VXML,
  state: State,
  inner: InnerParam,
) -> Result(#(VXML, State), DesugaringError) {
  let assert V(blame, tag, _, _) = vxml
  use <- on.false_true(list.contains(inner.original_path_tags, tag), fn() {
    Ok(#(vxml, state))
  })
  case core.v_first_attr_with_key(vxml, inner.original_path_key), state {
    None, _ -> Ok(#(vxml, state))
    Some(attr), None -> {
      use path <- on.ok(compose_and_simplify_path(attr.blame, attr.val, inner))
      Ok(#(vxml, Some(path)))
    }
    Some(_), Some(_) -> {
      Error(DesugaringError(
        blame,
        "descendant attempting to overwrite ancestor '"
          <> inner.original_path_key
          <> "' attribute",
      ))
    }
  }
}

fn compose_and_simplify_path(
  blame: Blame,
  path: String,
  inner: InnerParam,
) -> Result(String, DesugaringError) {
  filepath.expand(inner.source_path_prefix <> path)
  |> result.map_error(fn(_) {
    DesugaringError(
      blame,
      "path '" <> path <> "' points outside the root directory",
    )
  })
}

fn v_after(
  vxml: VXML,
  inner: InnerParam,
  original_state: State,
  latest_state: State,
) -> Result(#(List(VXML), State), DesugaringError) {
  let assert V(blame, tag, attrs, _) = vxml
  use <- on.false_true(tag == "img", fn() { Ok(#([vxml], original_state)) })
  use attr <- on.none_some(core.attrs_first_with_key(attrs, "src"), fn() {
    Error(DesugaringError(
      blame,
      "img element is missing its required 'src' attribute",
    ))
  })
  use src <- on.ok(compose_and_simplify_path(attr.blame, attr.val, inner))
  let children = case latest_state {
    None -> [path_span(src, inner)]
    Some(original_src) -> [
      path_span(original_src, inner),
      br,
      path_span(src, inner),
    ]
  }
  let outer_span = V(b, "span", inner.outer_span_attrs, children)
  Ok(#([vxml, outer_span], original_state))
}

fn path_span(path: String, inner: InnerParam) -> VXML {
  V(b, "span", inner.path_span_attrs, [T(b, [Line(b, path)])])
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #(
        "./public/",
        "original",
        ["img", "figure", "Carousel"],
        [#("class", "t-3003 t-3003-i")],
        [#("class", "t-3003-i-url")],
      ),
      source: "
                          <> root
                            <> img
                              src=img/hello.svg
                ",
      expected: "
                          <> root
                            <> img
                              src=img/hello.svg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  'public/img/hello.svg'
                ",
    ),
    testing.data(
      param: #(
        "./assets/",
        "original",
        ["img", "figure", "Carousel"],
        [#("class", "t-3003 t-3003-i")],
        [#("class", "t-3003-i-url")],
      ),
      source: "
                          <> root
                            <> img
                              src=img/compressed.jpg
                              original=../img/original.jpg
                ",
      expected: "
                          <> root
                            <> img
                              src=img/compressed.jpg
                              original=../img/original.jpg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  'img/original.jpg'
                              <> br
                              <> span
                                class=t-3003-i-url
                                <>
                                  'assets/img/compressed.jpg'
                ",
    ),
    testing.data(
      param: #(
        "/media/",
        "original",
        ["img", "figure", "Carousel"],
        [#("class", "t-3003 t-3003-i")],
        [#("class", "t-3003-i-url")],
      ),
      source: "
                          <> root
                            <> figure
                              original=photos/fullsize.png
                              <> img
                                src=photos/thumb.png
                ",
      expected: "
                          <> root
                            <> figure
                              original=photos/fullsize.png
                              <> img
                                src=photos/thumb.png
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    '/media/photos/fullsize.png'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    '/media/photos/thumb.png'
                ",
    ),
    testing.data(
      param: #(
        "./static/",
        "original",
        ["img", "figure", "Carousel"],
        [#("class", "t-3003 t-3003-i")],
        [#("class", "t-3003-i-url")],
      ),
      source: "
                          <> root
                            <> Carousel
                              original=carousel/slide-hq.webp
                              <> img
                                src=carousel/slide.webp
                ",
      expected: "
                          <> root
                            <> Carousel
                              original=carousel/slide-hq.webp
                              <> img
                                src=carousel/slide.webp
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'static/carousel/slide-hq.webp'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'static/carousel/slide.webp'
                ",
    ),
    testing.data(
      param: #(
        "./public/",
        "original",
        ["img", "figure", "Carousel"],
        [#("class", "t-3003 t-3003-i")],
        [#("class", "t-3003-i-url")],
      ),
      source: "
                          <> root
                            <> img
                              src=img/logo.svg
                            <> img
                              src=img/banner.jpg
                              original=img/banner-original.jpg
                            <> figure
                              original=img/photo-hires.png
                              <> img
                                src=img/photo.png
                ",
      expected: "
                          <> root
                            <> img
                              src=img/logo.svg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  'public/img/logo.svg'
                            <> img
                              src=img/banner.jpg
                              original=img/banner-original.jpg
                            <> span
                              class=t-3003 t-3003-i
                              <> span
                                class=t-3003-i-url
                                <>
                                  'public/img/banner-original.jpg'
                              <> br
                              <> span
                                class=t-3003-i-url
                                <>
                                  'public/img/banner.jpg'
                            <> figure
                              original=img/photo-hires.png
                              <> img
                                src=img/photo.png
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/img/photo-hires.png'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/img/photo.png'
                ",
    ),
    testing.data(
      param: #(
        "./public/",
        "original",
        ["img", "figure", "Carousel"],
        [#("class", "t-3003 t-3003-i")],
        [#("class", "t-3003-i-url")],
      ),
      source: "
                          <> root
                            <> figure
                              original=diagrams/chart-hires.svg
                              <> img
                                src=diagrams/chart.svg
                            <> Carousel
                              original=gallery/slide-full.jpg
                              <> img
                                src=gallery/slide-thumb.jpg
                ",
      expected: "
                          <> root
                            <> figure
                              original=diagrams/chart-hires.svg
                              <> img
                                src=diagrams/chart.svg
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/diagrams/chart-hires.svg'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/diagrams/chart.svg'
                            <> Carousel
                              original=gallery/slide-full.jpg
                              <> img
                                src=gallery/slide-thumb.jpg
                              <> span
                                class=t-3003 t-3003-i
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/gallery/slide-full.jpg'
                                <> br
                                <> span
                                  class=t-3003-i-url
                                  <>
                                    'public/gallery/slide-thumb.jpg'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
