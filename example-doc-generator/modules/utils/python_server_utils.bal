import ballerina/os;
import ballerina/lang.runtime;

# Checks whether the Python agent server is reachable on the given port.
# Probes the /health endpoint with a 3-second timeout.
# + port - the port to check
# + return - true if the server responds, false otherwise
public function checkAgentServerRunning(int port) returns boolean {
    os:Process|error proc = os:exec({
        value: "curl",
        arguments: ["-s", "-o", "/dev/null", "-w", "%{http_code}",
                    "--max-time", "3", "http://localhost:" + port.toString() + "/health"]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Starts the Python agent server on the given port using
# `cd agent && uv run agent_server.py --port <port>` and waits until the
# /health endpoint is reachable. The venv is expected at agent/.venv.
# + port - the port to bind the agent server to
# + return - an error if the server fails to start within the timeout
public function startAgentServer(int port) returns error? {
    os:Process|error proc = os:exec({
        value: "sh",
        arguments: ["-c", "cd agent && uv run agent_server.py --port " + port.toString()]
    });
    if proc is error {
        return error("Failed to start agent server: " + proc.message());
    }
    // Wait up to 20 seconds for the server to become ready
    int attempts = 0;
    while attempts < 20 {
        runtime:sleep(1);
        if checkAgentServerRunning(port) {
            return;
        }
        attempts += 1;
    }
    return error("Agent server did not become ready within 20 seconds on port " + port.toString());
}
