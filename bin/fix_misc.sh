#!/bin/bash

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/install-stackstate/initial_run_guide.adoc
sed -i 's|xref:/setup/install-stackstate/kubernetes_openshift\[|xref:/setup/install-stackstate/kubernetes_openshift/README.adoc[|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/otel/collector.adoc
sed -i '/:doctype: book/d' "$f"
sed -i 's/^= Related resources/== Related resources/' "$f"
sed -i 's/^== HTTP Requests from the exporter are too big/=== HTTP Requests from the exporter are too big/' "$f"
sed -i 's/^= Troubleshooting/== Troubleshooting/' "$f"
sed -i 's/^=== HTTP request compression/==== HTTP request compression/' "$f"
sed -i 's/^=== Max batch size/==== Max batch size/' "$f"
sed -i 's|xref:/setup/otel/getting-started\[|xref:/setup/otel/getting-started/README.adoc[|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/upgrade-stackstate/migrate-from-6.adoc
patch -f "$f" "$bdir"/migrate-from-6.patch
rm -f "$f".orig
rm -f "$f".rej

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/upgrade-stackstate/steps-to-upgrade.adoc
sed -i 's|<<_upgrade_stackstate,|<<_upgrade_suse_observability,|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/use/alerting/k8s-add-monitors-cli.adoc
sed -i 's|<<_create_or_update_the_monitor_in_stackstate,|<<_create_or_update_the_monitor_in_suse_observability,|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/use/alerting/k8s-override-monitor-arguments.adoc
sed -i 's|<<_build_an_override_annotation,Build an override annotation|<<_how_to_build_my_annotation,How to build my annotation|' "$f"
sed -i 's|<<_what_monitor_allows_overriding,|<<_what_monitors_allow_overriding_arguments,|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/otel/getting-started/getting-started-k8s-operator.adoc
sed -i '/:doctype: book/d' "$f"
sed -i 's|^= More info|== More info|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/otel/getting-started/getting-started-k8s.adoc
sed -i '/:doctype: book/d' "$f"
sed -i 's|^= More info|== More info|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/otel/getting-started/getting-started-lambda.adoc
sed -i '/:doctype: book/d' "$f"
sed -i 's|^= More info|== More info|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/otel/getting-started/getting-started-linux.adoc
sed -i '/:doctype: book/d' "$f"
sed -i 's|^= More info|== More info|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/classic.adoc
sed -i '/:page-layout: landing/d' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/use/metrics/k8s-add-charts.adoc
sed -i 's|<<_create_or_update_the_metric_binding_in_stackstate,|<<_create_or_update_the_metric_binding_in_suse_observability,|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/install-stackstate/kubernetes_openshift/kubernetes_install.adoc
sed -i 's|#_generate_baseconfig_values\.yaml_and_sizing_values\.yaml|#_generate_baseconfig_values_yaml_and_sizing_values_yaml|g' "$f"
sed -i 's|_generate_baseconfig_values\.yaml_and_sizing_values\.yaml|_generate_baseconfig_values_yaml_and_sizing_values_yaml|g' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/install-stackstate/kubernetes_openshift/openshift_install.adoc
sed -i 's|#_generate_baseconfig_values\.yaml_and_sizing_values\.yaml|#_generate_baseconfig_values_yaml_and_sizing_values_yaml|g' "$f"
sed -i 's|_generate_baseconfig_values\.yaml_and_sizing_values\.yaml|_generate_baseconfig_values_yaml_and_sizing_values_yaml|g' "$f"
sed -i 's|#_create_openshift_values\.yaml|#_create_openshift_values_yaml|' "$f"
sed -i 's|_create_openshift_values\.yaml|_create_openshift_values_yaml|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/security/authentication/authentication_options.adoc
sed -i 's|xref:/setup/security/rbac\[RBAC|xref:/setup/security/rbac/README.adoc[RBAC|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/security/authentication/keycloak.adoc
sed -i 's|xref:/setup/security/rbac\[RBAC|xref:/setup/security/rbac/README.adoc[RBAC|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/security/authentication/ldap.adoc
sed -i 's|xref:/setup/security/rbac\[RBAC|xref:/setup/security/rbac/README.adoc[RBAC|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/security/authentication/oidc.adoc
sed -i 's|xref:/setup/security/rbac\[RBAC|xref:/setup/security/rbac/README.adoc[RBAC|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/setup/security/rbac/role_based_access_control.adoc
sed -i 's|xref:/setup/security/authentication\[How|xref:/setup/security/authentication/README.adoc[How|' "$f"

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/use/alerting/notifications/configure.adoc
sed -i 's|<<_scopes,scope>>|<<_scope,scope>>|' "$f"