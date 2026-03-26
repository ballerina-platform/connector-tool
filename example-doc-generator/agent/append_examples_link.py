#!/usr/bin/env python3
"""
append_examples_link.py

Post-processing step: fetches the Examples section from the connector's Ballerina
Central readme (via registry API) and appends it to the workflow doc under the
heading '## More Code Examples'.

Usage: python append_examples_link.py <doc_path>

Strategy:
  1. Extract connector name from the H1 title of the doc.
  2. Query the Ballerina Central registry API (/latest) to get package metadata.
  3. Extract the 'readme' field (markdown) from the response.
  4. Parse out the '## Examples' section from the readme.
  5. Append the section content under '## More Code Examples' (not the original heading).
"""

import json
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REGISTRY_API = "https://api.central.ballerina.io/2.0/registry/packages/ballerinax/{name}/latest"


def extract_connector_name(doc_content: str) -> str | None:
    """Return lowercase connector name from '# [Name] Connector Example' title."""
    match = re.match(r"^#\s+(\w+)\s+Connector\s+Example", doc_content.strip(), re.IGNORECASE)
    return match.group(1).lower() if match else None


def fetch_json(url: str) -> dict | list | None:
    """GET a URL and parse the JSON response. Returns None on any error."""
    try:
        req = Request(url, headers={"User-Agent": "connector-docs-automation/1.0",
                                    "Accept": "application/json"})
        with urlopen(req, timeout=15) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode("utf-8"))
    except (HTTPError, URLError, json.JSONDecodeError):
        pass
    return None


def extract_examples_section(readme: str) -> str | None:
    """
    Parse the Examples section out of a Ballerina Central readme (markdown).

    Finds the first heading that matches 'Examples' (any level), then collects
    all content up to the next heading of the same or higher level. Returns the
    section body (without the original heading), or None if not found.
    """
    lines = readme.splitlines()

    # Find the Examples heading line
    start_idx = None
    heading_level = None
    for i, line in enumerate(lines):
        m = re.match(r"^(#{1,6})\s+Examples?\s*$", line.strip(), re.IGNORECASE)
        if m:
            start_idx = i
            heading_level = len(m.group(1))
            break

    if start_idx is None:
        return None

    # Collect lines after the heading until the next same-or-higher-level heading
    body_lines = []
    for line in lines[start_idx + 1:]:
        m = re.match(r"^(#{1,6})\s", line)
        if m and len(m.group(1)) <= heading_level:
            break
        body_lines.append(line)

    body = "\n".join(body_lines).strip()
    return body if body else None


def build_section(body: str) -> str:
    """Wrap extracted examples body under '## More code examples'."""
    return f"\n## More code examples\n\n{body}\n"


def main() -> None:
    if len(sys.argv) < 2:
        print("[WARN] append_examples_link: no doc path provided — skipping.")
        sys.exit(0)

    doc_path = Path(sys.argv[1])
    if not doc_path.exists():
        print(f"[WARN] append_examples_link: doc not found at {doc_path} — skipping.")
        sys.exit(0)

    content = doc_path.read_text(encoding="utf-8")

    # Idempotency: skip if already appended
    if "## More code examples" in content:
        print("[INFO] append_examples_link: 'More Code Examples' section already present — skipping.")
        sys.exit(0)

    connector_name = extract_connector_name(content)
    if not connector_name:
        print("[WARN] append_examples_link: could not extract connector name from doc title — skipping.")
        sys.exit(0)

    print(f"[INFO] append_examples_link: fetching metadata for '{connector_name}' from Ballerina Central...")
    metadata = fetch_json(REGISTRY_API.format(name=connector_name))
    if not metadata or not isinstance(metadata, dict):
        print(f"[INFO] append_examples_link: package 'ballerinax/{connector_name}' not found — skipping.")
        sys.exit(0)

    readme = metadata.get("readme", "")
    if not readme:
        print("[INFO] append_examples_link: readme field is empty in package metadata — skipping.")
        sys.exit(0)

    examples_body = extract_examples_section(readme)
    if not examples_body:
        print(f"[INFO] append_examples_link: no Examples section found in readme for '{connector_name}' — skipping.")
        sys.exit(0)

    print(f"[INFO] append_examples_link: found Examples section — appending as '## More Code Examples'.")
    doc_path.write_text(content.rstrip() + "\n" + build_section(examples_body), encoding="utf-8")
    print("[INFO] append_examples_link: done.")


if __name__ == "__main__":
    main()
