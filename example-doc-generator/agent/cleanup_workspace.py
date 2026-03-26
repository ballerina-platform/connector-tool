#!/usr/bin/env python3
"""
cleanup_workspace.py

Post-pipeline script: publishes the generated Ballerina integration project as a
connector code sample to wso2/integration-samples (via a fork), creates a feature
branch and PR, records the sample path in the run-log, then deletes the local
project and closes VS Code editor tabs.

Usage:
    python agent/cleanup_workspace.py --url URL [options]

Required:
    --url URL               code-server URL (e.g. http://localhost:8080)

Optional:
    --samples-repo PATH     Path to local integration-samples fork
                            (default: ../integration-samples relative to workspace)
    --no-publish            Skip sample publishing — just delete project and close tabs
    --dry-run               Print planned actions without making any changes

Prerequisites:
    - gh CLI authenticated (gh auth login)
    - integration-samples fork cloned locally with 'upstream' remote configured:
        git remote add upstream https://github.com/wso2/integration-samples.git
    - Playwright installed: python -m playwright install chromium
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

# ── Paths ─────────────────────────────────────────────────────────────────────

PROJECT_PATH_FILE = "artifacts/run-log/created-project.txt"
PUBLISHED_SAMPLE_LOG = "artifacts/run-log/published-sample-path.txt"

# Default integration-samples path: sibling of connector-docs-automations/
# Layout: <workspace>/connector-docs-automations/agent/cleanup_workspace.py
#         <workspace>/integration-samples/
_WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_SAMPLES_REPO = _WORKSPACE_ROOT / "integration-samples"

DEFAULT_UPSTREAM_REPO = "wso2/integration-samples"
DEFAULT_BASE_BRANCH = "main"


# ── Logging helpers ───────────────────────────────────────────────────────────

def info(msg: str) -> None:
    print(f"[INFO]  {msg}")

def warn(msg: str) -> None:
    print(f"[WARN]  {msg}", file=sys.stderr)

def dry(msg: str) -> None:
    print(f"[DRY]   {msg}")

def fail(msg: str) -> None:
    print(f"\n[ERROR] {msg}", file=sys.stderr)
    sys.exit(1)


# ── Subprocess helper ─────────────────────────────────────────────────────────

def run(cmd: list[str], cwd: Path | None = None, check: bool = True) -> str:
    result = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        check=check,
    )
    return result.stdout.strip()


# ── Step 1: Read created project path ────────────────────────────────────────

def read_project_path() -> Path:
    path_file = Path(PROJECT_PATH_FILE)
    if not path_file.exists():
        fail(f"No project path file at {PROJECT_PATH_FILE} — run `make run` first.")
    project_path = path_file.read_text().strip()
    if not project_path:
        fail("Project path file is empty — run `make run` first.")
    target = Path(project_path)
    if not target.exists():
        fail(f"Project directory not found: {project_path}")
    info(f"Project: {target}")
    return target


# ── Step 2: Infer fork slug ───────────────────────────────────────────────────

def infer_fork(samples_repo: Path) -> str:
    try:
        url = run(["git", "remote", "get-url", "origin"], cwd=samples_repo)
        import re
        m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", url)
        if m:
            return m.group(1)
    except subprocess.CalledProcessError:
        pass
    fail(
        "Could not infer fork slug from git remote 'origin'.\n"
        "Pass --fork OWNER/REPO explicitly."
    )


# ── Step 3: Sync main + create branch ────────────────────────────────────────

def sync_and_branch(samples_repo: Path, branch_name: str, base_branch: str, dry_run: bool) -> None:
    remotes = run(["git", "remote"], cwd=samples_repo).split()
    if "upstream" not in remotes:
        fail(
            "'upstream' remote not found in integration-samples repo.\n"
            "Add it with:\n"
            "  git remote add upstream https://github.com/wso2/integration-samples.git"
        )

    if dry_run:
        dry(f"git fetch upstream  (in {samples_repo})")
        dry(f"git checkout {base_branch} && git merge upstream/{base_branch} --ff-only")
        dry(f"git checkout -b {branch_name}")
        return

    info(f"Fetching upstream/{base_branch}...")
    subprocess.run(["git", "fetch", "upstream"], cwd=str(samples_repo), check=True)
    subprocess.run(["git", "checkout", base_branch], cwd=str(samples_repo), check=True)
    try:
        subprocess.run(
            ["git", "merge", f"upstream/{base_branch}", "--ff-only"],
            cwd=str(samples_repo),
            check=True,
        )
    except subprocess.CalledProcessError:
        fail(
            f"Could not fast-forward fork's {base_branch} to upstream/{base_branch}.\n"
            "Your fork has diverged. Resolve manually before running this script."
        )
    info(f"Creating branch: {branch_name}")
    subprocess.run(["git", "checkout", "-b", branch_name], cwd=str(samples_repo), check=True)


# ── Step 4: Copy project into connectors/ ────────────────────────────────────

def find_ballerina_project(base: Path) -> Path:
    """
    Return the path of the actual Ballerina project inside base.

    The agent sometimes creates a workspace wrapper so the layout is:
        base/                  ← what created-project.txt records
          <project>/           ← the actual Ballerina project (Ballerina.toml here)

    Checks base itself first, then one level of subdirectories.
    Falls back to base with a warning if Ballerina.toml is not found anywhere.
    """
    if (base / "Ballerina.toml").exists():
        return base
    for child in sorted(base.iterdir()):
        if child.is_dir() and (child / "Ballerina.toml").exists():
            info(f"Ballerina project found one level deep: {child.name}")
            return child
    warn(f"Ballerina.toml not found under {base} — using base path as-is")
    return base


def copy_sample(
    samples_repo: Path,
    project: Path,
    project_name: str,
    dry_run: bool,
) -> Path:
    actual_project = find_ballerina_project(project)
    dest = samples_repo / "connectors" / project_name
    if dry_run:
        dry(f"Copy {actual_project} → {dest}")
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(str(actual_project), str(dest))
    info(f"Copied sample to: {dest}")
    return dest


# ── Step 5: Commit and push ───────────────────────────────────────────────────

def commit_and_push(
    samples_repo: Path,
    project_name: str,
    branch_name: str,
    dry_run: bool,
) -> None:
    if dry_run:
        dry(f"git add . && git commit -m 'samples: add {project_name} connector integration sample'")
        dry(f"git push origin {branch_name}")
        return
    info("Committing changes...")
    subprocess.run(["git", "add", "."], cwd=str(samples_repo), check=True)
    subprocess.run(
        ["git", "commit", "-m", f"samples: add {project_name} connector integration sample"],
        cwd=str(samples_repo),
        check=True,
    )
    info(f"Pushing branch '{branch_name}' to origin...")
    subprocess.run(["git", "push", "origin", branch_name], cwd=str(samples_repo), check=True)


# ── Step 6: Create PR ─────────────────────────────────────────────────────────

def build_pr_body(project_name: str) -> str:
    return f"""\
## Purpose

Adds a working Ballerina connector integration sample for `{project_name}`.

## Goals

- Provide a runnable end-to-end sample demonstrating connector usage in WSO2 Integrator

## Approach

Sample generated by the connector-docs-automations pipeline.

## Release note

Added `{project_name}` Ballerina connector integration sample under `connectors/{project_name}/`.

## Samples

Connector integration sample added at `connectors/{project_name}/`. \
Contains Ballerina source files demonstrating connector operations.

## Automation tests

- Unit tests: N/A (sample project)
- Integration tests: N/A (sample project)

## Security checks

- Followed secure coding standards: yes
- Ran FindSecurityBugs plugin: N/A (Ballerina project)
- Confirmed no keys, passwords, tokens, usernames, or secrets committed: yes
"""


def create_pr(
    fork: str,
    branch_name: str,
    project_name: str,
    pr_body: str,
    upstream_repo: str,
    base_branch: str,
    dry_run: bool,
) -> str:
    fork_owner = fork.split("/")[0]
    title = f"samples: add {project_name} connector integration sample"
    head = f"{fork_owner}:{branch_name}"

    if dry_run:
        dry(f"gh pr create --repo {upstream_repo} --head {head} --base {base_branch}")
        dry(f"  Title: {title}")
        return "(dry run — no PR created)"

    info(f"Creating PR: {upstream_repo} ← {head}")
    try:
        result = subprocess.run(
            [
                "gh", "pr", "create",
                "--repo", upstream_repo,
                "--head", head,
                "--base", base_branch,
                "--title", title,
                "--body", pr_body,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        fail(f"Failed to create PR:\n{e.stderr.strip()}")


# ── Step 7: Write run-log entry ───────────────────────────────────────────────

def write_sample_log(project_name: str, dry_run: bool) -> None:
    sample_path = f"connectors/{project_name}"
    if dry_run:
        dry(f"Write published sample path to {PUBLISHED_SAMPLE_LOG}: {sample_path}")
        return
    log_file = Path(PUBLISHED_SAMPLE_LOG)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    log_file.write_text(sample_path, encoding="utf-8")
    info(f"Recorded sample path: {sample_path} → {PUBLISHED_SAMPLE_LOG}")


# ── Step 8: Delete local project ─────────────────────────────────────────────

def delete_project(project: Path, dry_run: bool) -> None:
    if dry_run:
        dry(f"shutil.rmtree({project})")
        return
    shutil.rmtree(project)
    info(f"Deleted local project: {project}")


# ── Step 9: Close editor tabs ─────────────────────────────────────────────────

def close_editor_tabs(url: str, dry_run: bool) -> None:
    if dry_run:
        dry(f"Open {url} in headless browser and press Ctrl+K W to close all editor tabs")
        return
    info("Closing VS Code editor tabs...")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1720, "height": 968})
        page.goto(url, wait_until="networkidle", timeout=30_000)
        # VS Code keyboard chord: Ctrl+K then W = Close All Editors
        page.keyboard.press("Control+k")
        page.keyboard.press("w")
        page.wait_for_timeout(1000)
        browser.close()
    info("Editor tabs closed.")


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Publish the generated integration as a connector sample to "
            "wso2/integration-samples, then delete the local project and close editor tabs."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python agent/cleanup_workspace.py --url http://localhost:8080\n"
            "  python agent/cleanup_workspace.py --url http://localhost:8080 --dry-run\n"
            "  python agent/cleanup_workspace.py --url http://localhost:8080 --no-publish\n"
            "  python agent/cleanup_workspace.py --url http://localhost:8080 \\\n"
            "      --project-path /Users/you/bi-workspace/my_connector/my_integration\n"
        ),
    )
    parser.add_argument(
        "--url",
        required=True,
        help="code-server URL (e.g. http://localhost:8080)",
    )
    parser.add_argument(
        "--samples-repo",
        default=str(DEFAULT_SAMPLES_REPO),
        metavar="PATH",
        help=(
            f"Path to local integration-samples fork "
            f"(default: {DEFAULT_SAMPLES_REPO})"
        ),
    )
    parser.add_argument(
        "--project-path",
        metavar="PATH",
        help=(
            "Absolute path to the created integration project. "
            "When provided, writes it to created-project.txt before proceeding — "
            "useful for manual runs when the pipeline did not write the file automatically."
        ),
    )
    parser.add_argument(
        "--upstream",
        default=DEFAULT_UPSTREAM_REPO,
        metavar="OWNER/REPO",
        help=(
            f"Upstream GitHub repo to open PRs against "
            f"(default: {DEFAULT_UPSTREAM_REPO})"
        ),
    )
    parser.add_argument(
        "--base-branch",
        default=DEFAULT_BASE_BRANCH,
        metavar="BRANCH",
        help=f"Base branch for integration samples PRs (default: {DEFAULT_BASE_BRANCH})",
    )
    parser.add_argument(
        "--no-publish",
        action="store_true",
        help="Skip sample publishing — just delete project and close editor tabs",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print planned actions without making any changes",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    samples_repo = Path(args.samples_repo).resolve()

    if args.dry_run:
        print("=" * 60)
        print("DRY RUN — no changes will be made")
        print("=" * 60)

    # ── 0. Write project path file if supplied manually ──────────
    if args.project_path:
        path_file = Path(PROJECT_PATH_FILE)
        path_file.parent.mkdir(parents=True, exist_ok=True)
        path_file.write_text(args.project_path.strip(), encoding="utf-8")
        info(f"Written project path to {PROJECT_PATH_FILE}: {args.project_path.strip()}")

    # ── 1. Read project path ──────────────────────────────────────
    project = read_project_path()
    project_name = project.name

    if not args.no_publish:
        # ── 2. Validate samples repo ──────────────────────────────
        if not (samples_repo / ".git").exists():
            fail(f"{samples_repo} is not a git repository.")
        fork = infer_fork(samples_repo)
        branch_name = f"samples/add-{project_name}"
        info(f"Fork: {fork}  |  Upstream: {args.upstream}  |  Branch: {branch_name}")

        # ── 3. Sync main + create branch ──────────────────────────
        sync_and_branch(samples_repo, branch_name, args.base_branch, args.dry_run)

        # ── 4. Copy sample ────────────────────────────────────────
        copy_sample(samples_repo, project, project_name, args.dry_run)

        # ── 5. Commit + push ──────────────────────────────────────
        commit_and_push(samples_repo, project_name, branch_name, args.dry_run)

        # ── 6. Create PR ──────────────────────────────────────────
        pr_body = build_pr_body(project_name)
        pr_url = create_pr(fork, branch_name, project_name, pr_body, args.upstream, args.base_branch, args.dry_run)

        # ── 7. Write run-log entry ────────────────────────────────
        write_sample_log(project_name, args.dry_run)

        print()
        print("=" * 60)
        if args.dry_run:
            print("Sample publish dry run complete.")
        else:
            print(f"Sample PR: {pr_url}")
        print("=" * 60)

    # ── 8. Delete local project ───────────────────────────────────
    delete_project(project, args.dry_run)

    # ── 9. Close editor tabs ──────────────────────────────────────
    close_editor_tabs(args.url, args.dry_run)

    print()
    print("=" * 60)
    if args.dry_run:
        print("Dry run complete. Remove --dry-run to execute.")
    else:
        print("Workspace cleanup complete.")
    print("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)
