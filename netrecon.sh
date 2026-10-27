#!/usr/bin/env bash
# netrecon - a small, dependency-light network reconnaissance tool.
#
# Discovers live hosts in a target range, scans them for open TCP ports,
# grabs service banners where possible, and writes a text + HTML report.
# Uses nmap for speed/accuracy when it's installed; otherwise falls back
# to a pure-bash TCP connect scan so it still runs on a bare Linux box.
#
#   ./netrecon.sh -t 192.168.1.0/24 -p top
#   ./netrecon.sh -t targets.txt -p 1-1024 --banners
#   ./netrecon.sh -t 10.0.0.5 -p 22,80,443 --json
#
# Run with -h for full usage. AUTHORIZED TESTING ONLY — see README.md.
set -uo pipefail
IFS=$'\n\t'

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/lib/common.sh"
source "$SELF_DIR/lib/discover.sh"
source "$SELF_DIR/lib/portscan.sh"
source "$SELF_DIR/lib/report.sh"

usage() {
  cat << EOF
netrecon v$NR_VERSION - authorized-use network recon tool

Usage: $0 -t TARGET [options]

Targets:
  -t, --target SPEC      Host, CIDR (e.g. 10.0.0.0/24), or path to a file
                          with one host/CIDR per line. Required.

Ports:
  -p, --ports SPEC        "top" (default, ~30 common ports), a list
                          "22,80,443", a range "1-1024", or a mix.

Behavior:
  --banners               Grab a service banner from each open port.
  --skip-discovery         Scan every target without a liveness check first.
  --timeout SECONDS        Per-connection timeout (default: 1).
  --concurrency N           Parallel port checks per host, bash backend only
                          (default: 100).
  --allow-public           Permit scanning non-private/non-loopback targets.
                          Without this, public IPs are refused (safety rail
                          for a learning tool — see README.md).
  -o, --out DIR             Report output directory (default: ./reports/<ts>).
  --json                    Also write results.json.
  -y, --yes                 Skip the interactive authorization prompt.
  -h, --help                Show this help.

Examples:
  $0 -t 192.168.1.0/24 -p top --banners
  $0 -t scope.txt -p 1-65535 -o reports/full --json
EOF
}

TARGET_SPEC="" PORT_SPEC="top" DO_BANNERS=0 SKIP_DISCOVERY=0
TIMEOUT=1 CONCURRENCY=100 ALLOW_PUBLIC=0 OUTDIR="" WANT_JSON=0 ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET_SPEC="$2"; shift 2 ;;
    -p|--ports) PORT_SPEC="$2"; shift 2 ;;
    --banners) DO_BANNERS=1; shift ;;
    --skip-discovery) SKIP_DISCOVERY=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    --allow-public) ALLOW_PUBLIC=1; shift ;;
    -o|--out) OUTDIR="$2"; shift 2 ;;
    --json) WANT_JSON=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[[ -n "$TARGET_SPEC" ]] || { usage; die "missing -t/--target"; }
[[ "$PORT_SPEC" == "top" ]] && PORT_SPEC="$(cat "$SELF_DIR/config/top-ports.txt")"
NR_PORT_SPEC="$PORT_SPEC"

# ---------------------------------------------------------------- targets
RAW_SPECS=()
if [[ -f "$TARGET_SPEC" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs)"
    [[ -n "$line" ]] && RAW_SPECS+=("$line")
  done < "$TARGET_SPEC"
else
  RAW_SPECS=("$TARGET_SPEC")
fi

TARGETS=()
for spec in "${RAW_SPECS[@]}"; do
  while IFS= read -r h; do
    [[ -n "$h" ]] && TARGETS+=("$h")
  done < <(expand_targets "$spec")
done
[[ ${#TARGETS[@]} -gt 0 ]] || die "no targets resolved from: $TARGET_SPEC"

# ---------------------------------------------------------------- safety rail
if [[ "$ALLOW_PUBLIC" -eq 0 ]]; then
  for h in "${TARGETS[@]}"; do
    ip="$(resolve_host "$h")"
    [[ -n "$ip" ]] || die "could not resolve: $h"
    is_private_ipv4 "$ip" || die "refusing public target '$h' ($ip). Re-run with --allow-public only if you hold written authorization for it."
  done
fi

# ---------------------------------------------------------------- authorization prompt
if [[ "$ASSUME_YES" -eq 0 ]]; then
  echo
  c_yellow "You are about to scan ${#TARGETS[@]} host(s): ${TARGETS[*]:0:5}$([[ ${#TARGETS[@]} -gt 5 ]] && echo ' ...')"
  c_yellow "Only scan systems you own or are explicitly authorized to test."
  read -r -p "Type YES to confirm you have authorization: " confirm
  [[ "$confirm" == "YES" ]] || die "aborted — authorization not confirmed."
fi

# ---------------------------------------------------------------- setup
TS="$(date +%Y%m%d-%H%M%S)"
NR_OUTDIR="${OUTDIR:-$SELF_DIR/reports/$TS}"
mkdir -p "$NR_OUTDIR/raw"
NR_TARGET_COUNT=${#TARGETS[@]}
NR_HOST_ORDER=()

BACKEND="bash"; have nmap && BACKEND="nmap"
log_info "backend: $BACKEND | targets: $NR_TARGET_COUNT | ports: ${PORT_SPEC:0:60}$([[ ${#PORT_SPEC} -gt 60 ]] && echo ...)"

# ---------------------------------------------------------------- discovery
LIVE_HOSTS=()
if [[ "$SKIP_DISCOVERY" -eq 1 ]]; then
  LIVE_HOSTS=("${TARGETS[@]}")
else
  log_info "checking which hosts are up..."
  for h in "${TARGETS[@]}"; do
    if host_is_up "$h"; then LIVE_HOSTS+=("$h"); log_ok "$h is up"; fi
  done
  if [[ ${#LIVE_HOSTS[@]} -eq 0 ]]; then
    log_warn "no hosts responded to liveness checks; scanning all targets anyway (use --skip-discovery to silence this)"
    LIVE_HOSTS=("${TARGETS[@]}")
  fi
fi

# ---------------------------------------------------------------- scan
for host in "${LIVE_HOSTS[@]}"; do
  log_info "scanning $host ..."
  rawfile="$NR_OUTDIR/raw/$host.tsv"; : > "$rawfile"
  NR_HOST_ORDER+=("$host")

  if [[ "$BACKEND" == "nmap" ]]; then
    extra=""; [[ "$DO_BANNERS" -eq 1 ]] && extra="-sV --version-light"
    while read -r line; do
      [[ "$line" == *"Ports:"* ]] || continue
      ports_part="${line#*Ports: }"
      IFS=',' read -ra entries <<< "$ports_part"
      for e in "${entries[@]}"; do
        e="$(echo "$e" | xargs)"
        IFS='/' read -r port state proto owner svc rest <<< "$e"
        [[ "$state" == "open" ]] || continue
        printf '%s\t%s\t%s\t%s\n' "$port" "open" "${svc:-unknown}" "${rest:-}" >> "$rawfile"
      done
    done < <(scan_host_nmap "$host" "$PORT_SPEC" "$extra")
  else
    while IFS=$'\t' read -r port state; do
      svc="$(awk -F: -v p="$port" '$1==p{print $2}' "$SELF_DIR/config/services.tsv" 2>/dev/null)"
      banner=""
      [[ "$DO_BANNERS" -eq 1 ]] && banner="$(bash_grab_banner "$host" "$port" "$TIMEOUT" | tr -d '\r')"
      printf '%s\t%s\t%s\t%s\n' "$port" "$state" "${svc:-unknown}" "$banner" >> "$rawfile"
    done < <(scan_host_bash "$host" "$PORT_SPEC" "$TIMEOUT" "$CONCURRENCY")
  fi
  n_open=$(wc -l < "$rawfile" | xargs)
  [[ "$n_open" -gt 0 ]] && log_ok "$host: $n_open open port(s)" || log_info "$host: no open ports found"
done

# ---------------------------------------------------------------- report
write_text_report "$NR_OUTDIR/report.txt"
write_html_report "$NR_OUTDIR/report.html"
if [[ "$WANT_JSON" -eq 1 ]]; then
  {
    printf '{\n  "generated": "%s",\n  "ports_scanned": "%s",\n  "hosts": [\n' \
      "$(date -u +%FT%TZ)" "$NR_PORT_SPEC"
    for i in "${!NR_HOST_ORDER[@]}"; do
      host="${NR_HOST_ORDER[$i]}"
      printf '    {"host": "%s", "open_ports": [' "$host"
      first=1
      if [[ -s "$NR_OUTDIR/raw/$host.tsv" ]]; then
        while IFS=$'\t' read -r port state service banner; do
          [[ $first -eq 0 ]] && printf ','
          esc_banner="$(printf '%s' "$banner" | sed 's/\\/\\\\/g; s/"/\\"/g')"
          printf '{"port": %s, "service": "%s", "banner": "%s"}' "$port" "$service" "$esc_banner"
          first=0
        done < "$NR_OUTDIR/raw/$host.tsv"
      fi
      printf ']}'
      [[ "$i" -lt $((${#NR_HOST_ORDER[@]}-1)) ]] && printf ','
      printf '\n'
    done
    printf '  ]\n}\n'
  } > "$NR_OUTDIR/results.json"
fi

echo
log_ok "done. report: $NR_OUTDIR/report.txt  (and report.html$([[ $WANT_JSON -eq 1 ]] && echo ', results.json'))"
