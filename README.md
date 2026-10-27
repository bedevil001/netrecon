# netrecon

A lightweight, dependency-light **network reconnaissance tool** written in
Bash: host discovery, TCP port scanning, service/banner identification, and
text + HTML reporting. Built as a learning project to understand how tools
like nmap work under the hood, with a graceful fallback so it also runs on
a machine that doesn't have nmap installed.

## ⚠️ Authorized use only

This tool is for scanning **systems you own or have explicit written
permission to test** — a home lab, a CTF target, or a client engagement
with signed scope. Scanning systems you don't own or lack authorization
for is illegal in most jurisdictions (e.g. the U.S. Computer Fraud and
Abuse Act, the UK Computer Misuse Act) even when the scan itself is "just"
reconnaissance.

Built-in safeguards (not a substitute for authorization, but they reduce
accidental misuse):
- Refuses public/non-private IP targets unless you pass `--allow-public`.
- Always shows an interactive confirmation before scanning, unless you
  pass `-y`/`--yes` (for use in your own authorized, scripted pipelines).

## What it does

1. **Target expansion** — accepts a single host, a CIDR range, or a file
   with one host/CIDR per line.
2. **Host discovery** — checks which targets are actually live before
   scanning every port on every address, saving time.
3. **Port scanning** — TCP connect scan across a port list or range.
4. **Service identification** — maps common ports to service names, and
   (optionally) grabs a banner from each open port.
5. **Reporting** — writes a timestamped `report.txt`, `report.html`, and
   optional `results.json` per run.

## Two backends, same output shape

| | with `nmap` installed | without `nmap` |
|---|---|---|
| Host discovery | `nmap -sn` | TCP connect probe on common ports |
| Port scan | `nmap -sT` | pure-Bash `/dev/tcp` connect scan, parallelized with `xargs -P` |
| Service/version | `nmap -sV` | static port→service lookup table |
| Banner grab | nmap's own | `nc`, or raw `/dev/tcp` if `nc` isn't available |

The tool detects which backend is available and tells you at the start of
every run (`backend: nmap` or `backend: bash`). This was a deliberate
design choice: nmap is the industry-standard tool and the "real" backend,
but writing the fallback scanner by hand is what actually teaches you how
TCP connect scanning, timeouts, and concurrency work — which is the point
of a portfolio project like this one.

## Usage

```bash
chmod +x netrecon.sh

# scan your own LAN's common ports
./netrecon.sh -t 192.168.1.0/24 -p top

# scan one host, custom port range, grab banners
./netrecon.sh -t 192.168.1.10 -p 1-1024 --banners

# scan a list of authorized targets from a file, write JSON too
./netrecon.sh -t scope.txt -p top --json -o reports/engagement1
```

Run `./netrecon.sh -h` for the full option list.

### Example report output

```
--- 192.168.1.10 ---
  22/tcp   open   ssh          SSH-2.0-OpenSSH_9.6p1
  80/tcp   open   http
  445/tcp  open   smb
```

## Project layout

```
netrecon.sh         # entry point: arg parsing, orchestration
lib/common.sh        # logging, dependency checks, private-IP validation
lib/discover.sh       # host liveness + target/CIDR expansion
lib/portscan.sh        # nmap and bash-native scanning backends
lib/report.sh            # text + HTML report generation
config/top-ports.txt      # default port list (~30 commonly-exposed ports)
config/services.tsv        # port -> service name lookup (bash backend)
```

## Known limitations (good to mention if asked in an interview)

- The bash fallback backend does a full TCP connect (not a SYN scan), so
  it's slower and more visible in logs than `nmap -sS` — that trade-off is
  what lets it run without root privileges.
- Banner grabbing is passive: it reads what a service sends on connect.
  Protocols that wait for the client to speak first (HTTP, for one) need a
  protocol-aware probe to get a banner; the nmap backend handles this via
  `-sV`, the bash backend currently does not.
- No UDP scanning. TCP only.
- Host discovery without nmap relies on a handful of commonly-open TCP
  ports rather than ICMP, since unprivileged bash can't send raw ICMP
  pings — so a fully firewalled host can look "down" when it's actually up.
  `--skip-discovery` scans every target regardless.

## Ideas for extending it (good CV talking points / next steps)

- Add a UDP scan mode.
- Protocol-aware banner probes (send a minimal HTTP request on web ports).
- Compare detected open ports against a baseline to flag drift over time.
- A `--rate-limit` flag for noisier/slower stealth-friendly scanning.

## Why this is on my CV

This project demonstrates: Bash scripting at a non-trivial scale (argument
parsing, modular libraries, error handling), core TCP/IP and scanning
concepts (connect scans, timeouts, concurrency control), safe tool design
(authorization gates, safe defaults), and report generation for
communicating findings — the same lifecycle (recon → scan → report) used
in real penetration testing engagements.
