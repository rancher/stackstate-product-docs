import sys
import re

debug = True


def dprint(*args, **kwargs):
    if debug:
        print(*args, **kwargs)


def fix_admon(adt):
    p = r'{% hint style=\"(?P<type>.*?)\" %}(?P<content>(.|\s)*?){% endhint %}'
    matches = re.finditer(p, adt)
    for match in matches:
        dprint(f"Match starts and ends at {
            match.start()} and {match.end() - 1}")
        type = match.group('type')
        content = match.group('content')

        match type:
            case 'danger':
                type = 'WARNING'
            case 'info':
                type = 'NOTE'
            case 'success':
                type = 'TIP'
            case 'success" "self-hosted info':
                type = 'TIP'
            case 'warning':
                type = 'CAUTION'

        adt = adt.replace(match.group(0), f'[{type}]\n===={content}====\n')

    return adt


def main():
    if len(sys.argv) != 2:
        print("Usage: python fix_admon.py input.adoc")
        sys.exit(1)

    ad_file = sys.argv[1]

    with open(ad_file, 'r', encoding='utf-8') as f:
        ad_in = f.read()
        f.close()

    ad_out = fix_admon(ad_in)

    with open(ad_file, 'w', encoding='utf-8') as f:
        f.write(ad_out)
        f.close()


if __name__ == "__main__":
    main()
