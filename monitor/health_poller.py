#!/usr/bin/env python3
import json, os, glob, time, requests

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failure_counts = {}

def load_envs():
    files = glob.glob(os.path.join(BASE_DIR, "envs", "*.json"))
    envs = []
    for f in files:
        with open(f) as fp:
            envs.append(json.load(fp))
    return envs

def update_status(env_id, status):
    state_path = os.path.join(BASE_DIR, "envs", f"{env_id}.json")
    if not os.path.exists(state_path):
        return
    with open(state_path) as f:
        state = json.load(f)
    state["status"] = status
    tmp = state_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, state_path)

def poll():
    envs = load_envs()
    for env in envs:
        env_id = env["id"]
        port   = env.get("port")
        url    = f"http://localhost:{port}/health"
        log_dir = os.path.join(BASE_DIR, "logs", env_id)
        os.makedirs(log_dir, exist_ok=True)
        log_path = os.path.join(log_dir, "health.log")

        try:
            start = time.time()
            r = requests.get(url, timeout=5)
            latency = round(time.time() - start, 3)
            status_code = r.status_code
            failure_counts[env_id] = 0
            status = "ok"
        except Exception as e:
            latency = None
            status_code = 0
            failure_counts[env_id] = failure_counts.get(env_id, 0) + 1
            status = "error"

        record = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "env_id": env_id,
            "status_code": status_code,
            "latency": latency,
            "status": status
        }

        with open(log_path, "a") as f:
            f.write(json.dumps(record) + "\n")

        if failure_counts.get(env_id, 0) >= 3:
            print(f"[WARNING] {env_id} is DEGRADED - 3 consecutive failures")
            update_status(env_id, "degraded")
        else:
            print(f"[{record['timestamp']}] {env_id} → {status_code} ({latency}s)")

if __name__ == "__main__":
    print("Health poller started...")
    while True:
        poll()
        time.sleep(30)
