#!/bin/bash

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/use/alerting/notifications/channels/slack.adoc

sed -i 's/describes why the notification was closed.*$/describes why the notification was closed.\n\n\.A Slack message with its thread for a closed notification\nimage::k8s\/notifications-slack-message-example.png[Slack thread example,75%]/' "$f"