#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/check_antora_file_errors.sh <log-file> <file1.adoc> [file2.adoc ...]

Description:
  Checks Antora/Asciidoctor ERROR and WARN entries in <log-file> for the provided AsciiDoc files.
  <log-file> must be the first parameter ($1).
  The list of files to check starts at the second parameter ($2 onwards).

Example:
  scripts/check_antora_file_errors.sh tmp/build.log docs/latest/modules/en/pages/test.adoc docs/latest/modules/de/pages/setup/otel/collector.adoc
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

log_file="$1"
shift

if [[ ! -f "$log_file" ]]; then
  echo "Error: log file not found: $log_file" >&2
  exit 1
fi

targets_joined=""
for target in "$@"; do
  targets_joined+="${target}"$'\034'
done

awk_cmd="awk"
case "$(uname -s)" in
  Darwin)
    awk_cmd="gawk"
    ;;
  Linux)
    awk_cmd="awk"
    ;;
esac

if ! command -v "$awk_cmd" >/dev/null 2>&1; then
  echo "Error: required command '$awk_cmd' not found in PATH." >&2
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "Tip: install gawk on macOS with: brew install gawk" >&2
  fi
  exit 1
fi

# One pass through the log: capture each diagnostic header, then match it
# when the subsequent indented file line appears.
"$awk_cmd" -v targets="$targets_joined" '
BEGIN {
  target_count = split(targets, raw_targets, "\034")
  for (i = 1; i <= target_count; i++) {
    if (raw_targets[i] == "") {
      continue
    }
    requested[++requested_count] = raw_targets[i]
  }
}

function basename(path, out) {
  out = path
  sub(/^.*\//, "", out)
  return out
}

function request_key_for_path(path, i, req, req_base, path_base) {
  path_base = basename(path)

  for (i = 1; i <= requested_count; i++) {
    req = requested[i]
    req_base = basename(req)

    if (path == req) {
      return req
    }

    # If user passed just a filename, match by basename.
    if (req !~ /\// && path_base == req) {
      return req
    }

    # If user passed a relative path, match the full suffix.
    if (req ~ /\// && path ~ ("/" req "$") ) {
      return req
    }
  }

  return ""
}

/^\[[0-9:.]+\] [A-Z]+ \([^)]+\): / {
  header = $0
  next
}

/^    file: / {
  include_header = 0
  if (header ~ /\] (ERROR|WARN) \(/) {
    include_header = 1
  } else if (header ~ /\] INFO \(asciidoctor\): possible invalid reference:/) {
    include_header = 1
  }

  if (!include_header) {
    next
  }

  file_path = $0
  sub(/^    file: /, "", file_path)

  key = request_key_for_path(file_path)
  if (key == "") {
    next
  }

  if (!(key in seen_section)) {
    seen_section[key] = 1
    print "== " key " =="
  }

  print header
  print "    file: " file_path
  print ""

  match_count[key]++
  total++
}

END {
  if (total == 0) {
    print "No ERROR/WARN entries found for requested files."
    exit 0
  }

  print "Summary:"
  for (i = 1; i <= requested_count; i++) {
    req = requested[i]
    count = match_count[req] + 0
    print "  " req ": " count " issue(s)"
  }
}
' "$log_file"