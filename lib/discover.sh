#!/usr/bin/env bash
# Host liveness check. Uses nmap -sn when present; otherwise treats a host
# as "up" if a small set of commonly-open ports answers a TCP connect
# within a short timeout (works without root and without ping).

LIVENESS_PORTS=(22 80 443 445 3389)

host_is_up() {
  local host="$1"
  if have nmap; then
    nmap -sn -PE -PS22,80,443 "$host" 2>/dev/null | grep -q "Host is up" && return 0
    return 1
  fi
  local p
  for p in "${LIVENESS_PORTS[@]}"; do
    timeout 1 bash -c "exec 3<>/dev/tcp/$host/$p" 2>/dev/null && return 0
  done
  return 1
}

expand_targets() {
  local spec="$1"
  if have nmap; then
    nmap -sL -n "$spec" 2>/dev/null | awk '/Nmap scan report/{print $NF}' | tr -d '()'
    return 0
  fi
  if have python3; then
    python3 - "$spec" << 'PY'
import ipaddress, sys
spec = sys.argv[1]
try:
    net = ipaddress.ip_network(spec, strict=False)
    for ip in net.hosts():
        print(ip)
except ValueError:
    print(spec)
PY
    return 0
  fi
  printf '%s\n' "$spec"
}
