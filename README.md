# Chaos Engineering Simulator (Local Docker Compose)

## ✨ Purpose
Modern systems must survive random failures.  
This project:
- Injects chaos (kill, pause, restart) into running containers.
- Monitors container health and status continuously.
- Automatically recovers failed services to reduce downtime.
- Logs metrics so resilience can be analyzed.

---

## 🛠️ Tech Stack
- **Docker Compose** (multi-service orchestration)  
- **Python 3.11** (scripts + services)  
- **Flask** (API service)  
- **Redis** (stateful service)  
- **Gunicorn** (production WSGI server)

---

## 🚀 Quickstart

### 1. Clone and enter
```powershell
git clone https://github.com/NikhilS2007/chaos-sim.git
cd chaos-sim

### 2. Python venv + dependencies
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

### 3. Start the stack
docker compose up -d --build

Check status:

docker compose ps

### 4. Run the chaos tools (separate terminals)\

Chaos Monkey (injects failurs every 20s):

python .\scripts\chaos_monkey.py --interval 20 --modes kill pause restart --project chaos-sim

Monitor (logs health to CSV)

python .\scripts\monitor.py --interval 5 --project chaos-sim

Auto-Recovery (restarts unhealthy/exited services):

python .\scripts\recover.py --project chaos-sim


### 5. Verify it works

curl http://localhost:5000/health

Expected: {"status":"ok"}
