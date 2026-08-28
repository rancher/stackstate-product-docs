#!/usr/bin/env python3
import os
import re
import sys

def check_syntax(directory="."):
    # This regex looks specifically for xref:# (intra-page xrefs)
    # It ignores xref:filename.adoc# (inter-page xrefs with anchors)
    violation_pattern = re.compile(r'xref:#')
    found_errors = False

    print(f"[INFO] (link-linter): Scanning '{directory}' for AsciiDoc link syntax violations...\n")

    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.adoc'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', encoding='utf-8') as f:
                    for line_num, line in enumerate(f, 1):
                        if violation_pattern.search(line):
                            # Formatted to mimic Antora's native GitHub Actions log output
                            print(f"[ERROR] (syntax-checker): invalid intra-page link syntax detected")
                            print(f"    file: {filepath}:{line_num}")
                            print(f"    found: {line.strip()}")
                            print(f"    fix: Use <<anchor, text>> instead of xref:#anchor[text]\n")
                            found_errors = True

    if found_errors:
        print("make: *** [link-linter] Error 1")
        print("Error: Process completed with exit code 2.")
        sys.exit(2)
    else:
        print("[INFO] (link-linter): All intra-page links use the correct <<>> syntax.")
        sys.exit(0)

if __name__ == "__main__":
    # Scan the directory passed as an argument, or default to current directory
    scan_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    check_syntax(scan_dir)