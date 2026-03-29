# Running the Pipeline with supervisord

supervisord manages the Ralph ceremonies loop as a supervised process — automatic
restart on crash, unified log files, and a web dashboard for monitoring.

## Install

```bash
pip install supervisor
# or, for an isolated install:
pipx install supervisor
```

## Start

```bash
# Default tool (claude)
scripts/supervisord-start.sh

# Use amp instead
scripts/supervisord-start.sh --tool amp
```

The script creates the `logs/` directory, starts supervisord in the background,
and prints initial status.

## Stop

```bash
scripts/supervisord-stop.sh
```

Sends SIGINT to the ralph process (equivalent to Ctrl-C), waits up to 30 seconds
for the current ceremony to finish cleanly, then shuts down supervisord.

## Check Status

```bash
supervisorctl -c supervisord.conf status
```

Example output:

```
ralph                            RUNNING   pid 12345, uptime 2:14:07
```

## Stream Logs

```bash
# Follow the supervisord-captured stdout/stderr
supervisorctl -c supervisord.conf tail -f ralph

# The ceremonies themselves write dated logs here:
ls prd/logs/
tail -f prd/logs/ceremonies-*.log
```

## Web Dashboard

Open [http://127.0.0.1:9001](http://127.0.0.1:9001) in a browser.

The dashboard shows process state, uptime, and lets you start/stop/restart
processes without touching the command line.

> **Security:** The dashboard is bound to `127.0.0.1` only and is not reachable
> from other machines. Change the default credentials (`admin` / `changeme`) in
> `supervisord.conf` before use — see the `[inet_http_server]` section.

## Reload Config After Changes

If you edit `supervisord.conf` while supervisord is running:

```bash
supervisorctl -c supervisord.conf reread
supervisorctl -c supervisord.conf update
```

`reread` detects the changes; `update` applies them (restarts affected processes).

## Change the Tool (claude → amp)

Edit the `environment=` line in `supervisord.conf`:

```ini
environment=RALPH_TOOL="amp"
```

Then reload:

```bash
supervisorctl -c supervisord.conf reread && supervisorctl -c supervisord.conf update
```

Or stop and restart with the `--tool` flag:

```bash
scripts/supervisord-stop.sh
scripts/supervisord-start.sh --tool amp
```

## How It Works

supervisord runs the ceremony loop in the foreground:

```bash
while scripts/ralph/ceremonies.sh --tool "$RALPH_TOOL"; do sleep 5; done
```

This mirrors `loop.sh` but keeps the process visible to supervisord so it can
track PID, uptime, and restart on crash. If `ceremonies.sh` exits non-zero
(fatal stop — machine needs human review), supervisord does **not** restart it
(`autorestart=unexpected` + `exitcodes=0`). Check `supervisorctl status` and
the log to see what stopped the machine.

## Log Files

All log files live in `logs/` (gitignored):

| File | Contents |
|---|---|
| `logs/supervisord.log` | supervisord daemon log |
| `logs/ralph.log` | stdout/stderr from the ceremony loop process |
| `logs/supervisor.sock` | unix socket for supervisorctl |
| `logs/supervisord.pid` | daemon PID |

Ceremony-level logs (individual run output) are still written by `ceremonies.sh`
to `prd/logs/ceremonies-<timestamp>.log`.
