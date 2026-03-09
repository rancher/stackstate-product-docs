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
COMMANDS=("kubectl" "tar" "awk" "tr" "grep")
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

# Title-case a string like "kafka_disk_buffered" -> "Kafka Disk Buffered"
title_case() {
    echo "$1" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
}

# Directory-case a string like "Kafka Disk Buffered" -> "kafka_disk_buffered"
dir_case() {
    echo "$1" | awk '{print tolower($0)}' | tr ' ' '_'
}

# Runs a dd disk write performance test on all pods matching a component label.
# Usage: collect_disk_performance <label> <subdir> <component> <container> <testfile_path> [<extra_dd_flags>]
#   label:          Human-readable name for log output (e.g. "StackGraph Buffered")
#   component:      Value for app.kubernetes.io/component pod selector
#   container:      Container name inside the pod
#   testfile_path:  Absolute path to the temporary test file inside the container
#   extra_dd_flags: Optional extra flags appended to the dd command (e.g. "oflag=direct")
collect_disk_performance() {
    local label="$1" component="$2" container="$3" testfile_path="$4" extra_dd_flags="$5"
    local subdir=$(dir_case "$label")
    local dd_flags="conv=fsync${extra_dd_flags:+ $extra_dd_flags}"

    techo "$label performance..."
    local SUBDIR="$OUTPUT_DIR/$subdir"

    local PODS
    PODS=$(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/component==$component" -o jsonpath="{.items[*].metadata.name}")
    if [ -z "$PODS" ]; then
      techo "No pods found for component '$component', skipping."
      return
    fi

    mkdir -p "$SUBDIR"

    for pod in $PODS; do
        kubectl -n "$NAMESPACE" exec "$pod" -c "$container" -- sh -xc "dd if=/dev/zero of=$testfile_path bs=100K count=5000 $dd_flags" > "$SUBDIR/$pod.log" 2>&1
        kubectl -n "$NAMESPACE" exec "$pod" -c "$container" -- sh -xc "rm $testfile_path" >> "$SUBDIR/$pod.log" 2>&1
    done
}

# Runs a dd disk write performance test on all pods matching a component label.
# Usage: collect_disk_performance <label> <subdir> <component> <container> <testfile_path> [<extra_dd_flags>]
#   label:          Human-readable name for log output (e.g. "StackGraph Buffered")
#   component:      Value for app.kubernetes.io/component pod selector
#   container:      Container name inside the pod
collect_network_performance() {
    local label="$1" component="$2" container="$3"
    local subdir=$(dir_case "$label")

    techo "$label performance..."
    local SUBDIR="$OUTPUT_DIR/$subdir"

    local PODS
    PODS=$(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/component==$component" -o jsonpath="{.items[*].metadata.name}")
    if [ -z "$PODS" ]; then
      techo "No pods found for component '$component', skipping."
      return
    fi

    # Convert to array to be able to do a broker count
    POD_ARRAY=($PODS)
    if [ "${#POD_ARRAY[@]}" = "1" ]; then
      techo "Skipping network testing due to only one '$component' found."
    fi

    POD_HOSTS=()
    for pod in $PODS; do
      pod_host=$(kubectl -n "$NAMESPACE" exec "$pod" -c "$container" -- hostname -f)
      POD_HOSTS+=("$pod_host")
    done

    mkdir -p "$SUBDIR"

    len=${#POD_ARRAY[@]}
    for (( i=0; i<len; i++ )); do
        next=$(( (i + 1) % len ))

        pod=${POD_ARRAY[i]}

        next_pod=${POD_ARRAY[next]}
        next_pod_host=${POD_HOSTS[next]}

        kubectl -n "$NAMESPACE" exec "$pod" -c "$container" -- sh -xc "nc -l 12348 > /dev/null" > "$SUBDIR/$pod.target.log" 2>&1 &
        kubectl -n "$NAMESPACE" exec "$next_pod" -c "$container" -- sh -xc "dd if=/dev/zero bs=1M count=1000 | nc -q 1 $next_pod_host 12348" > "$SUBDIR/$pod.source.log" 2>&1
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

generate_summary() {
    techo "Generating summary..."
    SUMMARY="$OUTPUT_DIR/summary.log"

    echo "=== SUSE Observability Performance Summary ===" > "$SUMMARY"
    echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY"
    echo "" >> "$SUMMARY"

    # Disk throughput sections (dd output)
    for section in stackgraph_disk_buffered stackgraph_disk_direct hdfs_disk_buffered hdfs_disk_direct kafka_disk_buffered kafka_disk_direct; do
        SECTION_DIR="$OUTPUT_DIR/$section"
        [ -d "$SECTION_DIR" ] || continue

        label=$(title_case "$section")
        echo "--- $label ---" >> "$SUMMARY"

        for logfile in "$SECTION_DIR"/*.log; do
            [ -f "$logfile" ] || continue
            pod=$(basename "$logfile" .log)
            # Extract the throughput value (e.g. "145 MB/s") from dd output — last field of the line containing "B/s"
            throughput=$(awk '/[KMGT]?B\/s/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]/ && $(i+1) ~ /B\/s/) {print $i, $(i+1); found=1}} END {if(!found) print ""}' "$logfile" | tail -1)
            if [ -n "$throughput" ]; then
                printf "  %-60s %s\n" "$pod" "$throughput" >> "$SUMMARY"
            else
                printf "  %-60s %s\n" "$pod" "N/A" >> "$SUMMARY"
            fi
        done
        echo "" >> "$SUMMARY"
    done

    # Kafka producer throughput sections (kafka-producer-perf-test output)
    for section in kafka_producer_local kafka_producer_remote; do
        SECTION_DIR="$OUTPUT_DIR/$section"
        [ -d "$SECTION_DIR" ] || continue

        label=$(title_case "$section")
        echo "--- $label ---" >> "$SUMMARY"

        for logfile in "$SECTION_DIR"/*.log; do
            [ -f "$logfile" ] || continue
            pod=$(basename "$logfile" .log)
            # Extract the final summary line (contains percentiles like "ms 50th")
            perf_line=$(grep 'ms 50th' "$logfile")
            if [ -n "$perf_line" ]; then
                # Parse: "500000 records sent, 56818.18 records/sec (55.49 MB/sec), 489.62 ms avg latency, ..."
                records_sec=$(echo "$perf_line" | awk -F', ' '{for(i=1;i<=NF;i++) if($i ~ /records\/sec/) print $i}' | awk '{print $1, $2}')
                mb_sec=$(echo "$perf_line" | awk -F'[()]' '{for(i=1;i<=NF;i++) if($i ~ /MB\/sec/) printf "(%s)", $i}')
                avg_lat=$(echo "$perf_line" | awk -F', ' '{for(i=1;i<=NF;i++) if($i ~ /avg latency/) print $i}')
                printf "  %-60s %s %s, %s\n" "$pod" "$records_sec" "$mb_sec" "$avg_lat" >> "$SUMMARY"
            else
                printf "  %-60s %s\n" "$pod" "N/A" >> "$SUMMARY"
            fi
        done
        echo "" >> "$SUMMARY"
    done

    # Network throughput sections (dd | nc output in *.source.log files)
    for section in hdfs_network kafka_network; do
        SECTION_DIR="$OUTPUT_DIR/$section"
        [ -d "$SECTION_DIR" ] || continue

        label=$(title_case "$section")
        echo "--- $label ---" >> "$SUMMARY"

        for logfile in "$SECTION_DIR"/*.source.log; do
            [ -f "$logfile" ] || continue
            pod=$(basename "$logfile" .source.log)
            # Extract target hostname from the nc command (e.g. "nc -q 1 <host> 12348")
            target=$(awk '/nc -q/ {for(i=1;i<=NF;i++) if($i == "-q") {print $(i+2); exit}}' "$logfile")
            # Shorten the FQDN to just the pod name (first dot-separated segment)
            target_short=$(echo "$target" | awk -F. '{print $1}')
            # Extract throughput from dd output
            throughput=$(awk '/[KMGT]?B\/s/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]/ && $(i+1) ~ /B\/s/) {print $i, $(i+1); found=1}} END {if(!found) print ""}' "$logfile" | tail -1)
            if [ -n "$throughput" ]; then
                printf "  %-60s %s\n" "$pod -> $target_short" "$throughput" >> "$SUMMARY"
            else
                printf "  %-60s %s\n" "$pod -> $target_short" "N/A" >> "$SUMMARY"
            fi
        done
        echo "" >> "$SUMMARY"
    done

    techo "Summary written to $SUMMARY"
    cat "$SUMMARY"
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

collect_disk_performance "StackGraph Disk Buffered" "stackgraph" "datanode" "/hadoop-data/data/testfile"
collect_disk_performance "StackGraph Disk Direct"   "stackgraph" "datanode" "/hadoop-data/data/testfile" "oflag=direct"

collect_disk_performance "HDFS Disk Buffered"       "hdfs-dn"    "datanode" "/hadoop-data/testfile"
collect_disk_performance "HDFS Disk Direct"         "hdfs-dn"    "datanode" "/hadoop-data/testfile"      "oflag=direct"
collect_network_performance "HDFS Network"             "hdfs-dn"    "datanode"

collect_disk_performance "Kafka Disk Buffered"      "kafka"      "kafka"    "/bitnami/kafka/testfile"
collect_disk_performance "Kafka Disk Direct"        "kafka"      "kafka"    "/bitnami/kafka/testfile"    "oflag=direct"
# The kafka images is missing both the `hostname` command and `nc`, so we skip this one
# collect_network_performance "Kafka Network"            "kafka"      "kafka"
collect_kafka_broker_performance

generate_summary

archive_and_cleanup
echo "All information collected in the $ARCHIVE_FILE"
