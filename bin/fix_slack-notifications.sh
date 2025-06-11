#!/bin/bash

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/configure-stackstate/slack-notifications.adoc

sed -i 's|image:../../resources/logo/stackstate-logo.png\[SUSE Observability logo\]|image:logo/stackstate-logo.png[SUSE Observability logo,25,25]|' "$f"