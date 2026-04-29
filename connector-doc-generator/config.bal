// Pipeline configuration — all values are read from Config.toml at runtime.
// Copy Config.toml.example → Config.toml and fill in the required fields.

// === Required ===
configurable string connectorName = ?;
configurable string moduleSlug = ?;
configurable string packageName = ?;
configurable string githubRepo = ?;
configurable string category = ?;

// === Optional ===
configurable string connectorVersion = "";
configurable string docsRepoRoot = "..";
configurable boolean dryRun = false;
configurable boolean force = false;

// Derived paths
final string docsRoot = docsRepoRoot + "/en/docs/connectors";
final string sidebarPath = docsRepoRoot + "/en/sidebars.ts";
