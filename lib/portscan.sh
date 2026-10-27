#!/usr/bin/env bash
# Port-scanning backends. Prefers nmap (fast, accurate service/version
# detection); falls back to a pure-bash TCP connect scan using /dev/tcp
# when nmap isn't installed, so the tool still works on a bare system.

# expand_ports "22,80,8000-8010" -> one port per line
expand_ports() {
  local spec="$1" part
  IFS=',' read -ra parts <<< "$spec"
  for part in "${parts[@]}"; do
    if [[ "$part" == *-* ]]; then
      local lo="${part%-*}" hi="${part#*-}" p
      for ((p=lo; p<=hi; p++)); do printf '%s\n' "$p"; done
    else
      printf '%s\n' "$part"
    fi
  done
}

# bash_connect_scan_one HOST PORT TIMEOUT -> prints "PORT\topen" on success
bash_connect_scan_one() {
  local host="$1" port="$2" timeout="${3:-1}"
  if timeout "$timeout" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    printf '%s\topen\n' "$port"
    return 0
  fi
  return 1
}
export -f bash_connect_scan_one

# bash_grab_banner HOST PORT TIMEOUT -> first line the service sends, if any
bash_grab_banner() {
  local host="$1" port="$2" timeout="${3:-2}"
  if have nc; then
    timeout "$timeout" nc -w "$timeout" "$host" "$port" </dev/null 2>/dev/null | head -c 200 | tr -d '\0' | head -1
    return 0
  fi
  ( exec 3<>"/dev/tcp/$host/$port" ) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    exec 3<>"/dev/tcp/$host/$port"
    timeout "$timeout" head -c 200 <&3 2>/dev/null | tr -d '\0' | head -1
    exec 3<&- 3>&- 2>/dev/null
  fi
}

# scan_host_nmap HOST PORTS EXTRA -> writes nmap's greppable output to stdout
scan_host_nmap() {
  local host="$1" ports="$2" extra="$3"
  # -Pn: skip host-discovery ping (we did our own liveness check already)
  # -sT: TCP connect scan — needs no special privileges, unlike -sS
  nmap -Pn -sT -p "$ports" --open $extra -oG - "$host" 2>/dev/null
}

# scan_host_bash HOST PORTS TIMEOUT CONCURRENCY -> "PORT\topen" lines
scan_host_bash() {
  local host="$1" ports="$2" timeout="$3" conc="$4"
  expand_ports "$ports" | xargs -P "$conc" -I{} bash -c \
    'bash_connect_scan_one "$0" "$1" "$2"' "$host" {} "$timeout"
}
