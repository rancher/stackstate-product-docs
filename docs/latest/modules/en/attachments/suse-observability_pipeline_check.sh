#!/bin/bash
# shellcheck disable=SC2016

INTERVAL=60
KEEP=false
ALL_CHECKS="pods cpu memory volumes receiver kafka vmagent otel clickhouse victoriametrics elasticsearch"
CHECKS=$ALL_CHECKS

list_checks() {
  cat <<EOF
pods             Pods that are not running or ready, restarts and OOMKilled containers
cpu              CPU throttling per container, or CPU usage against the limit without nodes/proxy
memory           Containers that use 95% or more of their memory limit
volumes          Persistent volumes that are 80% full or more
receiver         Agent requests, API keys, memory limiter, element budgets and rejected logs
kafka            Kafka consumer lag per topic and the pod that consumes it
vmagent          vmagent queue, retries, drops and writes to VictoriaMetrics
otel             OpenTelemetry Collector refused, dropped and failed data and export queues
clickhouse       ClickHouse rejected and delayed inserts
victoriametrics  VictoriaMetrics inserted rows, slow inserts and ignored rows
elasticsearch    Elasticsearch cluster health and disk usage
EOF
}

usage() {
  cat <<EOF
SUSE Observability data ingestion pipeline check.
Reads the metrics of the platform components twice, with an interval in between,
and reports crashing or throttled pods, rejected data and data that does not arrive.
Use it when the UI is not available. It does not change anything in the cluster.

Usage: $0 [options] [<namespace>]

options:
  -i <seconds>  Interval between the two samples, default $INTERVAL
  -c <checks>   Comma-separated list of checks to run, default all
  -l            List the checks
  -k            Keep the collected samples in a directory in the current directory
  -h            Print this help

<namespace>:
  The namespace that is running SUSE Observability, or
  "suse-observability" when not specified

Required permissions in the namespace: list pods, get pods.metrics.k8s.io, create pods/portforward.
Required cluster permission for the CPU throttling and volume checks: get nodes/proxy.
Without it, the script compares CPU and memory usage from pods.metrics.k8s.io with the
limits instead. That CPU check is an approximation, it does not measure throttling.
EOF
}

while getopts "hlki:c:" option; do
  case $option in
    h) usage; exit 0;;
    l) list_checks; exit 0;;
    k) KEEP=true;;
    i) INTERVAL=$OPTARG;;
    c) CHECKS=${OPTARG//,/ };;
    \?) echo "ERROR: Invalid option"; exit 1;;
  esac
done
shift $((OPTIND - 1))

NAMESPACE=${1:-suse-observability}

case $INTERVAL in
  ''|*[!0-9]*) echo "ERROR: The interval must be a number of seconds"; exit 1;;
esac
if [ "$INTERVAL" -lt 10 ]; then
  echo "ERROR: The interval must be at least 10 seconds"
  exit 1
fi

for c in $CHECKS; do
  case " $ALL_CHECKS " in
    *" $c "*) ;;
    *) echo "ERROR: Unknown check '$c', run $0 -l to list the checks"; exit 1;;
  esac
done

wants() {
  local c
  for c in "$@"; do
    case " $CHECKS " in *" $c "*) return 0;; esac
  done
  return 1
}

for cmd in kubectl curl awk sed sort mktemp; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "$cmd is not installed. Please install it and try again."
    exit 1
  fi
done

if ! CONTEXT=$(kubectl config current-context 2>/dev/null); then
  echo "Error: Could not find kubernetes cluster to connect to."
  echo "Please ensure KUBECONFIG is set to the path of a valid kubeconfig file before running this script."
  exit 1
fi

if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "Namespace '$NAMESPACE' does not exist. Exiting."
  exit 1
fi

if $KEEP; then
  WORK="${NAMESPACE}_pipeline_check_$(date -u +%Y-%m-%d_%H-%M-%SZ)"
  mkdir -p "$WORK"
else
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
fi

if [ -t 1 ]; then
  COLOR=true
else
  COLOR=false
fi

# Metric names to keep per scrape, so the samples stay small.
KEEP_RECEIVER='^(receiver_agent_request_total|stackstate_receiver_(memory_limiter_(claimed_size|limit)|unique_element_passed_(count|max)|element_create_passed_(count|max)|events_rejected_size_total))$'
KEEP_CONSUMER='^kafka_consumer_consumer_fetch_manager_metrics_records_lag$'
KEEP_VMAGENT='^(vm_persistentqueue_bytes_(pending|dropped_total)|vmagent_remotewrite_(packets_dropped_total|samples_dropped_total|retries_count_total|requests_total))$'
KEEP_OTEL='^otelcol_(receiver_refused_|exporter_send_failed_|processor_dropped_|exporter_queue_(size|capacity))'
KEEP_CLICKHOUSE='^ClickHouseProfileEvents_(RejectedInserts|DelayedInserts)$'
KEEP_VM='^(vm_slow_row_inserts_total|vm_rows_inserted_total|vm_rows_ignored_total)$'
KEEP_CADVISOR='^container_(cpu_cfs_periods_total|cpu_cfs_throttled_periods_total|memory_working_set_bytes|spec_memory_limit_bytes)$'
KEEP_KUBELET='^kubelet_volume_stats_(used|capacity)_bytes$'

# Converts Prometheus text format to: kind, source, metric, labels, value.
normalize() {
  awk -v kind="$1" -v src="$2" -v keep="$3" -v ns="$NAMESPACE" '
    /^#/ || NF == 0 { next }
    {
      line = $0
      b = index(line, "{"); sp = index(line, " ")
      if (b > 0 && b < sp) {
        name = substr(line, 1, b - 1)
        rest = substr(line, b + 1)
        e = index(rest, "}")
        labels = substr(rest, 1, e - 1)
        rest = substr(rest, e + 1)
      } else {
        name = substr(line, 1, sp - 1); labels = ""; rest = substr(line, sp)
      }
      if (name !~ keep) next
      if ((kind == "cadvisor" || kind == "kubelet") && index(labels, "namespace=\"" ns "\"") == 0) next
      gsub(/, +/, ",", labels)
      gsub(/api_key=[^",&)][^,&")]*/, "api_key=***", labels)
      split(rest, f, " ")
      if (f[1] !~ /^[-+]?[0-9.]+([eE][-+]?[0-9]+)?$/) next
      printf "%s\t%s\t%s\t%s\t%s\n", kind, src, name, labels, f[1]
    }'
}

# Port-forwards to a pod on a random local port and fetches the given paths.
fetch() {
  local pod=$1 port=$2 log lp="" pf p
  shift 2
  log=$(mktemp "$WORK/pf.XXXXXX")
  kubectl -n "$NAMESPACE" port-forward "pod/$pod" "0:$port" >"$log" 2>&1 &
  pf=$!
  for _ in $(seq 1 40); do
    lp=$(sed -nE 's/^Forwarding from 127\.0\.0\.1:([0-9]+) .*/\1/p' "$log" | head -1)
    [ -n "$lp" ] && break
    kill -0 "$pf" 2>/dev/null || break
    sleep 0.25
  done
  if [ -n "$lp" ]; then
    for p in "$@"; do
      curl -s --max-time 30 "http://127.0.0.1:$lp$p"
      echo
    done
  fi
  kill "$pf" 2>/dev/null
  wait "$pf" 2>/dev/null
  rm -f "$log"
}

running_pods() {
  kubectl -n "$NAMESPACE" get pods -l "$1" --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}

discover() {
  local pod
  : > "$WORK/targets"
  if wants receiver; then
    for pod in $(running_pods 'app.kubernetes.io/component in (receiver,receiver-base,receiver-logs,receiver-process-agent)'); do
      echo "receiver $pod 9404 $KEEP_RECEIVER" >> "$WORK/targets"
    done
  fi
  if wants kafka; then
    for pod in $(running_pods 'app.kubernetes.io/component in (server,sync,health-sync,correlate,e2es)'); do
      echo "consumer $pod 9404 $KEEP_CONSUMER" >> "$WORK/targets"
    done
  fi
  if wants vmagent; then
    for pod in $(running_pods 'app.kubernetes.io/component=vmagent'); do
      echo "vmagent $pod 8429 $KEEP_VMAGENT" >> "$WORK/targets"
    done
  fi
  if wants otel; then
    for pod in $(running_pods 'app.kubernetes.io/name=opentelemetry-collector'); do
      echo "otel $pod 8888 $KEEP_OTEL" >> "$WORK/targets"
    done
  fi
  if wants clickhouse; then
    for pod in $(running_pods 'app.kubernetes.io/name=clickhouse'); do
      echo "clickhouse $pod 8001 $KEEP_CLICKHOUSE" >> "$WORK/targets"
    done
  fi
  if wants victoriametrics; then
    for pod in $(running_pods 'app.kubernetes.io/name in (victoria-metrics-0,victoria-metrics-1)'); do
      echo "vm $pod 8428 $KEEP_VM" >> "$WORK/targets"
    done
  fi
  NODES=$(kubectl -n "$NAMESPACE" get pods --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u)
  ES_POD=""
  if wants elasticsearch; then
    ES_POD=$(running_pods 'app.kubernetes.io/name=elasticsearch,app.kubernetes.io/component=master' | head -1)
  fi
}

sample() {
  local n=$1 dir="$WORK/sample-$1" kind pod port keep node
  mkdir -p "$dir"
  date +%s > "$dir/time"
  kubectl -n "$NAMESPACE" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .status.containerStatuses[*]}{.name}{"|"}{.ready}{"|"}{.restartCount}{"|"}{.lastState.terminated.reason}{";"}{end}{"\n"}{end}' > "$dir/pods" &
  while read -r kind pod port keep; do
    (fetch "$pod" "$port" /metrics | normalize "$kind" "$pod" "$keep" > "$dir/$kind-$pod.tsv") &
  done < "$WORK/targets"
  for node in $NODES; do
    if wants cpu memory; then
      (kubectl get --raw "/api/v1/nodes/$node/proxy/metrics/cadvisor" 2>/dev/null | normalize cadvisor "$node" "$KEEP_CADVISOR" > "$dir/cadvisor-$node.tsv") &
    fi
    if wants volumes && [ "$n" = 2 ]; then
      (kubectl get --raw "/api/v1/nodes/$node/proxy/metrics" 2>/dev/null | normalize kubelet "$node" "$KEEP_KUBELET" > "$dir/kubelet-$node.tsv") &
    fi
  done
  wants cpu memory && (kubectl -n "$NAMESPACE" get pods.metrics.k8s.io 2>/dev/null \
    -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.window}{"|"}{range .containers[*]}{.name}{"="}{.usage.cpu}{"="}{.usage.memory}{";"}{end}{"\n"}{end}' \
    | podmetrics usage > "$dir/usage.tsv") &
  if [ "$n" = 2 ]; then
    (kubectl -n "$NAMESPACE" get pods --field-selector=status.phase=Running \
      -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .spec.containers[*]}{.name}{"="}{.resources.limits.cpu}{"="}{.resources.limits.memory}{";"}{end}{"\n"}{end}' \
      | podmetrics limit > "$dir/limits.tsv") &
  fi
  if [ "$n" = 2 ] && [ -n "$ES_POD" ]; then
    (fetch "$ES_POD" 9200 '/_cluster/health' '/_cat/allocation?h=node,disk.percent,disk.total&bytes=gb' > "$dir/elasticsearch") &
  fi
  wait
  cat "$dir"/*.tsv > "$WORK/$n.tsv" 2>/dev/null
}

# Converts pod metrics and pod limits (pod|[window|]container=cpu=memory;...) to the normalized format.
podmetrics() {
  awk -F'|' -v kind="$1" '
    function cores(v) {
      if (v ~ /n$/) return substr(v, 1, length(v) - 1) / 1e9
      if (v ~ /u$/) return substr(v, 1, length(v) - 1) / 1e6
      if (v ~ /m$/) return substr(v, 1, length(v) - 1) / 1e3
      return v + 0
    }
    function bytes(v,   u, i) {
      if (match(v, /[KMGTPE]i?$/)) {
        u = substr(v, RSTART); v = substr(v, 1, RSTART - 1)
        i = index("KMGTPE", substr(u, 1, 1))
        return v * ((u ~ /i$/) ? 1024 : 1000) ^ i
      }
      return v + 0
    }
    NF >= 2 {
      n = split($NF, c, ";")
      for (j = 1; j <= n; j++) {
        if (split(c[j], x, "=") < 3) continue
        if (x[2] != "") printf "%s\t%s\tcpu\tcontainer=\"%s\"\t%.6f\n", kind, $1, x[1], cores(x[2])
        if (x[3] != "") printf "%s\t%s\tmemory\tcontainer=\"%s\"\t%.0f\n", kind, $1, x[1], bytes(x[3])
      }
    }'
}

# Prints one section. Reads rows of: level, message, fix.
section() {
  awk -F'\t' -v title="$1" -v color="$COLOR" -v levels="$WORK/levels" -v fixlog="$WORK/fixes" '
    BEGIN {
      if (color == "true") { c["FAIL"] = "\033[31m"; c["WARN"] = "\033[33m"; c["OK"] = "\033[32m"; reset = "\033[0m" }
      printf "\n== %s\n", title
    }
    NF == 0 { next }
    $3 != "" && !($3 in seen) { seen[$3] = 1; fixes[++nf] = $3; print $3 >> fixlog }
    $1 == "FIX" { next }
    {
      n[$1]++; row[$1, n[$1]] = $2
      print $1 >> levels
    }
    END {
      split("FAIL WARN OK", order, " ")
      for (o = 1; o <= 3; o++) {
        l = order[o]
        for (i = 1; i <= n[l] && i <= 12; i++) printf "  %s%-4s%s  %s\n", c[l], l, reset, row[l, i]
        if (n[l] > 12) printf "        ... and %d more\n", n[l] - 12
      }
      for (i = 1; i <= nf; i++) printf "  Fix:  %s\n", fixes[i]
    }'
}

# Shared awk helpers for the checks. s is the sample number, secs the seconds between samples.
LIB='
function lbl(l, k,   v) {
  if (match(l, "(^|,)" k "=\"[^\"]*\"")) {
    v = substr(l, RSTART, RLENGTH); sub(/^,/, "", v)
    return substr(v, length(k) + 3, length(v) - length(k) - 3)
  }
  return ""
}
function out(level, msg, fix) { printf "%s\t%s\t%s\n", level, msg, fix }
function permin(d) { return d * 60 / secs }
function mib(b) { return sprintf("%.0f MiB", b / 1048576) }
function ceil(x) { return (x == int(x)) ? x : int(x) + 1 }
function cpufmt(c,   m) { m = int(c * 1000 + 0.5); return (m >= 1000 && m % 100 == 0) ? m / 1000 : m "m" }
function memfmt(b,   m) { m = int(b / 1048576 + 0.5); return (m % 1024 == 0) ? m / 1024 "Gi" : m "Mi" }
# Helm values key of the resources of a container, empty when unknown.
function vkey(pod, c) {
  if (c == "receiver") {
    if (pod ~ /-receiver-base-/) return "stackstate.components.receiver.split.base"
    if (pod ~ /-receiver-logs-/) return "stackstate.components.receiver.split.logs"
    if (pod ~ /-receiver-process-agent-/) return "stackstate.components.receiver.split.processAgent"
    return "stackstate.components.receiver"
  }
  if (c == "correlate") {
    if (pod ~ /-correlate-connection-/) return "stackstate.components.correlate.split.connection"
    if (pod ~ /-correlate-http-tracing-/) return "stackstate.components.correlate.split.httpTracing"
    if (pod ~ /-correlate-aggregator-/) return "stackstate.components.correlate.split.aggregator"
    return "stackstate.components.correlate"
  }
  if (c ~ /^(server|sync|e2es|vmagent|state|router|api|ui|checks|slicing|notification|initializer)$/) return "stackstate.components." c
  if (c == "health-sync") return "stackstate.components.healthSync"
  if (c == "authorization-sync") return "stackstate.components.authorizationSync"
  if (c == "workload-observer") return "stackstate.components.workloadObserver"
  if (c == "stackgraph" || c == "tephra") return "hbase." c
  if (c == "master" || c == "regionserver") return "hbase.hbase." c
  if (c == "datanode") return "hbase.hdfs.datanode"
  if (c == "namenode") return (pod ~ /-hdfs-snn-/) ? "hbase.hdfs.secondarynamenode" : "hbase.hdfs.namenode"
  if (c == "jmx-exporter") return "kafka.metrics.jmx"
  if (c ~ /^(kafka|zookeeper|clickhouse|elasticsearch|opentelemetry-collector|s3proxy)$/) return c
  if (c ~ /^victoria-metrics-[01]-server$/) return substr(c, 1, 18) ".server"
  return ""
}
# Records a suggested limit for a container. Replicas share a key, so the largest step wins.
function raise(pod, c, what, cur, f,   k) {
  k = vkey(pod, c); if (k == "") k = pod "/" c
  if (!((k, what) in SUGF) || f > SUGF[k, what]) { SUGF[k, what] = f; SUGC[k, what] = cur }
}
# Prints the suggested limits as fixes and returns how many.
function suggestions(   kw, x, k, cur, nv, txt, n) {
  for (kw in SUGF) {
    split(kw, x, SUBSEP); k = x[1]; cur = SUGC[kw]
    if (cur <= 0) continue
    if (x[2] == "cpu") { nv = ceil(cur * SUGF[kw] * 10) / 10; txt = cpufmt(cur) " to " cpufmt(nv) }
    else { nv = ceil(cur * SUGF[kw] / 134217728) * 134217728; txt = memfmt(cur) " to " memfmt(nv) }
    if (k ~ /\//) out("FIX", "", sprintf("Raise the %s limit of %s from %s.", x[2], k, txt))
    else out("FIX", "", sprintf("Raise %s.resources.limits.%s from %s, and the %s request with it.", k, x[2], txt, x[2]))
    n++
  }
  return n
}
{ s = (FILENAME == f1) ? 1 : 2 }
'

check() {
  awk -F'\t' -v f1="$WORK/1.tsv" -v secs="$SECS" "$LIB $1" "$WORK/1.tsv" "$WORK/2.tsv"
}

check_pods() {
  awk -F'\t' -v f1="$WORK/sample-1/pods" -v lf="$WORK/sample-2/limits.tsv" -v ns="$NAMESPACE" "$LIB"'
    FILENAME == lf { if ($3 == "memory") ml[$2 "/" lbl($4, "container")] = $5; next }
    FILENAME == f1 {
      n = split($3, c, ";")
      for (i = 1; i <= n; i++) if (c[i] != "") { split(c[i], x, "|"); before[$1 "/" x[1]] = x[3] }
      next
    }
    $2 == "Succeeded" { next }
    $2 != "Running" {
      printf "FAIL\t%s is %s\tInspect the pod with kubectl -n %s describe pod <pod>.\n", $1, $2, ns; bad++; next
    }
    {
      n = split($3, c, ";")
      for (i = 1; i <= n; i++) {
        if (c[i] == "") continue
        split(c[i], x, "|"); k = $1 "/" x[1]; rc = x[3] + 0
        if (x[2] != "true") { printf "FAIL\t%s is not ready\tCheck the logs with kubectl -n %s logs <pod> -c <container>.\n", k, ns; bad++ }
        if ((k in before) && rc > before[k] + 0) {
          printf "FAIL\t%s restarted during the check, last reason %s\tCheck the logs of the previous container with kubectl -n %s logs <pod> -c <container> --previous.\n", k, x[4], ns; bad++
        } else if (x[4] == "OOMKilled") {
          printf "FAIL\t%s: restarted %d time%s, last reason OOMKilled\t\n", k, rc, rc == 1 ? "" : "s"; bad++; oom++
          raise($1, x[1], "memory", ml[k], 1.5)
        } else if (rc > 0) {
          printf "WARN\t%s: restarted %d time%s, last reason %s\tCheck the logs of the previous container with kubectl -n %s logs <pod> -c <container> --previous.\n", k, rc, rc == 1 ? "" : "s", x[4], ns; bad++
        }
      }
    }
    END {
      if (oom && !suggestions()) out("FIX", "", "Raise the memory limit of the OOMKilled components.")
      if (!bad) print "OK\tAll pods are running and ready, no restarts"
    }
  ' "$WORK/sample-2/limits.tsv" "$WORK/sample-1/pods" "$WORK/sample-2/pods"
}

# cadvisor series are keyed by the cgroup id, because a restarted or rescheduled pod keeps its name.
check_cpu() {
  check '
    $1 == "cadvisor" && $3 ~ /^container_cpu_cfs_/ {
      c = lbl($4, "container"); if (c == "" || c == "POD") next
      k = lbl($4, "pod") "/" c; id = lbl($4, "id"); if (id == "") id = k
      name[id] = k; ipod[id] = lbl($4, "pod"); ic[id] = c
      if ($3 ~ /throttled/) t[s, id] = $5; else p[s, id] = $5
    }
    $1 == "usage" && $3 == "cpu" { k = $2 "/" lbl($4, "container"); u[k] += $5; un[k]++ }
    s == 2 && $1 == "limit" && $3 == "cpu" { lim[$2 "/" lbl($4, "container")] = $5 }
    END {
      fix = "Raise the CPU limit of the throttled components."
      for (id in name) {
        if (!((1, id) in p) || !((2, id) in p)) continue
        seen++
        dp = p[2, id] - p[1, id]; dt = t[2, id] - t[1, id]
        if (dp <= 0 || dt < 0 || dt > dp) continue
        pct = 100 * dt / dp
        if (pct >= 50) { out("FAIL", sprintf("%s throttled in %.0f%% of CPU periods", name[id], pct)); bad++; raise(ipod[id], ic[id], "cpu", lim[name[id]], 2) }
        else if (pct >= 25) { out("WARN", sprintf("%s throttled in %.0f%% of CPU periods", name[id], pct)); bad++; raise(ipod[id], ic[id], "cpu", lim[name[id]], 1.5) }
      }
      if (seen) {
        if (bad && !suggestions()) out("FIX", "", fix)
        if (!bad) out("OK", "No container is throttled in more than 25% of CPU periods")
        exit
      }
      out("WARN", "Could not read CPU throttling from the nodes, showing CPU usage against the limit instead", "Reading CPU throttling needs get permission on nodes/proxy. Usage against the limit is an approximation: a container can be throttled while its average usage is below the limit.")
      for (k in lim) {
        if (!(k in un) || lim[k] <= 0) continue
        useen++; avg = u[k] / un[k]
        if (avg / lim[k] >= 0.9) {
          out("WARN", sprintf("%s uses %.2f of its %g CPU limit (approximation)", k, avg, lim[k])); bad++
          split(k, x, "/"); raise(x[1], x[2], "cpu", lim[k], 1.5)
        }
      }
      if (bad && !suggestions()) out("FIX", "", "Raise the CPU limit of the components close to their limit.")
      if (!useen) out("WARN", "Could not read CPU usage either", "Reading CPU usage needs get permission on pods.metrics.k8s.io and a running metrics-server.")
      else if (!bad) out("OK", "No container uses more than 90% of its CPU limit (approximation)")
    }'
}

check_memory() {
  check '
    s == 2 && $1 == "cadvisor" && $3 ~ /^container_(memory_working_set_bytes|spec_memory_limit_bytes)$/ {
      c = lbl($4, "container"); if (c == "" || c == "POD") next
      k = lbl($4, "pod") "/" c; id = lbl($4, "id"); if (id == "") id = k
      name[id] = k; ipod[id] = lbl($4, "pod"); ic[id] = c
      if ($3 ~ /working_set/) ws[id] = $5; else lim[id] = $5
    }
    s == 2 && $1 == "usage" && $3 == "memory" { uws[$2 "/" lbl($4, "container")] = $5 }
    s == 2 && $1 == "limit" && $3 == "memory" { ulim[$2 "/" lbl($4, "container")] = $5 }
    END {
      fix = "Raise the memory limit of the components close to their limit."
      for (id in name) {
        seen++
        if (lim[id] > 0 && ws[id] / lim[id] >= 0.95) { out("WARN", sprintf("%s uses %s of its %s limit", name[id], mib(ws[id]), mib(lim[id]))); bad++; raise(ipod[id], ic[id], "memory", lim[id], 1.5) }
      }
      if (!seen) {
        for (k in ulim) {
          if (!(k in uws) || ulim[k] <= 0) continue
          seen++
          if (uws[k] / ulim[k] >= 0.95) {
            out("WARN", sprintf("%s uses %s of its %s limit", k, mib(uws[k]), mib(ulim[k]))); bad++
            split(k, x, "/"); raise(x[1], x[2], "memory", ulim[k], 1.5)
          }
        }
      }
      if (bad && !suggestions()) out("FIX", "", fix)
      if (!seen) out("WARN", "No memory metrics read", "Reading memory usage needs get permission on nodes/proxy or on pods.metrics.k8s.io.")
      else if (!bad) out("OK", "No container uses more than 95% of its memory limit")
    }'
}

check_volumes() {
  check '
    s == 2 && $1 == "kubelet" {
      k = lbl($4, "persistentvolumeclaim"); keys[k] = 1
      if ($3 ~ /used/) u[k] = $5; else cap[k] = $5
    }
    END {
      for (k in keys) {
        if (cap[k] <= 0) continue
        seen++; pct = 100 * u[k] / cap[k]
        if (pct < 80) continue
        out(pct >= 90 ? "FAIL" : "WARN", sprintf("Volume %s is %.0f%% full", k, pct), "Reduce the retention of the data, or resize the volume, see Resizing storage on the Data retention page."); bad++
        out("FIX", "", sprintf("Resize %s from %.0fGi to at least %dGi, so it is at most 70%% full.", k, cap[k] / 1073741824, ceil(u[k] / 0.7 / 1073741824)))
      }
      if (!seen) out("WARN", "No volume metrics read from the nodes", "Reading node metrics needs get permission on nodes/proxy.")
      else if (!bad) out("OK", sprintf("All %d volumes are less than 80%% full", seen))
    }'
}

check_receiver() {
  check '
    $1 != "receiver" && $1 != "limit" { next }
    $1 == "receiver" && !($2 in pods) { pods[$2] = 1; np++ }
    $3 == "receiver_agent_request_total" { req[s, $2, lbl($4, "valid_api_key")] += $5; has[s, $2] = 1 }
    $1 == "limit" && $3 == "memory" && lbl($4, "container") == "receiver" { rlim[$2] = $5 }
    s == 2 && $3 == "stackstate_receiver_unique_element_passed_count" && lbl($4, "element_type") == "agent" { agents[$2] = $5 }
    s == 2 && $3 == "stackstate_receiver_memory_limiter_claimed_size" { claimed[$2] = $5 }
    s == 2 && $3 == "stackstate_receiver_memory_limiter_limit" { limit[$2] = $5 }
    s == 2 && $3 ~ /^stackstate_receiver_(unique_element|element_create)_passed_(count|max)$/ {
      b = ($3 ~ /unique/) ? "unique" : "hourly"; k = $2 SUBSEP b SUBSEP lbl($4, "element_type")
      if ($3 ~ /_count$/) bc[k] = $5; else { bm[k] = $5; bk[k] = 1 }
    }
    $3 == "stackstate_receiver_events_rejected_size_total" { rej[s, lbl($4, "element_type")] += $5; rt[lbl($4, "element_type")] = 1 }
    END {
      uvar["component"] = "maxComponentsPerHost"; uvar["relation"] = "maxRelationsPerHost"; uvar["connection"] = "maxConnectionObservationsPerHost"
      hvar["component"] = "maxNewComponentsHourlyPerHost"; hvar["relation"] = "maxNewRelationsHourlyPerHost"
      hdef["component"] = 100; hdef["relation"] = 300
      for (p in pods) {
        if (!((1, p) in has) || !((2, p) in has)) { out("WARN", p ": could not read agent requests in both samples", "Check that you can port-forward to the Receiver pods."); continue }
        ok = req[2, p, "true"] - req[1, p, "true"]; inv = req[2, p, "false"] - req[1, p, "false"]
        total += ok
        if (ok <= 0) out("FAIL", p ": no agent requests with a valid API key during the check", "Check the agent logs and the ingress or route in front of the Router.")
        else out("OK", sprintf("%s: %.0f agent requests per minute", p, permin(ok)))
        if (inv > 0) out("WARN", sprintf("%s: %.0f requests per minute with an invalid API key", p, permin(inv)), "Check the API key in the configuration of the agents that send data.")
        if (limit[p] > 0 && claimed[p] / limit[p] >= 0.8) {
          out("WARN", sprintf("%s: memory limiter at %.0f%%", p, 100 * claimed[p] / limit[p]), "Add memory to the Receiver.")
          raise(p, "receiver", "memory", rlim[p], 1.5)
        }
      }
      for (k in bk) {
        if (bm[k] <= 0) continue
        split(k, x, SUBSEP); r = bc[k] / bm[k]
        if (r < 0.95) { budgets++; continue }
        out("WARN", sprintf("%s: %s %s budget at %.0f%% (%d of %d)", x[1], x[3], x[2], 100 * r, bc[k], bm[k]), "Check for limited agents with sts agent list first, see Receiver element budget saturated on the Tune data ingestion for your workload page.")
        env = "CONFIG_FORCE_stackstate_receiver_processAgent_"
        if (x[2] == "unique" && (x[3] in uvar) && agents[x[1]] > 0) {
          per = bm[k] / agents[x[1]]
          out("FIX", "", sprintf("Set %s%s in %s.extraEnv.open from %d to %d.", env, uvar[x[3]], vkey(x[1], "receiver"), per, ceil(1.5 * per)))
        } else if (x[2] == "hourly" && (x[3] in hvar))
          out("FIX", "", sprintf("Set %s%s in %s.extraEnv.open to 1.5 times its current value, %d by default.", env, hvar[x[3]], vkey(x[1], "receiver"), hdef[x[3]]))
      }
      suggestions()
      if (budgets) out("OK", (length(bk) > budgets) ? "Other element budgets are below 95%" : "Element budgets are below 95%")
      for (t in rt) {
        d = rej[2, t] - rej[1, t]
        if (d > 0) out("WARN", sprintf("%s rejected: %s per minute", t, mib(permin(d))), "Increase the Elasticsearch disk size, reduce the log retention or reduce noisy log sources.")
        else out("OK", sprintf("No %s rejected during the check (%s since the Receiver started)", t, mib(rej[2, t])))
      }
      if (!np) out("FAIL", "No Receiver metrics read", "Check that the Receiver pods run and that you can port-forward to them.")
    }'
}

check_kafka() {
  check '
    $1 == "consumer" && $3 == "kafka_consumer_consumer_fetch_manager_metrics_records_lag" {
      t = lbl($4, "topic"); if (t == "") next
      lag[s, t] += $5; topics[t] = 1; got[s] = 1
      if (s == 2 && index(" " owner[t] " ", " " $2 " ") == 0) owner[t] = owner[t] (owner[t] == "" ? "" : " ") $2
    }
    END {
      if (!got[2]) { out("FAIL", "No consumer lag read", "Check that the consumer pods run and that you can port-forward to them."); exit }
      for (t in topics) {
        l1 = lag[1, t]; l2 = lag[2, t]
        if ((l2 > 1000 && l2 > l1) || l2 > 100000) {
          out("WARN", sprintf("%s: lag %d, %s", t, l2, l2 > l1 ? "growing" : "shrinking"), "Check CPU throttling and memory of " owner[t] " and add resources to it.")
          bad++
        }
      }
      if (!bad) out("OK", "No topic has growing or high consumer lag")
    }'
}

check_vmagent() {
  check '
    $1 != "vmagent" { next }
    { got[s] = 1 }
    $3 == "vm_persistentqueue_bytes_pending" { pend[s] += $5 }
    $3 ~ /dropped_total$/ { drop[s, $3] += $5; dn[$3] = 1 }
    $3 == "vmagent_remotewrite_retries_count_total" { retry[s] += $5 }
    $3 == "vmagent_remotewrite_requests_total" { if (lbl($4, "status_code") == "2XX") okreq[s] += $5; else errreq[s] += $5 }
    END {
      if (!got[2]) { out("FAIL", "No vmagent metrics read", "Check that the vmagent pod runs and that you can port-forward to it."); exit }
      fixvm = "VictoriaMetrics accepts data slower than it arrives. Check the VictoriaMetrics section and add resources to VictoriaMetrics."
      for (m in dn) if (drop[2, m] > drop[1, m]) { out("FAIL", sprintf("%s grew by %d", m, drop[2, m] - drop[1, m]), fixvm); bad++ }
      if (pend[2] > 0 && pend[2] > pend[1]) { out("WARN", "Persistent queue is growing, " mib(pend[2]) " pending", fixvm); bad++ }
      if (retry[2] > retry[1]) { out("WARN", sprintf("%d remote write retries", retry[2] - retry[1]), fixvm); bad++ }
      if (errreq[2] > errreq[1]) { out("WARN", sprintf("%d failed remote write requests", errreq[2] - errreq[1]), fixvm); bad++ }
      if (okreq[2] <= okreq[1]) { out("FAIL", "No successful writes to VictoriaMetrics during the check", fixvm); bad++ }
      if (!bad) out("OK", sprintf("%.0f writes per minute to VictoriaMetrics, no queue, retries or drops", permin(okreq[2] - okreq[1])))
    }'
}

check_otel() {
  check '
    $1 == "limit" && $3 == "memory" && lbl($4, "container") == "opentelemetry-collector" { olim[$2] = $5; next }
    $1 != "otel" { next }
    { got[s] = 1; pod = $2; m = $3; sub(/_total$/, "", m) }
    m ~ /^otelcol_receiver_refused_/ { sub(/^otelcol_receiver_refused_/, "", m); k = m " on receiver " lbl($4, "receiver"); ref[s, k] += $5; rk[k] = 1 }
    m ~ /^otelcol_exporter_send_failed_/ { sub(/^otelcol_exporter_send_failed_/, "", m); k = m " on exporter " lbl($4, "exporter"); fail[s, k] += $5; fk[k] = 1 }
    m ~ /^otelcol_processor_dropped_/ { sub(/^otelcol_processor_dropped_/, "", m); k = m " on processor " lbl($4, "processor"); drp[s, k] += $5; dk[k] = 1 }
    s == 2 && m == "otelcol_exporter_queue_size" { qs[lbl($4, "exporter")] += $5 }
    s == 2 && m == "otelcol_exporter_queue_capacity" { qc[lbl($4, "exporter")] += $5 }
    END {
      if (!got[2]) { out("FAIL", "No OpenTelemetry Collector metrics read", "Check that the collector pod runs and that you can port-forward to it."); exit }
      fixdest = "Check the exporter destination: clickhousests is ClickHouse, prometheusremotewrite/victoria-metrics is vmagent and VictoriaMetrics, sts_kafka_exporter is Kafka."
      for (k in rk) if (ref[2, k] > ref[1, k]) { out("WARN", sprintf("Refused %.0f %s per minute", permin(ref[2, k] - ref[1, k]), k), "Add memory and CPU to the OpenTelemetry Collector."); bad++; refused++ }
      for (k in fk) if (fail[2, k] > fail[1, k]) { out("FAIL", sprintf("Failed to send %.0f %s per minute", permin(fail[2, k] - fail[1, k]), k), fixdest); bad++ }
      for (k in dk) if (drp[2, k] > drp[1, k]) { out("WARN", sprintf("Dropped %.0f %s per minute", permin(drp[2, k] - drp[1, k]), k), "Add memory and CPU to the OpenTelemetry Collector."); bad++; refused++ }
      for (e in qc) if (qc[e] > 0 && qs[e] / qc[e] >= 0.8) { out("WARN", sprintf("Export queue of %s is %.0f%% full", e, 100 * qs[e] / qc[e]), fixdest); bad++ }
      if (refused) raise(pod, "opentelemetry-collector", "memory", olim[pod], 1.5)
      suggestions()
      if (!bad) out("OK", "No refused, failed or dropped data, export queues below 80%")
    }'
}

check_clickhouse() {
  check '
    $1 == "clickhouse" { v[s, $3] += $5; got[s] = 1; pod = $2 }
    $1 == "limit" && lbl($4, "container") == "clickhouse" { cl[$3] = $5 }
    END {
      if (!got[2]) { out("WARN", "No ClickHouse metrics read", "Check that the ClickHouse pod runs and that you can port-forward to it."); exit }
      fix = "ClickHouse cannot merge data as fast as it arrives. Add CPU and memory to ClickHouse and check its disk usage."
      r = v[2, "ClickHouseProfileEvents_RejectedInserts"] - v[1, "ClickHouseProfileEvents_RejectedInserts"]
      d = v[2, "ClickHouseProfileEvents_DelayedInserts"] - v[1, "ClickHouseProfileEvents_DelayedInserts"]
      if (r > 0) out("FAIL", sprintf("%d rejected inserts", r), fix)
      if (d > 0) out("WARN", sprintf("%d delayed inserts", d), fix)
      if (r > 0 || d > 0) { raise(pod, "clickhouse", "cpu", cl["cpu"], 1.5); raise(pod, "clickhouse", "memory", cl["memory"], 1.5); suggestions() }
      else out("OK", "No rejected or delayed inserts")
    }'
}

check_vm() {
  check '
    $1 == "limit" && $3 == "memory" && lbl($4, "container") ~ /^victoria-metrics-[01]-server$/ { vlim[$2] = $5; vc[$2] = lbl($4, "container"); next }
    $1 != "vm" { next }
    !($2 in pods) { pods[$2] = 1; np++ }
    { got[s, $2] = 1 }
    $3 == "vm_slow_row_inserts_total" { slow[s, $2] += $5 }
    $3 == "vm_rows_inserted_total" { rows[s, $2] += $5 }
    $3 == "vm_rows_ignored_total" { ign[s, $2] += $5 }
    END {
      for (p in pods) {
        if (!((1, p) in got) || !((2, p) in got)) { out("WARN", p ": could not read metrics in both samples", "Check that you can port-forward to the VictoriaMetrics pods."); continue }
        r = rows[2, p] - rows[1, p]
        if (r <= 0) { out("FAIL", p ": no rows inserted during the check", "Check the vmagent section and the vmagent logs."); continue }
        pct = 100 * (slow[2, p] - slow[1, p]) / r
        if (pct > 5) { out("WARN", sprintf("%s: %.0f%% slow inserts", p, pct), "VictoriaMetrics does not have enough memory to cache the active series. Add memory to VictoriaMetrics."); raise(p, vc[p], "memory", vlim[p], 1.5) }
        else out("OK", sprintf("%s: %.0f rows per minute, %.1f%% slow inserts", p, permin(r), pct))
        i = ign[2, p] - ign[1, p]
        if (i > 0) out("WARN", sprintf("%s: %d rows ignored on ingestion", p, i), "Check the VictoriaMetrics logs for the reason, for example too many labels.")
      }
      suggestions()
      if (!np) out("FAIL", "No VictoriaMetrics metrics read", "Check that the VictoriaMetrics pods run and that you can port-forward to them.")
    }'
}

check_elasticsearch() {
  local f="$WORK/sample-2/elasticsearch"
  if [ -z "$ES_POD" ] || [ ! -s "$f" ]; then
    printf 'WARN\tCould not read Elasticsearch\tCheck that the Elasticsearch pods run and that you can port-forward to them.\n'
    return
  fi
  awk '
    /"status"/ {
      st = $0; sub(/.*"status":"/, "", st); sub(/".*/, "", st)
      if (st == "red") print "FAIL\tCluster health is red\tCheck the Elasticsearch logs and the unassigned shards."
      else if (st == "yellow") print "WARN\tCluster health is yellow\tCheck the Elasticsearch logs and the unassigned shards."
      else print "OK\tCluster health is " st
      next
    }
    NF >= 2 && $2 ~ /^[0-9]+$/ {
      if ($2 < 80) { printf "OK\t%s disk is %d%% full\n", $1, $2; next }
      printf "WARN\t%s disk is %d%% full\tWhen disk usage is high, the Receiver rejects more logs. Reduce the log retention, or resize the Elasticsearch volumes, see Resizing storage on the Data retention page.\n", $1, $2
      if ($3 ~ /^[0-9]+$/) { n = $3 * $2 / 70; printf "FIX\t\tResize the Elasticsearch volumes from %dGi to at least %dGi, so they are at most 70%% full.\n", $3, (n == int(n)) ? n : int(n) + 1 }
    }' "$f"
}

echo "Checking the data ingestion pipeline in context $CONTEXT, namespace $NAMESPACE"
if [ -n "$(running_pods 'app.kubernetes.io/component=sync')" ]; then
  echo "Profile: HA"
elif [ -n "$(running_pods 'app.kubernetes.io/component in (server,receiver)')" ]; then
  echo "Profile: non-HA"
else
  echo "No SUSE Observability pods found in namespace $NAMESPACE. Exiting."
  exit 1
fi
discover
echo "Taking the first sample"
sample 1
echo "Waiting $INTERVAL seconds"
sleep "$INTERVAL"
echo "Taking the second sample"
sample 2
SECS=$(( $(cat "$WORK/sample-2/time") - $(cat "$WORK/sample-1/time") ))
: > "$WORK/levels"

wants pods && check_pods | section "Pods"
wants cpu && check_cpu | section "CPU throttling"
wants memory && check_memory | section "Memory"
wants volumes && check_volumes | section "Volumes"
wants receiver && check_receiver | section "Receiver"
wants kafka && check_kafka | section "Kafka consumer lag"
wants vmagent && check_vmagent | section "vmagent"
wants otel && check_otel | section "OpenTelemetry Collector"
wants clickhouse && check_clickhouse | section "ClickHouse"
wants victoriametrics && check_vm | section "VictoriaMetrics"
wants elasticsearch && check_elasticsearch | section "Elasticsearch"

FAILS=$(grep -c '^FAIL$' "$WORK/levels")
WARNS=$(grep -c '^WARN$' "$WORK/levels")
echo
echo "Summary: $FAILS failed, $WARNS warnings"
touch "$WORK/fixes"
SHORT=$(sed -nE 's/^Raise ([^ ]+)\.resources\.limits\..*/\1/p' "$WORK/fixes" | sort -u | wc -l)
if [ "$SHORT" -ge 3 ]; then
  echo "$SHORT components are short of resources. Consider the next sizing profile instead of raising their limits one by one. A profile change takes more than a helm upgrade, see the Change the sizing profile page in the SUSE Observability documentation."
fi
if [ "$FAILS" -gt 0 ] || [ "$WARNS" -gt 0 ]; then
  echo "After a change, wait until the consumer lag stops growing and run the check again."
fi
if $KEEP; then
  echo "Samples kept in $WORK"
fi
if [ "$FAILS" -gt 0 ] || [ "$WARNS" -gt 0 ]; then
  exit 1
fi
