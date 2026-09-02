# Desugarer style guide

This guide records the source conventions used by the package's reusable
desugarers. Follow it when adding a desugarer or changing an existing one.

Code organization and naming should make each desugarer's public contract,
parameter preparation, transformation, and tests readable from top to bottom.

## File organization

Use this order by default:

1. Imports.
2. `pub const name`.
3. The beach banner labeled `Desugarer`, followed by the desugarer description
   and `constructor`.
4. `Param`, `InnerParam`, and `param_to_inner_param`, in that order. Place any
   other parameter-preparation declarations alongside them as needed.
5. The implementation, ordered from callers to callees: begin with
   `inner_param_to_transform`, then the nodemap, then the helpers it calls.
6. The wave banner and assertive tests, when tests exist.

Keep tests at the bottom even when other declarations could technically follow
them.

The entire pre-test portion of the file should present logic top-down. Place
each caller before the callees it invokes, including within chains of private
implementation helpers. A reader should be able to begin at the constructor and
continue downward through progressively lower-level details.

An implementation may use a different internal order when both of these
conditions hold:

- The implementation is substantially large or complex.
- It has deliberate semantic organization expressed through section
  comments, inter-function commentary, or carefully grouped cooperating
  functions that would become less readable or riskier to review if moved.

File length alone does not justify the exception. Keep `name`, the beach
banner, description and constructor, and parameter preparation at the top when
that does not disrupt the implementation's semantic sections.

## Public parameters and private implementation types

`Param` is the public calling shape used in pipeline modules. It must be built
from generic types such as tuples, lists, options, strings, integers, and
booleans. Do not make `Param` a desugarer-specific record: doing so would force
the pipeline module to import that record and its constructor.

Use formatter-resilient comments immediately before tuple fields:

```gleam
type Param =
  #(
    // Ancestor tags.
    List(String),
    // Replacement used inside a matching ancestor.
    #(String, String),
    // Replacement used outside a matching ancestor.
    #(String, String),
  )
```

Do not use horizontally aligned column comments. `gleam format` changes tuple
layout and destroys their alignment.

Document each tuple field immediately above that field. Each comment should be
readable on its own rather than depending on horizontal alignment with other
fields.

`InnerParam` is private and should normally be a record when it contains
several semantically distinct values:

```gleam
type InnerParam {
  InnerParam(
    ancestor_tags: List(String),
    inside_from: String,
    inside_to: String,
    outside_from: String,
    outside_to: String,
  )
}
```

`param_to_inner_param` is the explicit boundary between the convenient public
calling shape and the named internal representation:

```gleam
fn param_to_inner_param(
  param: Param,
) -> Result(InnerParam, DesugaringError) {
  let #(ancestor_tags, inside, outside) = param
  let #(inside_from, inside_to) = inside
  let #(outside_from, outside_to) = outside

  Ok(InnerParam(
    ancestor_tags,
    inside_from,
    inside_to,
    outside_from,
    outside_to,
  ))
}
```

Use a type alias when `InnerParam` genuinely has the same simple meaning as
`Param`. Do not create a record merely to satisfy a rule.

## State

Private state with multiple semantic fields should normally be a record:

```gleam
type State {
  State(
    has_seen_ancestor: Bool,
    from: String,
    to: String,
  )
}
```

Prefer named access such as `state.from` over positional access such as
`state.1`. A scalar state, homogeneous collection, or self-evident pair may
remain a bare type or tuple.

## Nodemap callbacks

For enter/exit nodemaps, use the callback names established by
`nodemaps_2_transform`:

```text
on_enter
on_exit
on_text
```

Use `vxml` for a VXML argument rather than `node`. Preserve established local
conventions including `v_`, `t_`, `_val_`, and `TrafficLight`. Do not introduce
`_tag` suffixes merely to distinguish tag-related values. Keep plural grammar
correct—for example, `attrs` takes `have`, not `has`.

## Constructing the nodemap and transform

Name the function that constructs a transform from prepared parameters
`inner_param_to_transform`.

When nodemap construction is short and used only once, construct a locally
typed nodemap inside
`inner_param_to_transform`:

```gleam
fn inner_param_to_transform(
  inner: InnerParam,
) -> DesugarerTransform {
  let nodemap: n2t.OneToOneEnterExitStatefulNoErrorNodemap(State) =
    n2t.OneToOneEnterExitStatefulNoErrorNodemap(
      on_enter: fn(vxml, state) { on_enter(vxml, state, inner) },
      on_exit: on_exit,
      on_text: on_text,
    )

  let initial_state = State(
    has_seen_ancestor: False,
    from: inner.outside_from,
    to: inner.outside_to,
  )

  nodemap
  |> n2t.one_to_one_enter_exit_stateful_no_error_nodemap_2_desugarer_transform(
    initial_state,
  )
}
```

The explicit type annotation is important: it places the nodemap type beside
the corresponding `*_nodemap_2_desugarer_transform` adapter.

Keep a separate helper when constructing the nodemap involves substantial
logic, when it is reused, or when inlining would make
`inner_param_to_transform` difficult to scan.

## Constructor

The standard constructor uses `vxml_pipeline/authoring`:

```gleam
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}
```

This helper owns parameter inspection, validation-error capture, and transform
construction.

## Constructor description

Every public `constructor` should have an accurate documentation comment that
describes the desugarer's observable transformation:

- Keep descriptions concise and behavioral. Explain what the desugarer does,
  including conditions that materially delimit the transformation; do not
  narrate its internal traversal machinery.
- Write descriptions as complete sentences: begin with a capital letter and
  end with punctuation. Wrap their `///` lines to roughly 60 characters,
  including the comment prefix.
- Keep the description consistent with the implementation and tests.

## Desugarer section decoration

Each desugarer uses beach and wave section comments. The beach section starts
the public desugarer block and is labeled `Desugarer`, using this form:

```gleam
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️
```

Do not add a separate implementation banner. The caller-before-callee ordering
provides the implementation's structure without another decorated section.

Do not add replacement ruler lines.

Leave exactly one blank line after the beach banner before the constructor
description.

## Assertive tests

Keep `assertive_tests_data` and `assertive_tests` at the bottom of the file.

Use this exact wave banner, with one blank line between the banner and
`assertive_tests_data`:

```gleam
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() {
  // ...
}
```

Within every multiline `source` and `expected` VXML string, normalize the
minimum indentation of nonblank VXML lines to exactly 16 spaces. Move the block
as a whole: preserve every relative indentation level inside the VXML.

Target shape:

```gleam
source: "
                <> root
                  <> child
                    <>
                      'text'
                ",
expected: "
                <> root
                  <> renamed-child
                    <>
                      'text'
                ",
```

The test framework strips common leading indentation before parsing. The
16-space rule is solely for consistent source readability.

Incorrect normalization changes individual lines until they all have the same
indentation. Correct normalization shifts every line by the same amount so that
the least-indented nonblank VXML line begins at column 17.

Preserve fixture content, quoting, and tree structure when normalizing
indentation.

## Validation

Prefer validation owned by the defining library. For example, validate tags
with `vxml.validate_tag` when its structured error is useful. Boolean wrappers
such as `core.valid_tag` are acceptable when only a yes/no decision is needed.

Parameter validation belongs in `param_to_inner_param`; the nodemap should
normally receive prepared data.

## Review checklist

Before submitting a desugarer:

1. Keep `Param` generic and give complex private data named fields.
2. Present declarations from the public constructor down through its callees.
3. Describe the observable contract above `constructor`.
4. Use the established callback and transform-construction names.
5. Give a one-use nodemap an explicit local type annotation.
6. Use the standard beach and wave banners with their required blank lines.
7. Give multiline VXML fixtures a minimum indentation of 16 spaces.
8. Run `gleam format` and regenerate desugarer blames.
9. Run the desugarer's focused tests and the package test suite.
