import ballerina/file;
import ballerina/io;
import ballerina/os;
import ballerina/time;

import wso2/example_doc_generator.agent_client;
import wso2/example_doc_generator.ai_client;
import wso2/example_doc_generator.prompts;
import wso2/example_doc_generator.utils;


# Entry point for the full automation pipeline.
#
# Phase 1  (Steps 1–2):  Pre-flight validation — API key and Claude Code CLI.
# Phase 2  (Steps 3–5):  Infrastructure     — code-server and Python agent server.
# Phase 3  (Steps 6–10): Prompt generation  — build, call Claude, format, save.
# Phase 4  (Steps 11–13): Agent execution   — run agent, cleanup workspace, enforce doc structure.
# Phase 5  (Steps 14–17): Post-processing   — inject Devant button, append examples link, crop screenshots, write run log.
#
# + return - an error if any step fails
public function main() returns error? {
    utils:log("=== WSO2 Integrator Documentation Pipeline ===");
    utils:log("");

    time:Utc startTime = time:utcNow();
    utils:log("[INFO] Start time: " + time:utcToString(startTime));
    utils:log("[INFO] Goal: " + userGoal);
    utils:log("");

    // Track LLM usage across all direct API calls (agent cost is tracked separately)
    ai_client:LlmUsage promptGenUsage    = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};
    ai_client:LlmUsage slugGenUsage      = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};
    ai_client:LlmUsage docEnfUsage       = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};

    // ── Phase 1: Pre-flight validation ─────────────────────────────────────

    // Step 1: Validate Anthropic API key with a small ping before doing anything else
    utils:log("[STEP 1] Validating Anthropic API key...");
    check ai_client:validateApiKey(llmApiKey);
    utils:log("");

    // Step 2: Check Claude Code CLI is installed (required for agent execution)
    utils:log("[STEP 2] Checking if Claude Code CLI is installed...");
    boolean claudeInstalled = utils:checkClaudeCodeInstalled();
    if !claudeInstalled {
        return error("Claude Code CLI ('claude') is not installed or not on PATH. " +
                     "Install it from https://claude.ai/code and re-run the pipeline.");
    }
    utils:log("\t[INFO] Claude Code CLI is installed.");
    utils:log("");

    // ── Phase 2: Infrastructure ─────────────────────────────────────────────

    // Step 3: Check if code-server binary is installed; install via official script if not
    utils:log("[STEP 3] Checking if code-server is installed...");
    boolean codeServerBinaryInstalled = utils:checkCodeServerInstalled();
    if !codeServerBinaryInstalled {
        utils:log("\t[INFO] code-server not found. Installing via official script (curl -fsSL https://code-server.dev/install.sh | sh)...");
        check utils:installCodeServer();
        utils:log("\t[INFO] code-server installed successfully.");
    } else {
        utils:log("\t[INFO] code-server is already installed.");
    }
    utils:log("");

    // Step 4: Verify code-server is running on the configured port, start if needed
    utils:log("[STEP 4] Verifying code-server on port " + codeServerPort.toString() + "...");
    boolean codeServerRunning = utils:checkCodeServerRunning(codeServerPort);
    if !codeServerRunning {
        utils:log("\t[INFO] Code-server not running. Starting code-server...");
        check utils:startCodeServer(codeServerPort);
        utils:log("\t[INFO] Code-server started successfully.");
    } else {
        utils:log("\t[INFO] Code-server is already running.");
    }
    string codeServerUrl = "http://localhost:" + codeServerPort.toString();
    utils:log("\t[INFO] Code-server URL: " + codeServerUrl);
    utils:log("");

    // Step 5: Check if the Python agent server is running; start it if not
    utils:log("[STEP 5] Checking Python agent server on port " + agentServerPort.toString() + "...");
    boolean agentRunning = utils:checkAgentServerRunning(agentServerPort);
    if !agentRunning {
        utils:log("\t[INFO] Agent server not running. Starting via `uv run agent_server.py`...");
        check utils:startAgentServer(agentServerPort);
        utils:log("\t[INFO] Agent server started.");
    } else {
        utils:log("\t[INFO] Agent server is already running.");
    }
    string agentUrl = "http://localhost:" + agentServerPort.toString();
    utils:log("\t[INFO] Agent server URL: " + agentUrl);
    utils:log("");

    // ── Phase 3: Prompt generation ──────────────────────────────────────────

    // Step 6: Build system and user prompts
    utils:log("[STEP 6] Building system and user prompts...");
    string projectRoot = os:getEnv("PWD");
    string systemPrompt = prompts:buildSystemPrompt(projectRoot);
    string userMessage = prompts:buildUserMessage(userGoal, codeServerUrl, projectRoot);

    // Step 7: Call Anthropic API to generate the execution prompt
    utils:log("[STEP 7] Calling Anthropic API to generate execution prompt...");
    ai_client:LlmResult promptResult = check ai_client:callClaude(systemPrompt, userMessage, llmApiKey);
    string executionPrompt = promptResult.text;
    promptGenUsage = promptResult.usage;

    // Step 8: Generate a short filename slug from the goal via LLM
    utils:log("[STEP 8] Generating short filename slug...");
    ai_client:LlmResult slugResult = check ai_client:generateGoalSlug(userGoal, llmApiKey);
    string goalSlug = slugResult.text;
    slugGenUsage = slugResult.usage;

    // Step 9: Add header to the generated prompt
    utils:log("[STEP 9] Formatting execution prompt...");
    string header = string `# Execution Prompt

<!-- ============================================================
     XML-TAGGED MARKDOWN EXECUTION PROMPT
     Generated by: WSO2 Integrator Documentation Pipeline
     Agent: Playwright MCP (Browser Automation)
     Target: Code-Server — WSO2 Integrator (Low-Code)
     Goal: ${userGoal}
     ============================================================ -->

`;
    string fullPrompt = header + executionPrompt;

    // Step 10: Save to file — returns the path used for the agent in Step 11
    utils:log("[STEP 10] Saving execution prompt to " + utils:OUTPUT_DIR + "...");
    string promptPath = check utils:saveExecutionPrompt(fullPrompt, goalSlug);
    utils:log("\t[INFO] Saved to: " + promptPath);
    utils:log("");

    // ── Phase 4: Agent execution ─────────────────────────────────────────────

    // Step 11: Submit the execution prompt to the agent server and stream logs
    utils:log("[STEP 11] Running Claude agent...");
    agent_client:AgentCost? agentCost = check agent_client:runClaudeAgent(promptPath, agentUrl);
    utils:log("");

    // ── Phase 5: Post-processing ──────────────────────────────────────────────

    // Step 12: Close all editor tabs in code-server (deterministic cleanup, no LLM needed)
    // utils:log("[STEP 12] Workspace cleanup — closing editor tabs in code-server...");
    // os:Process|error cleanupProc = os:exec({
    //     value: "agent/.venv/bin/python",
    //     arguments: [
    //         "agent/cleanup_workspace.py",
    //         "--url", codeServerUrl,
    //         "--samples-repo", integrationSamplesRepo,
    //         "--upstream", integrationSamplesUpstream,
    //         "--base-branch", integrationSamplesBaseBranch
    //     ]
    // });
    // if cleanupProc is error {
    //     utils:log("\t[WARN] Could not start cleanup_workspace.py: " + cleanupProc.message());
    // } else {
    //     int cleanupExit = check cleanupProc.waitForExit();
    //     if cleanupExit == 0 {
    //         utils:log("\t[INFO] Workspace cleanup complete.");
    //     } else {
    //         utils:log("\t[WARN] cleanup_workspace.py exited with code " + cleanupExit.toString() + ".");
    //     }
    // }
    // utils:log("");

    // Step 13: Enforce documentation structure via a dedicated Claude API call.
    // The agent writes the doc with all browser-automation context in its window;
    // rules stated early in the system prompt get buried. This call has the rules
    // fresh in context with no other noise, so they are reliably applied.
    utils:log("[STEP 13] Enforcing documentation structure...");
    string workflowDocsDir = "./artifacts/workflow-docs";
    string enforcedDocPath = "";
    file:MetaData[]|file:Error dirEntries = file:readDir(workflowDocsDir);
    if dirEntries is file:MetaData[] {
        string docPath = "";
        foreach file:MetaData entry in dirEntries {
            if entry.absPath.endsWith(".md") {
                docPath = entry.absPath;
                break;
            }
        }
        if docPath == "" {
            utils:log("\t[INFO] No .md file found in " + workflowDocsDir + " — skipping enforcement.");
        } else {
            utils:log("\t[INFO] Found workflow doc: " + docPath);
            string|io:Error rawDoc = io:fileReadString(docPath);
            if rawDoc is string {
                string enforcementSystemPrompt = prompts:buildDocEnforcementSystemPrompt();
                ai_client:LlmResult|error enfResult = ai_client:callClaude(enforcementSystemPrompt, rawDoc, llmApiKey);
                if enfResult is ai_client:LlmResult {
                    io:Error? writeErr = io:fileWriteString(docPath, enfResult.text);
                    if writeErr is io:Error {
                        utils:log("\t[WARN] Could not write enforced doc: " + writeErr.message());
                    } else {
                        enforcedDocPath = docPath;
                        docEnfUsage = enfResult.usage;
                        utils:log("\t[INFO] Documentation structure enforced successfully.");
                    }
                } else {
                    utils:log("\t[WARN] Doc enforcement LLM call failed: " + enfResult.message());
                }
            } else {
                utils:log("\t[WARN] Could not read doc file: " + rawDoc.message());
            }
        }
    } else {
        utils:log("\t[INFO] Workflow docs directory not found — skipping enforcement.");
    }
    utils:log("");

    // Step 14: Inject "Deploy to Devant" button into the workflow doc
    utils:log("[STEP 14] Injecting Deploy to Devant button into workflow doc...");
    if enforcedDocPath != "" {
        os:Process|error devantProc = os:exec({
            value: "agent/.venv/bin/python",
            arguments: ["agent/inject_devant_button.py", enforcedDocPath]
        });
        if devantProc is error {
            utils:log("\t[WARN] Could not start inject_devant_button.py: " + devantProc.message());
            utils:log("\t[WARN] Run manually: agent/.venv/bin/python agent/inject_devant_button.py " + enforcedDocPath);
        } else {
            int devantExit = check devantProc.waitForExit();
            if devantExit == 0 {
                utils:log("\t[INFO] Deploy to Devant button injected successfully.");
            } else {
                utils:log("\t[WARN] inject_devant_button.py exited with code " + devantExit.toString() + ".");
            }
        }
    } else {
        utils:log("\t[INFO] No enforced doc path available — skipping Devant button injection.");
    }
    utils:log("");

    // Step 15: Append Ballerina Central examples link to the workflow doc (if examples exist)
    utils:log("[STEP 15] Checking Ballerina Central for connector examples link...");
    if enforcedDocPath != "" {
        os:Process|error examplesProc = os:exec({
            value: "agent/.venv/bin/python",
            arguments: ["agent/append_examples_link.py", enforcedDocPath]
        });
        if examplesProc is error {
            utils:log("\t[WARN] Could not start append_examples_link.py: " + examplesProc.message());
        } else {
            int examplesExit = check examplesProc.waitForExit();
            if examplesExit == 0 {
                utils:log("\t[INFO] Examples link step complete.");
            } else {
                utils:log("\t[WARN] append_examples_link.py exited with code " + examplesExit.toString() + ".");
            }
        }
    } else {
        utils:log("\t[INFO] No enforced doc path available — skipping examples link.");
    }
    utils:log("");

    // Step 16: Crop UI chrome from screenshots produced by the agent
    utils:log("[STEP 16] Cropping screenshots...");
    os:Process|error cropProc = os:exec({
        value: "agent/.venv/bin/python",
        arguments: ["agent/crop_screenshots.py"]
    });
    if cropProc is error {
        utils:log("\t[WARN] Could not launch crop_screenshots.py: " + cropProc.message());
        utils:log("\t[WARN] Run `make crop-screenshots` manually to crop screenshots.");
    } else {
        int exitCode = check cropProc.waitForExit();
        if exitCode == 0 {
            utils:log("\t[INFO] Screenshots cropped successfully.");
        } else {
            utils:log("\t[WARN] crop_screenshots.py exited with code " + exitCode.toString() + ".");
            utils:log("\t[WARN] Run `make crop-screenshots` manually to crop screenshots.");
        }
    }
    utils:log("");

    // ── Phase 5 (cont.): Finalise ─────────────────────────────────────────────

    time:Utc endTime = time:utcNow();
    decimal durationSecs = time:utcDiffSeconds(endTime, startTime);

    // Aggregate direct API call costs
    int totalInputTokens  = promptGenUsage.inputTokens  + slugGenUsage.inputTokens  + docEnfUsage.inputTokens;
    int totalOutputTokens = promptGenUsage.outputTokens + slugGenUsage.outputTokens + docEnfUsage.outputTokens;
    decimal totalCostUsd  = promptGenUsage.costUsd      + slugGenUsage.costUsd      + docEnfUsage.costUsd;

    // Add agent SDK cost to combined total
    decimal agentCostUsd = 0.0d;
    if agentCost is agent_client:AgentCost {
        decimal? ac = agentCost.totalCostUsd;
        if ac is decimal {
            agentCostUsd = ac;
        }
    }
    decimal totalCombinedCostUsd = totalCostUsd + agentCostUsd;

    // Step 17: Write run log to artifacts/run-log/
    utils:log("[STEP 17] Writing run log...");
    string runLogDir = "./artifacts/run-log";
    io:Error? keepErr = io:fileWriteString(runLogDir + "/.keep", "");
    if keepErr is io:Error {
        utils:log("\t[WARN] Could not create run-log dir: " + keepErr.message());
    }
    string timestamp = time:utcToString(startTime);
    // Build a filename-safe timestamp (replace : and . with -)
    string tsSlug = re `[:\.]`.replaceAll(timestamp, "-");
    string logPath = runLogDir + "/" + goalSlug + "_" + tsSlug + ".json";

    json agentCostJson = agentCost is agent_client:AgentCost ? {
        "totalCostUsd":    agentCost.totalCostUsd,
        "inputTokens":     agentCost.inputTokens,
        "outputTokens":    agentCost.outputTokens,
        "cacheReadTokens": agentCost.cacheReadTokens,
        "cacheWriteTokens":agentCost.cacheWriteTokens,
        "numTurns":        agentCost.numTurns
    } : "not available";

    json logJson = {
        "goal": userGoal,
        "goalSlug": goalSlug,
        "model": "claude-sonnet-4-6",
        "startTime": timestamp,
        "endTime": time:utcToString(endTime),
        "durationSeconds": durationSecs,
        "llmCalls": {
            "promptGeneration": {
                "inputTokens": promptGenUsage.inputTokens,
                "outputTokens": promptGenUsage.outputTokens,
                "costUsd": promptGenUsage.costUsd
            },
            "slugGeneration": {
                "inputTokens": slugGenUsage.inputTokens,
                "outputTokens": slugGenUsage.outputTokens,
                "costUsd": slugGenUsage.costUsd
            },
            "docEnforcement": {
                "inputTokens": docEnfUsage.inputTokens,
                "outputTokens": docEnfUsage.outputTokens,
                "costUsd": docEnfUsage.costUsd
            },
            "agentExecution": agentCostJson
        },
        "totalDirectApiCostUsd": totalCostUsd,
        "totalCombinedCostUsd": totalCombinedCostUsd,
        "artifacts": {
            "executionPromptPath": promptPath,
            "workflowDocPath": enforcedDocPath == "" ? "(not written)" : enforcedDocPath
        }
    };

    io:Error? logWriteErr = io:fileWriteString(logPath, logJson.toJsonString());
    if logWriteErr is io:Error {
        utils:log("\t[WARN] Could not write run log: " + logWriteErr.message());
    } else {
        utils:log("\t[INFO] Run log saved to: " + logPath);
    }
    utils:log("");

    // Print pipeline stats
    utils:log("--- Pipeline Stats ---");
    utils:log(string `Start time:      ${time:utcToString(startTime)}`);
    utils:log(string `End time:        ${time:utcToString(endTime)}`);
    utils:log(string `Duration:        ${durationSecs}s`);
    utils:log(string `Prompt length:   ${fullPrompt.length()} chars`);
    utils:log("--- LLM Cost Breakdown ---");
    utils:log(string `Prompt gen:      ${promptGenUsage.inputTokens} in / ${promptGenUsage.outputTokens} out  |  $${promptGenUsage.costUsd}`);
    utils:log(string `Slug gen:        ${slugGenUsage.inputTokens} in / ${slugGenUsage.outputTokens} out  |  $${slugGenUsage.costUsd}`);
    utils:log(string `Doc enforcement: ${docEnfUsage.inputTokens} in / ${docEnfUsage.outputTokens} out  |  $${docEnfUsage.costUsd}`);
    utils:log(string `Direct API total:${totalInputTokens} in / ${totalOutputTokens} out  |  $${totalCostUsd}`);
    utils:log(string `Agent SDK:       $${agentCostUsd}`);
    utils:log(string `COMBINED TOTAL:  $${totalCombinedCostUsd}`);

    utils:log("");
    utils:log("=== Pipeline Complete ===");
    utils:log("Artifacts saved under '" + utils:OUTPUT_DIR + "'.");
}
