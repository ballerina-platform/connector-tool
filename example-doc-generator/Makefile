.PHONY: help setup setup-python setup-bal build run \
        start-agent stop-agent \
        crop-screenshots crop-screenshots-dry crop-screenshots-backup \
        publish-docs publish-docs-dry publish-docs-no-preview \
        cleanup cleanup-dry \
        clean clean-artifacts

# ── Default ──────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Connector Docs Automation — available targets"
	@echo ""
	@echo "  Setup"
	@echo "    make setup            Install all dependencies (Ballerina + Python)"
	@echo "    make setup-python     Create agent/.venv and install Python deps"
	@echo "    make setup-bal        Build the Ballerina project"
	@echo ""
	@echo "  Run"
	@echo "    make run              Run the full 12-step pipeline (bal run + crop)"
	@echo "    make start-agent      Start the Python agent server in the foreground"
	@echo "    make stop-agent       Send shutdown request to the agent server"
	@echo ""
	@echo "  Publish"
	@echo "    make publish-docs             Publish docs + create PR (auto-detects docs-integrator path)"
	@echo "    make publish-docs-dry         Dry run — print planned actions, no changes"
	@echo "    make publish-docs-no-preview  Publish docs without Playwright preview screenshots"
	@echo "    PUBLISH_ARGS='...'            Pass extra flags, e.g. PUBLISH_ARGS='--category messaging'"
	@echo "    DOCS_REPO=PATH                Override docs-integrator path"
	@echo "    DOCS_UPSTREAM=OWNER/REPO      Override docs PR target repo (default: wso2/docs-integrator)"
	@echo "    DOCS_BASE_BRANCH=BRANCH       Override docs PR base branch (default: dev)"
	@echo ""
	@echo "  Cleanup"
	@echo "    make cleanup                  Publish integration sample PR + delete local project + close tabs"
	@echo "    make cleanup-dry              Dry run — print planned actions, no changes"
	@echo "    CODE_SERVER_PORT=N            Override code-server port (default: 8080)"
	@echo "    AGENT_SERVER_PORT=N           Override agent server port (default: 8765)"
	@echo "    SAMPLES_REPO=PATH             Override integration-samples path"
	@echo "    INTEGRATION_UPSTREAM=OWNER/REPO  Override samples PR target repo (default: wso2/integration-samples)"
	@echo "    INTEGRATION_BASE_BRANCH=BRANCH   Override samples PR base branch (default: main)"
	@echo "    PROJECT_PATH=PATH             Manually set project path (writes created-project.txt)"
	@echo "    CLEANUP_ARGS='...'            Pass extra flags, e.g. CLEANUP_ARGS='--no-publish'"
	@echo ""
	@echo "  Artifacts"
	@echo "    make clean            Remove artifacts/, target/, Dependencies.toml, agent/.venv"
	@echo "    make clean-artifacts  Remove only the artifacts/ directory"
	@echo ""

# ── Setup ────────────────────────────────────────────────────────────────────
setup: setup-python setup-bal
	@echo "Setup complete."

# Sentinel file: rebuilt whenever requirements.txt changes or .venv is missing.
agent/.venv/.installed: agent/requirements.txt
	@echo "→ Creating agent/.venv and installing Python dependencies..."
	cd agent && uv venv
	cd agent && uv pip install -r requirements.txt
	cd agent && .venv/bin/playwright install chromium
	touch agent/.venv/.installed
	@echo "Python setup complete."

setup-python: agent/.venv/.installed
	@echo "Python environment is ready. Activate with: source agent/.venv/bin/activate"

setup-bal:
	@echo "→ Building Ballerina project..."
	bal build
	@echo "Ballerina build complete."

# ── Run ──────────────────────────────────────────────────────────────────────
run:
	@echo "→ Running full pipeline..."
	bal run

crop-screenshots: agent/.venv/.installed
	agent/.venv/bin/python agent/crop_screenshots.py

crop-screenshots-dry: agent/.venv/.installed
	agent/.venv/bin/python agent/crop_screenshots.py --dry-run

crop-screenshots-backup: agent/.venv/.installed
	agent/.venv/bin/python agent/crop_screenshots.py --backup

start-agent: agent/.venv/.installed
	@echo "→ Starting Python agent server (agent/agent_server.py)..."
	cd agent && unset CLAUDECODE && .venv/bin/python agent_server.py

AGENT_SERVER_PORT ?= 8765

stop-agent:
	@echo "→ Sending shutdown to agent server..."
	curl -s -X POST http://localhost:$(AGENT_SERVER_PORT)/shutdown || echo "Agent server not running."

# ── Publish docs ─────────────────────────────────────────────────────────────
# DOCS_REPO          — override the docs-integrator path (optional; defaults to ../docs-integrator)
# DOCS_UPSTREAM      — GitHub org/repo for docs-integrator PRs (default: wso2/docs-integrator)
# DOCS_BASE_BRANCH   — base branch for docs-integrator PRs (default: dev)
# PUBLISH_ARGS       — extra flags passed to publish_docs.py

DOCS_REPO ?=
DOCS_UPSTREAM ?= wso2/docs-integrator
DOCS_BASE_BRANCH ?= dev

_publish_docs_cmd = agent/.venv/bin/python scripts/publish_docs.py \
  $(if $(DOCS_REPO),--docs-repo "$(DOCS_REPO)",) \
  --upstream "$(DOCS_UPSTREAM)" \
  --base-branch "$(DOCS_BASE_BRANCH)" \
  $(PUBLISH_ARGS)

publish-docs: agent/.venv/.installed
	@echo "→ Publishing connector docs..."
	$(_publish_docs_cmd)

publish-docs-dry: agent/.venv/.installed
	@echo "→ Publishing connector docs (dry run)..."
	$(_publish_docs_cmd) --dry-run

publish-docs-no-preview: agent/.venv/.installed
	@echo "→ Publishing connector docs (no preview)..."
	$(_publish_docs_cmd) --no-preview

# ── Cleanup workspace ────────────────────────────────────────────────────────
# CODE_SERVER_PORT         — code-server port (default: 8080)
# SAMPLES_REPO             — override integration-samples path (optional)
# INTEGRATION_UPSTREAM     — GitHub org/repo for integration samples PRs (default: wso2/integration-samples)
# INTEGRATION_BASE_BRANCH  — base branch for integration samples PRs (default: main)
# CLEANUP_ARGS             — extra flags passed to cleanup_workspace.py

CODE_SERVER_PORT ?= 8080
SAMPLES_REPO ?=
PROJECT_PATH ?=
INTEGRATION_UPSTREAM ?= wso2/integration-samples
INTEGRATION_BASE_BRANCH ?= main

_cleanup_cmd = agent/.venv/bin/python agent/cleanup_workspace.py \
  --url http://localhost:$(CODE_SERVER_PORT) \
  --upstream "$(INTEGRATION_UPSTREAM)" \
  --base-branch "$(INTEGRATION_BASE_BRANCH)" \
  $(if $(SAMPLES_REPO),--samples-repo "$(SAMPLES_REPO)",) \
  $(if $(PROJECT_PATH),--project-path "$(PROJECT_PATH)",) \
  $(CLEANUP_ARGS)

cleanup: agent/.venv/.installed
	@echo "→ Publishing integration sample, deleting local project, closing tabs..."
	$(_cleanup_cmd)

cleanup-dry: agent/.venv/.installed
	@echo "→ Cleanup dry run..."
	$(_cleanup_cmd) --dry-run

# ── Artifacts ────────────────────────────────────────────────────────────────
clean:
	@echo "→ Cleaning artifacts/, target/, Dependencies.toml, agent/.venv..."
	rm -rf artifacts/ target/ Dependencies.toml agent/.venv
	@echo "Done."

clean-artifacts:
	@echo "→ Removing artifacts/ directory..."
	rm -rf artifacts/
