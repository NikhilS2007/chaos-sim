# setup.ps1 — scaffolds the entire Chaos Engineering Simulator repo (Windows/PowerShell)

$ErrorActionPreference = "Stop"

# 1) Create folders
New-Item -ItemType Directory -Force -Path .\services\api | Out-Null
New-Item -ItemType Directory -Force -Path .\services\worker | Out-Null
New-Item -ItemType Directory -Force -Path .\scripts | Out-Null

# 2) docker-compose.yml
@"
version: "3.8"

x-health-defaults: &health_defaults
  interval: 5s
  timeout: 3s
  retries: 5

services:
  api:
    build: ./services/api
    container_name: chaos_api
    environment:
      - FLASK_ENV=production
    ports:
      - "5000:5000"
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:5000/health"]
      <<: *health_defaults
    restart: unless-stopped

  worker:
    build: ./services/worker
    container_name: chaos_worker
    depends_on:
      api:
        condition: service_healthy
    environment:
      - API_URL=http://api:5000
    healthcheck:
      test: ["CMD", "python", "-c", "import os,sys; sys.exit(0)"]
      <<: *health_defaults
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: chaos_redis
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      <<: *health_defaults
    restart: unless-stopped
"@ | Set-Content -Encoding UTF8 .\docker-compose.yml

# 3) services/api/Dockerfile
@"
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY app.py /app/app.py
RUN pip install --no-cache-dir flask gunicorn
EXPOSE 5000
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:5000", "app:app"]
"@ | Set-Content -Encoding UTF8 .\services\api\Dockerfile

# 4) services/api/app.py
@"
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.get("/")
def root():
    return jsonify({"service": "api", "message": "Hello from API"})

@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200

@app.get("/work")
def work():
    total = sum(i*i for i in range(10000))
    return jsonify({"result": total})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
"@ | Set-Content -Encoding UTF8 .\services\api\app.py

# 5) services/worker/Dockerfile
@"
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY worker.py /app/worker.py
RUN pip install --no-cache-dir requests
CMD ["python", "worker.py"]
"@ | Set-Content -Encoding UTF8 .\services\worker\Dockerfile

# 6) services/worker/worker.py
@"
import os
import time
import requests

API_URL = os.getenv("API_URL", "http://api:5000")

if __name__ == "__main__":
    print("[worker] starting… API_URL=", API_URL, flush=True)
    while True:
        try:
            r = requests.get(f"{API_URL}/work", timeout=3)
            if r.ok:
                print("[worker] work ok:", r.json(), flush=True)
            else:
                print("[worker] work failed status:", r.status_code, flush=True)
        except Exception as e:
            print("[worker] error:", e, flush=True)
        time.sleep(2)
"@ | Set-Content -Encoding UTF8 .\services\worker\worker.py

# 7) scripts/chaos_monkey.py
@"
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
            log("no containers found for project; sleeping…")
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
"@ | Set-Content -Encoding UTF8 .\scripts\chaos_monkey.py

# 8) scripts/monitor.py
@"
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
"@ | Set-Content -Encoding UTF8 .\scripts\monitor.py

# 9) scripts/recover.py
@"
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

    log("listening for events…")
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
                log(f"event: {status} -> {name} :: attempting recovery…")
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
"@ | Set-Content -Encoding UTF8 .\scripts\recover.py

# 10) Python requirements
@"
docker
requests
"@ | Set-Content -Encoding UTF8 .\requirements.txt

# 11) .env (optional)
@"
# place environment overrides here if needed
"@ | Set-Content -Encoding UTF8 .\.env

# 12) README (short)
@"
# Chaos Engineering Simulator (Local Docker Compose)

Inject failures (kill, pause, restart) into a local multi-service stack, monitor health, and auto-recover.
- Services: API (Flask), Worker (requests), Redis
- Tools: chaos_monkey.py, monitor.py, recover.py

## Quick Run
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
docker compose up -d --build
python .\scripts\chaos_monkey.py --interval 20 --modes kill pause restart --project chaos-sim
python .\scripts\monitor.py --interval 5 --project chaos-sim
python .\scripts\recover.py --project chaos-sim
"@ | Set-Content -Encoding UTF8 .\README.md

Write-Host "✅ Project scaffolded. Next: create venv, install deps, and run Docker."
