# Makefile helpers for local Phase 0/1 development

.PHONY: backend-test omok-test compose-up

backend-test:
	cd backend && PYTHONPATH=. python -m pytest tests -q

omok-test:
	cmake -S core/omok -B core/omok/build
	cmake --build core/omok/build
	ctest --test-dir core/omok/build --output-on-failure

compose-up:
	docker compose up --build
