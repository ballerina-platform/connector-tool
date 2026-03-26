import ballerina/os;
import ballerina/lang.runtime;

# Checks whether the code-server binary is available on PATH.
# Runs `code-server --version`; a zero exit code means it is installed.
# + return - true if code-server is installed, false otherwise
public function checkCodeServerInstalled() returns boolean {
    os:Process|error proc = os:exec({
        value: "code-server",
        arguments: ["--version"]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Installs code-server using the official installer script:
#   curl -fsSL https://code-server.dev/install.sh | sh
# The pipe is a shell construct, so this is run via `sh -c`.
# + return - an error if the installer script fails
public function installCodeServer() returns error? {
    os:Process|error proc = os:exec({
        value: "sh",
        arguments: ["-c", "curl -fsSL https://code-server.dev/install.sh | sh"]
    });
    if proc is error {
        return error("Failed to launch code-server installer: " + proc.message());
    }
    int|error exitCode = proc.waitForExit();
    if exitCode is error {
        return error("code-server installer script failed: " + exitCode.message());
    }
    if exitCode != 0 {
        return error("code-server installer script failed with exit code: " + exitCode.toString());
    }
}

# Checks whether the Claude Code CLI ('claude') is available on PATH.
# Runs `claude --version`; a zero exit code means it is installed.
# + return - true if Claude Code CLI is installed, false otherwise
public function checkClaudeCodeInstalled() returns boolean {
    os:Process|error proc = os:exec({
        value: "claude",
        arguments: ["--version"]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Checks whether code-server is reachable on the given port using curl.
# + port - the port to check
# + return - true if code-server is running, false otherwise
public function checkCodeServerRunning(int port) returns boolean {
    os:Process|error proc = os:exec({
        value: "curl",
        arguments: ["-s", "-L", "-o", "/dev/null", "-w", "%{http_code}",
                    "--max-time", "3", "http://localhost:" + port.toString()]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Starts code-server on the given port and waits until it is ready.
# + port - the port to bind code-server to
# + return - an error if code-server fails to start within the timeout
public function startCodeServer(int port) returns error? {
    os:Process|error proc = os:exec({
        value: "code-server",
        arguments: ["--auth", "none", "--bind-addr", "0.0.0.0:" + port.toString()]
    });
    if proc is error {
        return error("Failed to start code-server: " + proc.message());
    }
    // Wait up to 15 seconds for code-server to become ready
    int attempts = 0;
    while attempts < 15 {
        runtime:sleep(1);
        if checkCodeServerRunning(port) {
            return;
        }
        attempts += 1;
    }
    return error("Code-server did not become ready within 15 seconds on port " + port.toString());
}
