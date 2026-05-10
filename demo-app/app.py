from flask import Flask, jsonify
import os, time

app = Flask(__name__)
start_time = time.time()

@app.route("/")
def home():
    return jsonify({"message": "Hello from sandbox!", "env": os.getenv("ENV_ID", "unknown")})

@app.route("/health")
def health():
    return jsonify({"status": "ok", "uptime": time.time() - start_time})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
