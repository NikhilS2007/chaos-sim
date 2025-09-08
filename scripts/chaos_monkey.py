#!/usr/bin/env python3
"""
Chaos Monkey: randomly kills/pauses/restarts containers in a compose project.
Usage:
  python scripts/chaos_monkey.py --interval 20 --modes kill pause restart --project chaos-sim
"""
import argparse
import random
import time
from datetime import datetime
import docker

ACTIONS = {
    "kill": lambda c: c.kill(),
    "pause": lambda c: c.pause(),
    "unpause": lambda c: c.unpause(),
    "restart": lambda c: c.restart(),
}

def pick_target(containers):
    running = [c for c in containers if c.status in ("running", "paused")]
    return random.choice(running) if running else random.choice(containers)

def log(msg):
    ts = datetime.utcnow().isoformat()
    print(f"[chaos] {ts} {msg}", flush=True)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--interval", type=int, default=20, help="seconds between injections")
    p.add_argument("--modes", nargs="+", default=["kill","pause","restart"],
                   help="subset of actions: kill pause restart unpause")
    p.add_argument("--project", default="chaos-sim", help="compose project name (for filtering)")
    p.add_argument("--prob_unpause", type=float, default=0.5, help="probability to unpause if paused")
    args = p.parse_args()

    client = docker.from_env()

    while True:
        containers = client.containers.list(all=True)
        scoped = []
        for c in containers:
            labels = c.attrs.get("Config", {}).get("Labels", {}) or {}
            proj = labels.get("com.docker.compose.project")
            if proj == args.project or c.name.startswith("chaos_"):
                scoped.append(c)
        if not scoped:
            log("no containers found for project; sleepingâ€¦")
            time.sleep(args.interval)
            continue

        action = random.choice(args.modes)
        target = pick_target(scoped)

        paused = [c for c in scoped if c.status == "paused"]
        if paused and random.random() < args.prob_unpause:
            t = random.choice(paused)
            log(f"unpause -> {t.name}")
            try:
                ACTIONS["unpause"](t)
            except Exception as e:
                log(f"unpause failed: {e}")
            time.sleep(args.interval)
            continue

        log(f"{action} -> {target.name} (status={target.status})")
        try:
            ACTIONS[action](target)
        except Exception as e:
            log(f"action failed: {e}")
        time.sleep(args.interval)

if __name__ == "__main__":
    main()
