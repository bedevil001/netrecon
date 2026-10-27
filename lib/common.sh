#!/usr/bin/env bash
# Shared helpers: logging, dependency checks, input validation.

NR_VERSION="1.0.0"

c_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
c_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

log_info()  { printf '[*] %s\n' "$*"; }
log_ok()    { c_green "[+] $*"; }
log_warn()  { c_yellow "[!] $*"; }
log_err()   { c_red "[x] $*" >&2; }

die() { log_err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Only accepts RFC1918 / loopback / link-local private ranges, or hostnames
# that resolve to one. This is a deliberate safety rail for a learning/CV
# project: it keeps the default build from being pointed at arbitrary public
# IPs without the operator explicitly overriding it (see --allow-public).
is_private_ipv4() {
  local ip="$1" IFS=.
  read -r a b c d <<< "$ip"
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$c" =~ ^[0-9]+$ && "$d" =~ ^[0-9]+$ ]] || return 1
  (( a==10 )) && return 0
  (( a==172 && b>=16 && b<=31 )) && return 0
  (( a==192 && b==168 )) && return 0
  (( a==127 )) && return 0
  (( a==169 && b==254 )) && return 0
  return 1
}

resolve_host() {
  local host="$1"
  if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$host"; return 0
  fi
  if have getent; then
    getent ahostsv4 "$host" 2>/dev/null | awk '{print $1; exit}'
  elif have python3; then
    python3 -c "import socket,sys; print(socket.gethostbyname(sys.argv[1]))" "$host" 2>/dev/null
  fi
}
