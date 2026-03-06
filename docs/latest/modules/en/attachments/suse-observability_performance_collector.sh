#!/bin/bash

while getopts "h:" option; do
  case $option in
     h) # show Help
      cat <<EOF
SUSE Observability performance measurement tool.
Runs some rudimentary performance tests on a deployed instance to validate performance.

Usage: $0 [options] [<namespace>]

options:
  -h  Print this help

<namespace>:
  The namespace that is running SUSE Observability, or
  "suse-observability" when not specified
EOF
      exit 0;;
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
for cmd in ${COMMANDS[@]}; do
  if ! command -v $cmd &>/dev/null; then
     echo "$cmd is not installed. Please install it and try again."
     exit 1
  fi
done

# Check if KUBECONFIG is set
if ! kubectl config current-context > /dev/null; then
  echo "Error: Could not find kubernetes cluster to connect to."
  echo "Please ensure KUBECONFIG is set to the path of a valid kubeconfig file before running this script."
  echo "If kubeconfig is not set, use the command: export KUBECONFIG=PATH-TO-YOUR/kubeconfig. Exiting..."
  exit 1
else
  CONTEXT=$(kubectl config current-context)
  echo "Running performance tests in kubernetes context: $CONTEXT"
fi

# Check if namespace exist or not
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Namespace '$NAMESPACE' does not exist. Exiting."
    exit 1
fi
# Directory to store results
OUTPUT_DIR="${NAMESPACE}_performance_$(date -u +%Y-%m-%d_%H-%M-%SZ)"
ARCHIVE_FILE="${OUTPUT_DIR}.tar.gz"

techo() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a $OUTPUT_DIR/collector-output.log
}

collect_stackgraph_disk_performance_buffered() {
    techo "StackGraph Buffered Disk performance..."
    SUBDIR="$OUTPUT_DIR/stackgraph_disk_buffered"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==stackgraph -o jsonpath="{.items[*].metadata.name}")
    if [ "${PODS[0]}" = "" ]; then
      techo "StackGraph not found due to HA setup."
    else
      mkdir -p "$SUBDIR"

      for pod in $PODS; do
          kubectl -n "$NAMESPACE" exec "$pod" -c "datanode" -- sh -xc 'dd if=/dev/zero of=/hadoop-data/data/testfile bs=1M count=500 conv=fsync' > "$SUBDIR/$pod.log" 2>&1
          kubectl -n "$NAMESPACE" exec "$pod" -c "datanode" -- sh -xc 'rm /hadoop-data/data/testfile' >> "$SUBDIR/$pod.log" 2>&1
      done
    fi
}

collect_stackgraph_disk_performance_direct() {
    techo "StackGraph Direct Disk performance..."
    SUBDIR="$OUTPUT_DIR/stackgraph_disk_direct"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==stackgraph -o jsonpath="{.items[*].metadata.name}")
    if [ "${PODS[0]}" = "" ]; then
      techo "StackGraph not found due to HA setup."
    else
      mkdir -p "$SUBDIR"

      for pod in $PODS; do
          kubectl -n "$NAMESPACE" exec "$pod" -c "datanode" -- sh -xc 'dd if=/dev/zero of=/hadoop-data/data/testfile bs=1M count=500 conv=fsync oflag=direct' > "$SUBDIR/$pod.log" 2>&1
          kubectl -n "$NAMESPACE" exec "$pod" -c "datanode" -- sh -xc 'rm /hadoop-data/data/testfile' >> "$SUBDIR/$pod.log" 2>&1
      done
    fi
}

collect_hdfs_disk_performance_buffered() {
    techo "HDFS Buffered Disk performance..."
    SUBDIR="$OUTPUT_DIR/hdfs_disk_buffered"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==hdfs-dn -o jsonpath="{.items[*].metadata.name}")
    if [ "${PODS[0]}" = "" ]; then
      techo "HDFS not found due to non-HA setup."
    else
      mkdir -p "$SUBDIR"

      for pod in $PODS; do
          kubectl -n "$NAMESPACE" exec "$pod" -c "datanode" -- sh -xc 'dd if=/dev/zero of=/hadoop-data/testfile bs=1M count=500 conv=fsync' > "$SUBDIR/$pod.log" 2>&1
          kubectl -n "$NAMESPACE" exec "$pod" -c "datanode" -- sh -xc 'rm /hadoop-data/testfile' >> "$SUBDIR/$pod.log" 2>&1
      done
    fi
}

collect_hdfs_disk_performance_direct() {
    techo "HDFS Direct Disk performance..."
    SUBDIR="$OUTPUT_DIR/hdfs_disk_direct"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==hdfs-dn -o jsonpath="{.items[*].metadata.name}")
    if [ "${PODS[0]}" = "" ]; then
      techo "HDFS not found due to non-HA setup."
    else
      mkdir -p "$SUBDIR"

      for pod in $PODS; do
          kubectl -n "$NAMESPACE" exec "$pod" -c "datanode" -- sh -xc 'dd if=/dev/zero of=/hadoop-data/testfile bs=1M count=500 conv=fsync oflag=direct' > "$SUBDIR/$pod.log" 2>&1
          kubectl -n "$NAMESPACE" exec "$pod" -c "datanode" -- sh -xc 'rm /hadoop-data/testfile' >> "$SUBDIR/$pod.log" 2>&1
      done
    fi
}

collect_kafka_disk_performance_buffered() {
    techo "Kafka Buffered Disk performance..."
    SUBDIR="$OUTPUT_DIR/kafka_disk_buffered"

    mkdir -p "$SUBDIR"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==kafka -o jsonpath="{.items[*].metadata.name}")
    for pod in $PODS; do
        kubectl -n "$NAMESPACE" exec "$pod" -c "kafka" -- sh -xc 'dd if=/dev/zero of=/bitnami/kafka/testfile bs=1M count=500 conv=fsync' > "$SUBDIR/$pod.log" 2>&1
        kubectl -n "$NAMESPACE" exec "$pod" -c "kafka" -- sh -xc 'rm /bitnami/kafka/testfile' >> "$SUBDIR/$pod.log" 2>&1
    done
}

collect_kafka_disk_performance_direct() {
    techo "Kafka Direct Disk performance..."
    SUBDIR="$OUTPUT_DIR/kafka_disk_direct"

    mkdir -p "$SUBDIR"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==kafka -o jsonpath="{.items[*].metadata.name}")
    for pod in $PODS; do
        kubectl -n "$NAMESPACE" exec "$pod" -c "kafka" -- sh -xc 'dd if=/dev/zero of=/bitnami/kafka/testfile bs=1M count=500 conv=fsync oflag=direct' > "$SUBDIR/$pod.log" 2>&1
        kubectl -n "$NAMESPACE" exec "$pod" -c "kafka" -- sh -xc 'rm /bitnami/kafka/testfile' >> "$SUBDIR/$pod.log" 2>&1
    done
}

create_kafka_topics() {
  # Topics cannot be removed because topic deletion is disabled by default on the broker
    techo "Creating topics"

    SUBDIR="$OUTPUT_DIR/kafka_topic_create"

    mkdir -p "$SUBDIR"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==kafka -o jsonpath="{.items[*].metadata.name}")

    index=0
    for pod in $PODS; do
      # Topics are pinned to a particular broker using replica-assignment, allowing to test localhost/networked traffic
        kubectl -n "$NAMESPACE" exec "$pod" -c "kafka" -- bash -xc "\
          JMX_PORT="" /opt/bitnami/kafka/bin/kafka-topics.sh --create --if-not-exists --topic perf-test-topic-$index --bootstrap-server localhost:9092 --replica-assignment $index --config retention.ms=300000 --config retention.bytes=1073741824 \
        " > "$SUBDIR/$pod.log" 2>&1

        ((index++))
    done
}

collect_kafka_broker_performance_local() {
  # Topics cannot be removed because topic deletion is disabled by default on the broker
    techo "Performance testing throughput to topic on localhost"

    SUBDIR="$OUTPUT_DIR/kafka_producer_local"

    mkdir -p "$SUBDIR"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==kafka -o jsonpath="{.items[*].metadata.name}")

    index=0
    for pod in $PODS; do
       kubectl -n "$NAMESPACE" exec "$pod" -c "kafka" -- bash -xc "\
                 JMX_PORT="" /opt/bitnami/kafka/bin/kafka-producer-perf-test.sh --topic perf-test-topic-$index --num-records 500000 --record-size 1024 --throughput -1 --producer-props bootstrap.servers=localhost:9092 acks=1\
               " > "$SUBDIR/$pod.log" 2>&1

        ((index++))
    done
}

collect_kafka_broker_performance_remote() {
  # Topics cannot be removed because topic deletion is disabled by default on the broker
    techo "Performance testing throughput to topic on remote broker"

    SUBDIR="$OUTPUT_DIR/kafka_producer_remote"

    mkdir -p "$SUBDIR"

    PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component==kafka -o jsonpath="{.items[*].metadata.name}")

    # Convert to array to be able to do a broker count
    POD_ARRAY=($PODS)
    if [ "${#POD_ARRAY[@]}" = "1" ]; then
      techo "Skipping remote testing due to only 1 kafka broker"
    else
      techo "Performance testing remote"
      index=0
      # Used to select a topic on a remote broker
      prev_index=${#POD_ARRAY[@]}
      ((prev_index--))
      for pod in $PODS; do
          kubectl -n "$NAMESPACE" exec "$pod" -c "kafka" -- bash -xc "\
            JMX_PORT="" /opt/bitnami/kafka/bin/kafka-producer-perf-test.sh --topic perf-test-topic-$prev_index --num-records 500000 --record-size 1024 --throughput -1 --producer-props bootstrap.servers=localhost:9092 acks=1\
          " > "$SUBDIR/$pod.log" 2>&1
          prev_index=$index
          ((index++))
      done
    fi
}

collect_kafka_broker_performance() {
    techo "Kafka Topic performance..."
    create_kafka_topics
    collect_kafka_broker_performance_local
    collect_kafka_broker_performance_remote
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

collect_stackgraph_disk_performance_buffered
collect_stackgraph_disk_performance_direct
collect_hdfs_disk_performance_buffered
collect_hdfs_disk_performance_direct
collect_kafka_disk_performance_buffered
collect_kafka_disk_performance_direct
collect_kafka_broker_performance

archive_and_cleanup
echo "All information collected in the $ARCHIVE_FILE"
