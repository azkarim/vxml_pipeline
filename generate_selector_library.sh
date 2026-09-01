#!/usr/bin/env bash
# Generates src/vxml_pipeline/selectors.gleam from the files in src/vxml_pipeline/selectors/
set -euo pipefail

SRC_DIR="src/vxml_pipeline/selectors"
OUT_FILE="src/vxml_pipeline/selectors.gleam"

# Build a newline-separated list of module names (strip '__'-prefixed and '.gleam')
MODULES=$(find "$SRC_DIR" -maxdepth 1 -type f -name '*.gleam' ! -name '__*' \
          -exec basename {} .gleam \; | sort)

# Write the file
{
  echo "//// Reusable selectors for pipeline tracking output."
  echo
  # imports
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "import vxml_pipeline/selectors/${m}"
  done
  echo

  # consts
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "pub const ${m} = ${m}.selector"
  done
} > "$OUT_FILE"

gleam format "$OUT_FILE"

echo "Wrote $OUT_FILE with $(printf '%s\n' "$MODULES" | wc -l | tr -d ' ') selector(s)."
