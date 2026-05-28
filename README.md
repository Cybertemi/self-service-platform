 Self-Service Platform (Mini Heroku)

A self-service platform where users can spin up isolated temporary environments,
deploy apps, simulate outages, monitor health, and auto-destroy everything.

## Architecture

![Architecture](architecture.png)

## Prerequisites

- Linux VM (Ubuntu 20.04/22.04)
- Docker installed
- Python 3.10+
- make
- jq
- uuid-runtime

```bash
# Install dependencies
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo apt install -y make jq uuid-runtime python3-pip
```

## Quick Start (zero to first running env in 5 commands)

```bash
git clone https://github.com/Cybertemi/self-service-platform
cd self-service-platform
python3 -m venv venv && source venv/bin/activate
pip install flask requests
make up
```

Then in a new terminal:
```bash
make create
# Enter name: myapp
# Enter TTL: 1800
```

## Makefile Commands

| Command | Description |
|---|---|
| `make up` | Start Nginx + daemon + API |
| `make down` | Stop everything, destroy all envs |
| `make create` | Create new environment |
| `make destroy ENV=env-abc123` | Destroy specific environment |
| `make logs ENV=env-abc123` | Tail environment logs |
| `make health` | Show all env health statuses |
| `make simulate ENV=env-abc123 MODE=crash` | Simulate outage |
| `make clean` | Wipe all state and logs |

## API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| POST | `/envs` | Create environment |
| GET | `/envs` | List all active envs |
| DELETE | `/envs/:id` | Destroy environment |
| GET | `/envs/:id/logs` | Last 100 lines of app.log |
| GET | `/envs/:id/health` | Last 10 health checks |
| POST | `/envs/:id/outage` | Simulate outage |

## Full Demo Walkthrough

### 1. Start the platform
```bash
make up
```

### 2. Create an environment
```bash
make create
# name: myapp, TTL: 600
```

### 3. Check health
```bash
make health
curl http://localhost:<PORT>/health
```

### 4. Simulate outage
```bash
make simulate ENV=<env-id> MODE=crash
```

### 5. Observe degraded status (within 90s)
```bash
curl http://localhost:8000/envs/<env-id>/health
```

### 6. Recover
```bash
make simulate ENV=<env-id> MODE=recover
```

### 7. Watch auto-destroy
```bash
# Wait for TTL to expire, then:
cat logs/cleanup.log
ls envs/  # should be empty
```

## Outage Simulation Modes

| Mode | What it does | How to recover |
|---|---|---|
| `crash` | Kills the container | `MODE=recover` |
| `pause` | Freezes the container | `MODE=recover` |
| `network` | Cuts network access | `MODE=recover` |
| `recover` | Restores everything | — |
| `stress` | Spikes CPU | Wait 60s |

## Known Limitations

- Nginx routing uses localhost subdomains — requires `/etc/hosts` edits or a real domain for external access
- Flask API runs in debug mode — use gunicorn for production
- Log shipping uses background processes, not a proper log aggregator
- No authentication on the API endpoints
- Single VM means no horizontal scaling

## Demo

Live demo application:
https://drive.google.com/drive/folders/1tTgCcgOorp9ms7c3MSw6axD5pp8Arvym

You can use the demo app to:

- Create temporary environments
- Simulate outages and recovery workflows
- Monitor environment health
- Observe automatic cleanup after TTL expiration

---

## Conclusion

This project demonstrates the core concepts behind modern Internal Developer Platforms (IDPs) and self-service infrastructure systems used in real-world platform engineering teams.

The platform provides automated environment provisioning, isolated deployments, health monitoring, outage simulation, and automatic resource cleanup within a lightweight architecture built on Docker, Flask, Nginx, and Linux tooling.

Through this project, key DevOps and platform engineering concepts were explored, including:

- Container orchestration fundamentals
- Infrastructure automation
- Environment lifecycle management
- Health monitoring and recovery workflows
- Self-service developer tooling
- CI/CD-aligned operational patterns

Future improvements could include:

- Kubernetes-based orchestration
- Authentication and RBAC
- Persistent storage support
- Multi-node scaling
- Centralized logging and metrics
- Production-grade deployment with Gunicorn and reverse proxy hardening

This project was built as a hands-on exploration of scalable developer infrastructure and platform engineering workflows inspired by systems like Heroku and modern cloud developer platforms.

### Author

Temitope Ilori Linkedin: http://linkedin.com/in/iloritemi
