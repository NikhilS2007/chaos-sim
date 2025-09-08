#!/usr/bin/env python3
"""
Recover: listens for docker events and restarts unhealthy/exited containers.
Usage:
  python scripts/recover.py --project chaos-sim
"""
import argparse
from datetime import datetime
import docker

def log(msg):
    print(f"[recover] {datetime.utcnow().isoformat()} {msg}", flush=True)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--project", default="chaos-sim")
    args = p.parse_args()

    client = docker.from_env()

    log("listening for eventsâ€¦")
    for ev in client.events(decode=True):
        try:
            if ev.get("Type") != "container":
                continue
            status = ev.get("status")  # e.g., 'die', 'health_status: unhealthy'
            actor = ev.get("Actor", {})
            attrs = actor.get("Attributes", {})
            name = attrs.get("name", "unknown")
            project = attrs.get("com.docker.compose.project")
            if project != args.project and not name.startswith("chaos_"):
                continue

            if status in ("die", "oom", "kill") or str(status).startswith("health_status"):
                log(f"event: {status} -> {name} :: attempting recoveryâ€¦")
                try:
                    c = client.containers.get(name)
                    c.restart()
                    log(f"restarted {name}")
                except Exception as e:
                    log(f"restart failed for {name}: {e}")
        except Exception:
            continue

if __name__ == "__main__":
    main()
