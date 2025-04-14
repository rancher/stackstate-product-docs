#!/bin/bash

f=/home/jhk/projects/suse/product-docs/stackstate-product-docs/docs/next/modules/en/pages/k8s-quick-start-guide.adoc

sed -i "/^'''/d" "$f"
sed -i "/^--$/d" "$f"
sed -i "/^\[discrete\]$/d" "$f"
sed -i 's/^= Kubernetes/== Kubernetes/' "$f"
sed -i 's/^= OpenShift/== OpenShift/' "$f"
sed -i 's/^= Amazon EKS/== Amazon EKS/' "$f"
sed -i 's/^= Google GKE/== Google GKE/' "$f"
sed -i 's/^= Azure AKS/== Azure AKS/' "$f"
sed -i 's/^= KOPS/== KOPS/' "$f"
sed -i 's/^= Self-hosted/== Self-hosted/' "$f"
