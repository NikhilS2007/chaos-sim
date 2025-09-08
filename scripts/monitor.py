#!/usr/bin/env python3
"""
Monitor: prints health/status of containers and writes csv logs.
Usage:
  python scripts/monitor.py --interval 5 --project chaos-sim
"""
import argparse
import csv
import os
import time
from datetime import datetime
import docker

def get_health(container):
    try:
        hc = container.attrs["State"].get("Health")
        if not hc:
            return "n/a"
        return hc.get("Status", "n/a")
    except Exception:
        return "n/a"

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--interval", type=int, default=5)
    p.add_argument("--project", default="chaos-sim")
    p.add_argument("--out", default="monitor_log.csv")
    args = p.parse_args()

    client = docker.from_env()

    write_header = not os.path.exists(args.out)
    f = open(args.out, "a", newline="")
    writer = csv.writer(f)
    if write_header:
        writer.writerow(["timestamp","name","status","health","restart_count"])

    try:
        while True:
            containers = client.containers.list(all=True)
            for c in containers:
                labels = c.attrs.get("Config", {}).get("Labels", {}) or {}
                proj = labels.get("com.docker.compose.project")
                if proj != args.project and not c.name.startswith("chaos_"):
                    continue
                c.reload()
                state = c.attrs["State"]
                health = get_health(c)
                restarts = state.get("RestartCount", 0)
                row = [datetime.utcnow().isoformat(), c.name, c.status, health, restarts]
                print("[monitor]", row, flush=True)
                writer.writerow(row)
            f.flush()
            time.sleep(args.interval)
    finally:
        f.close()

if __name__ == "__main__":
    main()
