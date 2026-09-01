#!/usr/bin/env bash
# Generates src/vxml_pipeline/desugarers.gleam from the files in src/vxml_pipeline/desugarers/
set -euo pipefail

SRC_DIR="src/vxml_pipeline/desugarers"
OUT_FILE="src/vxml_pipeline/desugarers.gleam"

# Build a newline-separated list of module names (strip '__'-prefixed and '.gleam')
MODULES=$(find "$SRC_DIR" -maxdepth 1 -type f -name '*.gleam' ! -name '__*' \
          -exec basename {} .gleam \; | sort)

# Write the file
{
  echo "//// Reusable desugarer constructors."
  echo
  # imports
  echo "import vxml_pipeline/testing"
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "import vxml_pipeline/desugarers/${m}"
  done
  echo

  # consts
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "pub const ${m} = ${m}.constructor"
  done
  echo

  # assertive_tests
  echo "pub const assertive_tests : List(fn() -> testing.AssertiveTestCollection) = ["
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "  ${m}.assertive_tests,"
  done
  echo "]"
} > "$OUT_FILE"

gleam format "$OUT_FILE"

echo "Wrote $OUT_FILE with $(printf '%s\n' "$MODULES" | wc -l | tr -d ' ') desugarer(s)."
