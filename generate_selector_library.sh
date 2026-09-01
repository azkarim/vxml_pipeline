#!/usr/bin/env bash
# Generates src/desugaring/selectors.gleam from the files in src/desugaring/selectors/
set -euo pipefail

SRC_DIR="src/desugaring/selectors"
OUT_FILE="src/desugaring/selectors.gleam"

# Build a newline-separated list of module names (strip '__'-prefixed and '.gleam')
MODULES=$(find "$SRC_DIR" -maxdepth 1 -type f -name '*.gleam' ! -name '__*' \
          -exec basename {} .gleam \; | sort)

# Write the file
{
  # imports
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "import desugaring/selectors/${m}"
  done
  echo

  # consts
  printf '%s\n' "$MODULES" | while IFS= read -r m; do
    echo "pub const ${m} = ${m}.selector"
  done
} > "$OUT_FILE"

echo "Wrote $OUT_FILE with $(printf '%s\n' "$MODULES" | wc -l | tr -d ' ') selector(s)."
