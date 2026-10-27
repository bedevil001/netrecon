# Notes for future me

- `bash -n netrecon.sh lib/*.sh` before committing — quick syntax check.
- Test both backends if you add a feature: with nmap installed, and
  without (e.g. `PATH=/usr/bin:/bin` in a container that lacks nmap) to
  make sure the bash fallback still works.
- Keep the authorization prompt and the private-IP safety rail — don't
  remove them even for convenience during testing; use `-y` and
  `--allow-public` instead.
