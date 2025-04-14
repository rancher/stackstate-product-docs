#!/bin/bash

f=$1

if [ -z "$f" ]; then
    echo "Usage: code.sh <file>"
    exit 1
fi

sed -i '/{% endcode %}/d' "$f"

perl -i -pe 's/(?:{% code title=")(?<title>.+?)"(?:.+\n)/.$+{title}/gm' "$f"

sed -i '/{% code.* %}/d' "$f"