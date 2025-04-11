#!/bin/bash

f=$1

if [ -z "$f" ]; then
    echo "Usage: img_path.sh <file>"
    exit 1
fi

sed -i 's|image::/\.gitbook/assets/|image::|g' "$f"
sed -i 's|image:/\.gitbook/assets/|image::|g' "$f"
sed -i 's|image::\.gitbook/assets/|image::|g' "$f"
sed -i 's|image::\.\./\.\./.gitbook/assets/|image::|g' "$f"
sed -i 's|image::\.\.\/\.gitbook/assets/|image::|g' "$f"
sed -i 's|image::\.\.\/\.\.\/\.gitbook/assets/|image::|g' "$f"
sed -i 's|image::\.\.\/\.\.\/\.\.\/\.gitbook/assets/|image::|g' "$f"
sed -i 's|image:\.\.\/\.\.\/\.gitbook/assets/|image::|g' "$f"