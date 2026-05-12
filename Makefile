.PHONY: up down create destroy logs health simulate clean

up:
	docker network create sandbox-nginx 2>/dev/null || true
	docker run -d \
		--name sandbox-nginx \
		--network sandbox-nginx \
		-p 80:80 \
		-v $(PWD)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
		-v $(PWD)/nginx/conf.d:/etc/nginx/conf.d:ro \
		nginx:alpine 2>/dev/null || echo "Nginx already running"
	pip3 install flask requests --quiet
	nohup bash platform/cleanup_daemon.sh &
	nohup python3 monitor/health_poller.py &
	python3 platform/api.py &
	@echo ""
	@echo "Platform is up!"
	@echo "  API:   http://localhost:8000"
	@echo "  Nginx: http://localhost:80"

down:
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		ENV_ID=$$(jq -r '.id' $$f); \
		bash platform/destroy_env.sh $$ENV_ID; \
	done
	docker stop sandbox-nginx 2>/dev/null || true
	docker rm sandbox-nginx 2>/dev/null || true
	pkill -f cleanup_daemon.sh 2>/dev/null || true
	pkill -f health_poller.py 2>/dev/null || true
	pkill -f api.py 2>/dev/null || true
	@echo "Platform stopped"

create:
	@read -p "Environment name: " NAME; \
	 read -p "TTL in seconds (default 1800): " TTL; \
	 TTL=$${TTL:-1800}; \
	 bash platform/create_env.sh $$NAME $$TTL

destroy:
	@[ -n "$(ENV)" ] || (echo "Usage: make destroy ENV=env-abc123" && exit 1)
	bash platform/destroy_env.sh $(ENV)

logs:
	@[ -n "$(ENV)" ] || (echo "Usage: make logs ENV=env-abc123" && exit 1)
	tail -f logs/$(ENV)/app.log

health:
	@echo "=== Environment Health ==="
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		jq -r '"ID: \(.id)  Status: \(.status)  Name: \(.name)"' $$f; \
	done

simulate:
	@[ -n "$(ENV)" ] || (echo "Usage: make simulate ENV=env-abc123 MODE=crash" && exit 1)
	@[ -n "$(MODE)" ] || (echo "Usage: make simulate ENV=env-abc123 MODE=crash" && exit 1)
	bash platform/simulate_outage.sh --env $(ENV) --mode $(MODE)

clean:
	rm -rf logs/* envs/* nginx/conf.d/*
	@echo "All state and logs wiped"
