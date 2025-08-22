#!/bin/bash

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/cli/cli-sts.adoc

patch -f "$f" "$bdir"/cli-sts.patch

rm -f "$f".orig
rm -f "$f".rej

sed -i 's|_install_the_new_sts_cli|_install_the_sts_cli|' "$f"