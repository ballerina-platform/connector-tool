#!/usr/bin/env python3
"""
inject_devant_button.py

Post-processing script: injects a "Deploy to Devant" badge/button into the
generated workflow doc just before the "## More Code Examples" section.

The button links to the connector sample in wso2/integration-samples (main branch),
using the project name recorded in artifacts/run-log/created-project.txt.

Usage:
    python agent/inject_devant_button.py <doc_path>

Arguments:
    doc_path    Absolute path to the workflow doc .md file to update

Exit codes:
    0  always — failure cases are logged as warnings so the pipeline is never blocked
"""

import sys
from pathlib import Path

PROJECT_PATH_FILE = "artifacts/run-log/created-project.txt"
MARKER = "## More Code Examples"

BUTTON_TEMPLATE = (
    "[![Deploy to Devant]"
    "(https://openindevant.choreoapps.dev/images/DeployDevant-White.svg)]"
    "(https://console.devant.dev/new?gh=wso2/integration-samples/tree/main/connectors/{project_name})"
)


def main() -> None:
    # ── Validate arguments ────────────────────────────────────────────────────
    if len(sys.argv) < 2:
        print("[ERROR] Usage: inject_devant_button.py <doc_path>", file=sys.stderr)
        sys.exit(0)

    doc_path = Path(sys.argv[1])

    if not doc_path.exists():
        print(
            f"[ERROR] Doc file not found: {doc_path} — skipping Devant button injection",
            file=sys.stderr,
        )
        sys.exit(0)

    # ── Read project name from run-log ────────────────────────────────────────
    path_file = Path(PROJECT_PATH_FILE)
    if not path_file.exists():
        print(
            f"[WARN]  created-project.txt not found at {path_file} — "
            "skipping Devant button injection",
            file=sys.stderr,
        )
        sys.exit(0)

    raw = path_file.read_text(encoding="utf-8").strip()
    if not raw:
        print(
            "[WARN]  created-project.txt is empty — skipping Devant button injection",
            file=sys.stderr,
        )
        sys.exit(0)

    project_name = Path(raw).name  # e.g. "snowflake_db_integration"

    # ── Build button markdown ─────────────────────────────────────────────────
    button_line = BUTTON_TEMPLATE.format(project_name=project_name)

    # ── Read doc content ──────────────────────────────────────────────────────
    try:
        content = doc_path.read_text(encoding="utf-8")
    except OSError as e:
        print(
            f"[ERROR] Failed to read doc file: {e} — skipping Devant button injection",
            file=sys.stderr,
        )
        sys.exit(0)

    # ── Inject button ─────────────────────────────────────────────────────────
    if MARKER in content:
        updated = content.replace(MARKER, f"{button_line}\n\n{MARKER}", 1)
    else:
        print(
            f"[WARN]  '{MARKER}' not found in doc — appending Deploy to Devant button at end of file",
            file=sys.stderr,
        )
        updated = content.rstrip() + f"\n\n{button_line}\n"

    # ── Write updated content ─────────────────────────────────────────────────
    try:
        doc_path.write_text(updated, encoding="utf-8")
    except OSError as e:
        print(
            f"[ERROR] Failed to write doc file: {e} — skipping Devant button injection",
            file=sys.stderr,
        )
        sys.exit(0)

    print(
        f"[INFO]  Injected Deploy to Devant button for project '{project_name}' into {doc_path}"
    )


if __name__ == "__main__":
    main()
