#!/bin/bash

ELASTICSEARCH_LOGS=0
ELASTICSEARCH_RANGE="7d"
while getopts "her:" option; do
  case $option in
     h) # show Help
      cat <<EOF
SUSE Observability support package collector.
Fetches details of a SUSE Observability instance for troubleshooting.

Usage: $0 [options] [<namespace>]

options:
  -h  Print this help
  -e  Fetch logs for suse-observability pods from Elasticsearch
  -r  Time range for logs to fetch from Elasticsearch,
      when not specified "7d" is used

<namespace>:
  The namespace that is running SUSE Observability, or
  "suse-observability" when not specified
EOF
      exit 0;;
     e) # Collect elasticsearch logs
      ELASTICSEARCH_LOGS=1;;
     r) # Time range for elasticsearch logs
      ELASTICSEARCH_RANGE=$OPTARG;;
    \?) # Invalid option
      echo "ERROR: Invalid option"
      exit 1;;
  esac
done
shift $(($OPTIND - 1))

# Namespace to collect information
NAMESPACE=${1:-suse-observability}

# Check if commands are installed or not
COMMANDS=("kubectl" "tar")
if [ $ELASTICSEARCH_LOGS ]; then
  COMMANDS+=("curl" "jq")
fi
for cmd in ${COMMANDS[@]}; do
  if ! command -v $cmd &>/dev/null; then
     echo "$cmd is not installed. Please install it and try again."
     exit 1
  fi
done

# skip helm release analysis when not all its dependencies are present
HELM_RELEASES=1
for cmd in base64 gzip jq
do
  if ! command -v $cmd &>/dev/null; then
     echo "$cmd is not installed. Skipping analysis of helm releases."
     HELM_RELEASES=0
  fi
done

# Check if KUBECONFIG is set
if [[ -z "$KUBECONFIG" || ! -f "$KUBECONFIG" ]]; then
    echo "Error: KUBECONFIG is not set. Please ensure KUBECONFIG is set to the path of a valid kubeconfig file before running this script."
    echo "If kubeconfig is not set, use the command: export KUBECONFIG=PATH-TO-YOUR/kubeconfig. Exiting..."
 exit 1
fi

# Check if namespace exist or not
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Namespace '$NAMESPACE' does not exist. Exiting."
    exit 1
fi
# Directory to store logs
OUTPUT_DIR="${NAMESPACE}_logs_$(date +%Y%m%d%H%M%S)"
ARCHIVE_FILE="${OUTPUT_DIR}.tar.gz"

techo() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a $OUTPUT_DIR/collector-output.log
}

# Function to collect yaml
collect_yaml_configs() {
    techo "Collecting YAML configurations..."

    mkdir -p "$OUTPUT_DIR/yaml"
    
    # Pods YAMLs
    kubectl -n "$NAMESPACE" get pod -o yaml> "$OUTPUT_DIR/yaml/pods.yaml"
    # StatefulSet YAMLs
    kubectl -n "$NAMESPACE" get statefulsets -o yaml > "$OUTPUT_DIR/yaml/statefulsets.yaml"
    # DaemonSet YAMLs
    kubectl -n "$NAMESPACE" get daemonsets -o yaml > "$OUTPUT_DIR/yaml/daemonsets.yaml"
    # Service YAMLs
    kubectl -n "$NAMESPACE" get services -o yaml > "$OUTPUT_DIR/yaml/services.yaml"
    # Deployment YAMLs
    kubectl -n "$NAMESPACE" get deployments -o yaml > "$OUTPUT_DIR/yaml/deployments.yaml"
    # ConfigMap YAMLs
    kubectl -n "$NAMESPACE" get configmaps -o yaml > "$OUTPUT_DIR/yaml/configmaps.yaml"
    # Cronjob YAMLs
    kubectl -n "$NAMESPACE" get cronjob -o yaml > "$OUTPUT_DIR/yaml/cronjob.yaml"
    # PV,PVC YAML
    kubectl -n "$NAMESPACE" get pv,pvc -o yaml  > "$OUTPUT_DIR/yaml/pv-pvc.yaml"
}

# Function to collect pod logs
collect_pod_logs() {
    techo "Collecting pod logs..."
    PODS=$(kubectl -n "$NAMESPACE" get pods -o jsonpath="{.items[*].metadata.name}")
    for pod in $PODS; do
        mkdir -p "$OUTPUT_DIR/pods/$pod"
        CONTAINERS=$(kubectl -n "$NAMESPACE" get pod "$pod" -o jsonpath="{.spec.containers[*].name}")
        for container in $CONTAINERS; do
            kubectl -n "$NAMESPACE" logs "$pod" -c "$container" > "$OUTPUT_DIR/pods/$pod/${container}.log" 2>&1
            kubectl -n "$NAMESPACE" logs "$pod" -c "$container" --previous > "$OUTPUT_DIR/pods/$pod/${container}_previous.log" 2>/dev/null
        done
    done
 }

# Function to collect pod disk usage
collect_pod_disk_usage() {
    techo "Collecting pod disk usage..."
    PODS=$(kubectl -n "$NAMESPACE" get pods -o jsonpath="{.items[*].metadata.name}")
    for pod in $PODS; do
        mkdir -p "$OUTPUT_DIR/pods/$pod"
        kubectl -n "$NAMESPACE" exec -it "$pod" -- df -h > "$OUTPUT_DIR/pods/$pod/disk-usage" 2>/dev/null
    done
 }

# Function to collect details on helm releases
collect_helm_releases() {
    techo "Collecting helm releases..."
    mkdir -p "$OUTPUT_DIR/releases"
    RELEASES=$(kubectl -n "$NAMESPACE" get secrets -l owner=helm -o jsonpath="{.items[*].metadata.name}")
    for release in $RELEASES; do
        kubectl -n "$NAMESPACE" get secret "$release" -o jsonpath='{.data.release}' | \
          base64 --decode | base64 --decode | gzip -d | \
          jq '{ info: .info, metadata: .chart.metadata, config: .config }' > "$OUTPUT_DIR/releases/$release"
    done
}

collect_pod_logs_from_elasticsearch() {
    techo "Collecting logs from elasticsearch..."
    SERVICE=$(kubectl -n "$NAMESPACE" get service -l app.kubernetes.io/name=elasticsearch -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ "$SERVICE" == "" ]; then
      techo "ERROR: No elasticsearch service found"
      return
    fi

    kubectl -n "$NAMESPACE" port-forward "service/$SERVICE" 9200 > /dev/null 2>&1 &
    CHILD=$!

    CONNECTED=0
    for _ in {1..10}; do
      curl --fail "http://localhost:9200/_cat/health" > /dev/null 2>&1
      CONNECTED=$?
      if [ $CONNECTED == 0 ]; then
        break;
      fi
      sleep 1
    done
    if [ $CONNECTED != 0 ]; then
      techo "ERROR: Unable to port-forward elasticsearch service '$SERVICE' port 9200"
      kill $CHILD
      return
    fi

    RANGE_START="now-${ELASTICSEARCH_RANGE}"
    PODS=($(curl --silent -XPOST --header 'Content-Type: application/json' "http://localhost:9200/sts_k8s_logs/_search" -d @- <<EOF | jq -r '.aggregations.pod_name.buckets[].key'
{
  "query": {
    "bool": {
      "must": [ {
        "range": {
          "@timestamp": {
            "gt": "${RANGE_START}"
          }
        }
      }, {
        "bool": {
          "should": [ {
            "wildcard": {
              "resource.pod_name": "*suse-observability*"
            }
          }, {
            "wildcard": {
              "resource.pod_name": "*hbase*"
            }
          } ]
        }
      } ]
    }
  },
  "size": 0,
  "aggs": {
    "pod_name": {
      "terms": {
        "field": "resource.pod_name",
        "size": 200
      }
    }
  }
}
EOF
))
    TEMP=$(mktemp)
    techo "Found ${#PODS[@]} pods"
    for pod in ${PODS[@]}; do
      mkdir -p "$OUTPUT_DIR/pods/$pod"
      echo -n "$pod"
      from=$RANGE_START
      while [ "$from" != "" ]; do
        echo -n "."
        curl --silent -XPOST --header 'Content-Type: application/json' "http://localhost:9200/sts_k8s_logs/_search" -d @- <<EOF > $TEMP
{
  "query": {
    "bool": {
      "must": [ {
        "term": {
          "resource.pod_name": "$pod"
        }
      }, {
        "range": {
          "@timestamp": {
            "gt": "${from}"
          }
        }
      } ]
    }
  },
  "sort": [ {
    "@timestamp": "asc"
  } ],
  "size": 1000
}
EOF
        ts=$(jq -r '.hits.hits[-1].sort[0]' $TEMP)
        if [ "$ts" != "null" ]; then
          from=$(($ts / 1000000))
        else
          from=""
        fi
        jq -r '.hits.hits[]._source.message' $TEMP >> "$OUTPUT_DIR/pods/$pod/collected-logs"
      done
      echo " done"
    done
    unlink $TEMP
    kill $CHILD
}

archive_and_cleanup() {
    echo "Creating archive $ARCHIVE_FILE..."
    tar -czf "$ARCHIVE_FILE" "$OUTPUT_DIR"
    echo "Archive created."

    echo "Cleaning up the output directory..."
    rm -rf "$OUTPUT_DIR"
    echo "Output directory removed."
}

trap "exit" INT TERM
trap "kill 0" EXIT

echo "Collecting data in ${OUTPUT_DIR}"
mkdir -p "$OUTPUT_DIR"

techo "Collecting node details..."
kubectl get nodes -o wide > "$OUTPUT_DIR/nodes_status"
kubectl describe nodes > "$OUTPUT_DIR/nodes_describe"

# Collect general pod statuses
techo "Collecting pod statuses..."
kubectl -n "$NAMESPACE" get pods -o wide > "$OUTPUT_DIR/pods_status"

# Collect StatefulSets information
techo "Collecting StatefulSets information..."
kubectl -n "$NAMESPACE" get statefulsets -o wide > "$OUTPUT_DIR/statefulsets"
kubectl -n "$NAMESPACE" describe statefulsets > "$OUTPUT_DIR/statefulsets_describe"

# Collect DaemonSets information
techo "Collecting DaemonSets information..."
kubectl -n "$NAMESPACE" get daemonsets -o wide > "$OUTPUT_DIR/daemonsets"
kubectl -n "$NAMESPACE" describe daemonsets > "$OUTPUT_DIR/daemonsets_describe"

techo "Collecting Deployments information..."
kubectl -n "$NAMESPACE" get deployments -o wide > "$OUTPUT_DIR/deployments"

techo "Collecting services information..."
kubectl -n "$NAMESPACE" get services -o wide > "$OUTPUT_DIR/services"

techo "Collecting information about configmaps and secrets..."
kubectl -n "$NAMESPACE" get configmaps -o wide > "$OUTPUT_DIR/configmaps"
kubectl -n "$NAMESPACE" get secrets -o wide > "$OUTPUT_DIR/secrets"

techo "Collecting cronjob information..."
kubectl -n "$NAMESPACE" get cronjob -o wide > "$OUTPUT_DIR/cronjob"

techo "Collecting PV and PVC information"
kubectl -n "$NAMESPACE" get pv,pvc -o wide > "$OUTPUT_DIR/pv-pvc"

techo "Collecting events in $NAMESPACE ..."
kubectl -n "$NAMESPACE" get events --sort-by='.metadata.creationTimestamp' > "$OUTPUT_DIR/events"

# Run the pod logs collection function
collect_pod_logs
collect_pod_disk_usage
collect_yaml_configs
if [ $HELM_RELEASES ]; then
  collect_helm_releases
fi
if [ $ELASTICSEARCH_LOGS ]; then
  collect_pod_logs_from_elasticsearch
fi

archive_and_cleanup
echo "All information collected in the $ARCHIVE_FILE"
