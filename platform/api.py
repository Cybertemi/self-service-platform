from flask import Flask, jsonify, request
import subprocess, json, os, glob, time

app = Flask(__name__)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load_state(env_id):
    path = os.path.join(BASE_DIR, "envs", f"{env_id}.json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)

def all_envs():
    files = glob.glob(os.path.join(BASE_DIR, "envs", "*.json"))
    envs = []
    for f in files:
        with open(f) as fp:
            envs.append(json.load(fp))
    return envs

# POST /envs — create environment
@app.route("/envs", methods=["POST"])
def create():
    data = request.json or {}
    name = data.get("name", "myapp")
    ttl  = data.get("ttl", 1800)
    result = subprocess.run(
        ["bash", "platform/create_env.sh", name, str(ttl)],
        capture_output=True, text=True, cwd=BASE_DIR
    )
    if result.returncode != 0:
        return jsonify({"error": result.stderr}), 500
    # Extract env ID from output
    for line in result.stdout.splitlines():
        if "ID:" in line:
            env_id = line.split("ID:")[1].strip()
            return jsonify({"env_id": env_id, "output": result.stdout}), 201
    return jsonify({"output": result.stdout}), 201

# GET /envs — list all active envs
@app.route("/envs", methods=["GET"])
def list_envs():
    envs = all_envs()
    now = int(time.time())
    for e in envs:
        e["ttl_remaining"] = max(0, e["created_at"] + e["ttl"] - now)
    return jsonify(envs)

# DELETE /envs/<id> — destroy environment
@app.route("/envs/<env_id>", methods=["DELETE"])
def destroy(env_id):
    result = subprocess.run(
        ["bash", "platform/destroy_env.sh", env_id],
        capture_output=True, text=True, cwd=BASE_DIR
    )
    if result.returncode != 0:
        return jsonify({"error": result.stderr}), 500
    return jsonify({"status": "destroyed", "id": env_id})

# GET /envs/<id>/logs — last 100 lines of app.log
@app.route("/envs/<env_id>/logs", methods=["GET"])
def get_logs(env_id):
    log_path = os.path.join(BASE_DIR, "logs", env_id, "app.log")
    if not os.path.exists(log_path):
        return jsonify({"error": "No logs found"}), 404
    result = subprocess.run(
        ["tail", "-n", "100", log_path],
        capture_output=True, text=True
    )
    return jsonify({"env_id": env_id, "logs": result.stdout.splitlines()})

# GET /envs/<id>/health — last 10 health check results
@app.route("/envs/<env_id>/health", methods=["GET"])
def get_health(env_id):
    log_path = os.path.join(BASE_DIR, "logs", env_id, "health.log")
    if not os.path.exists(log_path):
        return jsonify({"error": "No health logs found"}), 404
    result = subprocess.run(
        ["tail", "-n", "10", log_path],
        capture_output=True, text=True
    )
    lines = []
    for line in result.stdout.splitlines():
        try:
            lines.append(json.loads(line))
        except:
            lines.append({"raw": line})
    return jsonify({"env_id": env_id, "health": lines})

# POST /envs/<id>/outage — simulate outage
@app.route("/envs/<env_id>/outage", methods=["POST"])
def outage(env_id):
    data = request.json or {}
    mode = data.get("mode", "crash")
    result = subprocess.run(
        ["bash", "platform/simulate_outage.sh", "--env", env_id, "--mode", mode],
        capture_output=True, text=True, cwd=BASE_DIR
    )
    if result.returncode != 0:
        return jsonify({"error": result.stderr}), 500
    return jsonify({"env_id": env_id, "mode": mode, "output": result.stdout})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
