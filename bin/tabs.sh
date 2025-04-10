#!/bin/bash

f=$1

if [ -z "$f" ]; then
    echo "Usage: tabs.sh <file>"
    exit 1
fi

sed -i 's/{% tabs %}/[tabs]\n====/g' $f
sed -i 's/{% endtabs %}/====/g' $f
sed -i 's/{% endtab %}/--/g' $f

sed -i 's/{% tab title="\(.*\)" %}/\1::\n+\n--/g' $f