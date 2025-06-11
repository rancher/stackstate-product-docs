#!/bin/bash

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/configure/health/debug-health-sync.adoc

sed -i 's|xref:/configure/health/send-health-data\[|xref:/configure/health/send-health-data/send-health-data.adoc[|' "$f"
sed -i 's|xref:/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en|xref:|' "$f"
