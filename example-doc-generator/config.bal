// Pipeline configuration — all values are read from Config.toml at runtime.
// Copy Config.toml.example → Config.toml and fill in the required fields.

// === Required ===
configurable string llmApiKey = ?;
configurable string userGoal = ?;

// === Service Ports ===
configurable int codeServerPort = 8080;
configurable int agentServerPort = 8765;

// === External Repo Paths (local filesystem) ===
configurable string integrationSamplesRepo = "../integration-samples";
configurable string docsIntegratorRepo = "../docs-integrator";

// === GitHub Repo Identifiers ===
configurable string integrationSamplesUpstream = "wso2/integration-samples";
configurable string integrationSamplesBaseBranch = "main";
configurable string docsIntegratorFork = ?;
configurable string docsIntegratorUpstream = "wso2/docs-integrator";
configurable string docsIntegratorBaseBranch = "dev";
