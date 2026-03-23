# Signtone - Register by sound
# Usage: make <command>

SHELL := /bin/bash

.PHONY: docker-up docker-down docker-logs api worker dashboard test init-db test-beacon setup lint restart

docker-up:
	cd docker && docker compose up -d

docker-down:
	cd docker && docker compose down

docker-logs:
	cd docker && docker compose logs -f

api:
	cd backend && venv/bin/uvicorn app.main:app --reload --port 8000

worker:
	cd backend && venv/bin/celery -A app.workers.celery_app worker --loglevel=info

dashboard:
	cd dashboard && ../backend/venv/bin/streamlit run app.py --server.port 8501

test:
	cd backend && venv/bin/pytest tests/ -v

init-db:
	PYTHONPATH=backend backend/venv/bin/python scripts/setup_indexes.py

test-beacon:
	PYTHONPATH=backend backend/venv/bin/python scripts/test_beacon.py

setup:
	cd backend && python -m venv venv && \
	venv/bin/pip install --upgrade pip && \
	venv/bin/pip install -r requirements.txt

lint:
	cd backend && venv/bin/python -m pylint app/

restart:
	lsof -ti :8000 | xargs kill -9 2>/dev/null; sleep 1; \
	cd backend && venv/bin/uvicorn app.main:app --reload --port 8000
