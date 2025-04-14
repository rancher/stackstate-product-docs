#!/bin/bash

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/use/alerting/notifications/channels/teams.adoc

sed -i 's/is created in the channel.*$/is created in the channel.\n\n\.Teams messages for an open and close notification\nimage::k8s\/notifications-teams-example.png[Teams example,75%]/' "$f"