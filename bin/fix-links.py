import sys
import re
import os

debug = False


def dprint(*args, **kwargs):
    if debug:
        print(*args, **kwargs)


def fix_links(adt, root_path):
    p = r'(?P<whole_link>(?:(xref|link):)(?P<l_name>.+?)(?P<anchor_text>(\[|#).+?]))'
    matches = re.finditer(p, adt)
    for match in matches:
        dprint(f"Match starts and ends at {
            match.start()} and {match.end() - 1}")

        # whole_link = match.group('whole_link')
        link = match.group('l_name')
        anchor_text = match.group('anchor_text')

        full_path = os.path.realpath(link)
        dprint(f"full_path: {full_path}")
        dprint(f"root_path: {root_path}")
        normalised_path = re.sub(root_path, '', full_path) + anchor_text
        dprint(f"normalised_path: {normalised_path}")

        adt = adt.replace(match.group(0), f'xref:{normalised_path}')

    return adt


def main():
    if len(sys.argv) != 3:
        print("Usage: python fix-links.py input.adoc root_path")
        sys.exit(1)

    adoc_file = sys.argv[1]
    root_path = sys.argv[2]

    with open(adoc_file, 'r', encoding='utf-8') as f:
        text_in = f.read()
        f.close()

    this_dir = os.getcwd()
    try:
        dprint(f"adoc_file: {adoc_file}")
        dir_fn = os.path.dirname(adoc_file)
        dprint(f"dir_fn: {dir_fn}")
        os.chdir(dir_fn)
    except Exception:
        print("Error changing directory to adoc file location")
        sys.exit(1)

    text_out = fix_links(text_in, root_path)

    try:
        os.chdir(this_dir)
    except Exception:
        print("Error changing directory back to working directory")
        sys.exit(1)

    with open(adoc_file, 'w', encoding='utf-8') as f:
        f.write(text_out)
        f.close()


if __name__ == "__main__":
    main()
