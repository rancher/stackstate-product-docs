#!/usr/bin/env python3
import os
import sys
import argparse
import re

def check_orphans(antora_path, module, nav_filename):
    # Construct paths based on the exact arguments
    pages_dir = os.path.join(antora_path, 'modules', module, 'pages')
    nav_file_path = os.path.join(antora_path, nav_filename)

    # 1. Verify directories exist
    if not os.path.exists(pages_dir):
        print(f"[ERROR] Pages directory not found: {pages_dir}")
        sys.exit(1)
    if not os.path.exists(nav_file_path):
        print(f"[ERROR] Navigation file not found: {nav_file_path}")
        sys.exit(1)

    # 2. Get all .adoc files in the pages directory
    existing_pages = set()
    for root, _, files in os.walk(pages_dir):
        for file in files:
            if file.endswith('.adoc'):
                # Ignore README.adoc files
                if file.lower() == 'readme.adoc':
                    continue

                # Get the relative path from the pages directory
                rel_dir = os.path.relpath(root, pages_dir)
                if rel_dir == '.':
                    existing_pages.add(file)
                else:
                    existing_pages.add(os.path.join(rel_dir, file))

    # 3. Read the nav.adoc file and find all xrefs
    nav_references = set()
    xref_pattern = re.compile(r'xref:([^\[#]+).*?\[.*?\]')
    
    with open(nav_file_path, 'r', encoding='utf-8') as f:
        for line in f:
            matches = xref_pattern.findall(line)
            for match in matches:
                # If a module name is specified in the xref (like en:page.adoc), strip it out
                if ':' in match:
                    match = match.split(':', 1)[1]
                nav_references.add(match.strip())

    # 4. Compare the sets to find orphans
    orphans = existing_pages - nav_references

    if orphans:
        print(f"[FAIL] Found {len(orphans)} orphan page(s) not linked in the navigation menu:")
        for orphan in sorted(orphans):
            print(f"  - {orphan}")
        print("\nError: Process completed with exit code 1.")
        sys.exit(1)
    else:
        print("[SUCCESS] No orphan pages found! All pages are linked in the navigation menu.")
        sys.exit(0)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Check for orphan Antora pages.")
    parser.add_argument('-antoraPath', default='/docs', help='Path to Antora document sources')
    parser.add_argument('-module', default='ROOT', help='Module to analyze')
    parser.add_argument('-filename', default='modules/ROOT/nav.adoc', help='File to analyze')
    
    args = parser.parse_args()
    
    print(f"Scanning for orphans in module '{args.module}'...")
    check_orphans(args.antoraPath, args.module, args.filename)