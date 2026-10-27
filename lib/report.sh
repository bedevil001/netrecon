#!/usr/bin/env bash
# Builds a timestamped text + HTML report from per-host TSV files written
# during the scan ($NR_OUTDIR/raw/<host>.tsv: port, state, service, banner).

write_text_report() {
  local outfile="$1"
  {
    printf 'netrecon scan report\n'
    printf 'generated: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    printf 'targets scanned: %s\n' "$NR_TARGET_COUNT"
    printf 'ports scanned: %s\n\n' "$NR_PORT_SPEC"
    for host in "${NR_HOST_ORDER[@]}"; do
      printf -- '--- %s ---\n' "$host"
      if [[ -s "$NR_OUTDIR/raw/$host.tsv" ]]; then
        while IFS=$'\t' read -r port state service banner; do
          printf '  %-7s %-6s %-12s %s\n' "$port/tcp" "$state" "$service" "$banner"
        done < "$NR_OUTDIR/raw/$host.tsv"
      else
        printf '  no open ports found\n'
      fi
      printf '\n'
    done
  } > "$outfile"
}

html_escape() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

write_html_report() {
  local outfile="$1"
  {
    cat << 'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<title>netrecon scan report</title>
<style>
  :root{color-scheme:light dark}
  body{font-family:ui-monospace,Menlo,Consolas,monospace;max-width:900px;margin:2rem auto;padding:0 1rem}
  h1{font-size:1.3rem} .meta{color:#888;margin-bottom:1.5rem}
  table{border-collapse:collapse;width:100%;margin-bottom:2rem}
  th,td{border:1px solid #8884;padding:.4rem .6rem;text-align:left;font-size:.9rem}
  th{background:#8882}
  .host{font-weight:bold;margin:1.2rem 0 .3rem}
  .empty{color:#888;font-style:italic}
</style></head><body>
HTML
    printf '<h1>netrecon scan report</h1>\n'
    printf '<div class="meta">generated %s UTC &middot; %s target(s) &middot; ports: %s</div>\n' \
      "$(date -u +'%Y-%m-%d %H:%M:%S')" "$NR_TARGET_COUNT" "$(printf '%s' "$NR_PORT_SPEC" | html_escape)"
    for host in "${NR_HOST_ORDER[@]}"; do
      printf '<div class="host">%s</div>\n' "$(printf '%s' "$host" | html_escape)"
      if [[ -s "$NR_OUTDIR/raw/$host.tsv" ]]; then
        printf '<table><tr><th>Port</th><th>State</th><th>Service</th><th>Banner</th></tr>\n'
        while IFS=$'\t' read -r port state service banner; do
          printf '<tr><td>%s/tcp</td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
            "$port" "$state" "$(printf '%s' "$service" | html_escape)" "$(printf '%s' "$banner" | html_escape)"
        done < "$NR_OUTDIR/raw/$host.tsv"
        printf '</table>\n'
      else
        printf '<p class="empty">no open ports found</p>\n'
      fi
    done
    printf '</body></html>\n'
  } > "$outfile"
}
