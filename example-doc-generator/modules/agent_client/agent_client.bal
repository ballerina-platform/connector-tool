import ballerina/http;
import ballerina/lang.runtime;
import wso2/example_doc_generator.utils;

# Job submission response from the agent server.
type StartResponse record {
    # UUID assigned to the submitted job
    string job_id;
};

# Structured cost data returned by the agent server once the job completes.
public type AgentCost record {
    # Total USD cost reported by the Claude Agent SDK (nil if not available)
    decimal? totalCostUsd;
    # Input tokens consumed across the entire agent run
    int inputTokens;
    # Output tokens generated across the entire agent run
    int outputTokens;
    # Cache read tokens (prompt caching)
    int cacheReadTokens;
    # Cache write tokens (prompt caching)
    int cacheWriteTokens;
    # Number of conversation turns in the agent run (nil if not available)
    int? numTurns;
};

# Poll response for a running or completed agent job.
type JobStatus record {
    # "running" or "done"
    string status;
    # Accumulated log lines in "[LABEL] text" format
    string[] logs;
    # Structured cost data — present only after the job completes
    AgentCost? cost;
};

# Submits the execution prompt to the Python agent server and streams its log
# lines to the console as they arrive, blocking until the job is marked done.
#
# + promptPath - absolute or relative path to the generated execution prompt file
# + agentUrl   - base URL of the Python agent server (e.g. http://localhost:8765)
# + return     - AgentCost if available, nil if cost data was absent, or an error
public function runClaudeAgent(string promptPath, string agentUrl) returns AgentCost?|error {
    http:Client agentClient = check new (agentUrl, timeout = 600);

    // Submit the job
    json payload = {"prompt_path": promptPath};
    http:Response startResp = check agentClient->post("/run", payload);
    if startResp.statusCode < 200 || startResp.statusCode >= 300 {
        string|error errBody = startResp.getTextPayload();
        string detail = errBody is string ? errBody : "(unable to read body)";
        return error(string `Agent server returned HTTP ${startResp.statusCode}: ${detail}`);
    }
    json startBody = check startResp.getJsonPayload();
    StartResponse startData = check startBody.cloneWithType(StartResponse);
    string jobId = startData.job_id;
    utils:log("\t[INFO] Job submitted: " + jobId);

    // Poll every second; print new log lines as they arrive
    int lastLogCount = 0;
    while true {
        runtime:sleep(1);
        http:Response pollResp = check agentClient->get(string `/jobs/${jobId}`);
        json pollBody = check pollResp.getJsonPayload();
        JobStatus jobStatus = check pollBody.cloneWithType(JobStatus);

        int i = lastLogCount;
        while i < jobStatus.logs.length() {
            utils:log("\t" + jobStatus.logs[i]);
            i += 1;
        }
        lastLogCount = jobStatus.logs.length();

        if jobStatus.status == "done" {
            utils:log("\t[INFO] Claude agent finished.");
            return jobStatus.cost;
        }
    }
}
