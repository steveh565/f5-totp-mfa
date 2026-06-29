#!/bin/bash
# convert-markers.sh - Convert plain text markers to Markdown
# Usage: bash convert-markers.sh inputfile.txt outputfile.md

INPUT="$1"
OUTPUT="$2"

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: $0 inputfile.txt outputfile.md"
    exit 1
fi

cp "$INPUT" "$OUTPUT"

# Headers (with optional leading whitespace)
sed -i 's/^[[:space:]]*\[H1\] /# /' "$OUTPUT"
sed -i 's/^[[:space:]]*\[H2\] /## /' "$OUTPUT"
sed -i 's/^[[:space:]]*\[H3\] /### /' "$OUTPUT"

# Code blocks (with optional leading whitespace, preserve indentation)
sed -i 's/^[[:space:]]*\[CB\]bash$/```bash/' "$OUTPUT"
sed -i 's/^[[:space:]]*\[CB\]$/```/' "$OUTPUT"
sed -i 's/^[[:space:]]*\[CE\]$/```/' "$OUTPUT"

# Block quotes (with optional leading whitespace)
sed -i 's/^[[:space:]]*\[BQ\] /> /' "$OUTPUT"

# Checkboxes (with optional leading whitespace)
sed -i 's/^[[:space:]]*\[CK\] /- [ ] /' "$OUTPUT"

# Bold (appears anywhere on line, multiple times)
sed -i 's/\[BD\]/**/g' "$OUTPUT"

# Tables (handle multiple per line, with optional leading whitespace)
sed -i 's/^[[:space:]]*\[TB\] /| /' "$OUTPUT"
sed -i 's/ \[TB\]$/ |/' "$OUTPUT"
sed -i 's/ \[TB\] / | /g' "$OUTPUT"

# Remove blank line markers (with optional leading whitespace)
sed -i '/^[[:space:]]*\[NL\][[:space:]]*$/d' "$OUTPUT"

echo "Converted $INPUT to $OUTPUT"