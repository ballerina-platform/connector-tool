// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;

import wso2/connector_automator.utils;

function shellQuote(string value) returns string {
    return "'" + regexp:replaceAll(re `'`, value, "'\"'\"'") + "'";
}

function resolveRelativePath(string gitRoot, string absolutePath) returns string? {
    string prefix = gitRoot.endsWith("/") ? gitRoot : gitRoot + "/";
    if !absolutePath.startsWith(prefix) {
        return ();
    }
    return absolutePath.substring(prefix.length());
}

function readPackageVersion(string ballerinaDir) returns string? {
    string|io:Error content = io:fileReadString(ballerinaDir + "/Ballerina.toml");
    if content is io:Error {
        return ();
    }
    boolean inPackage = false;
    foreach string line in regexp:split(re `\n`, content) {
        string trimmed = line.trim();
        if trimmed.startsWith("[") {
            inPackage = trimmed == "[package]";
        } else if inPackage && trimmed.startsWith("version") {
            string[] parts = regexp:split(re `=`, trimmed);
            if parts.length() >= 2 {
                return regexp:replaceAll(re `^\s*"|"\s*$`, parts[1].trim(), "");
            }
        }
    }
    return ();
}

function recommendedVersion(string currentVersion, string changeType) returns string? {
    string[] parts = regexp:split(re `\.`, currentVersion);
    if parts.length() != 3 {
        return ();
    }
    int|error major = int:fromString(parts[0]);
    int|error minor = int:fromString(parts[1]);
    int|error patch = int:fromString(parts[2]);
    if major is error || minor is error || patch is error {
        return ();
    }
    match changeType {
        "MAJOR" => { return string `${major + 1}.0.0`; }
        "MINOR" => { return string `${major}.${minor + 1}.0`; }
        "PATCH" => { return string `${major}.${minor}.${patch + 1}`; }
        _ => { return (); }
    }
}

public function executeVersionSummary(string connectorPath) returns error? {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    utils:CommandResult rootResult = utils:executeCommand("git rev-parse --show-toplevel", ballerinaDir);
    if !rootResult.success {
        return error("connector is not inside a Git worktree");
    }
    string gitRoot = rootResult.stdout.trim();
    utils:CommandResult baseResult = utils:executeCommand("git merge-base origin/main HEAD", gitRoot);
    if !baseResult.success || baseResult.stdout.trim().length() == 0 {
        return error("could not resolve the merge base of origin/main and HEAD");
    }
    string mergeBase = baseResult.stdout.trim();

    string[] relativePaths = [];
    foreach string sourcePath in [ballerinaDir + "/client.bal", ballerinaDir + "/types.bal"] {
        if check file:test(sourcePath, file:EXISTS) {
            string? relativePath = resolveRelativePath(gitRoot, sourcePath);
            if relativePath is string {
                relativePaths.push(relativePath);
            }
        }
    }
    if relativePaths.length() == 0 {
        return error("client.bal and types.bal were not found inside the Git worktree");
    }

    string[] diffs = [];
    foreach string relativePath in relativePaths {
        string command = string `git diff ${mergeBase} -- ${shellQuote(relativePath)}`;
        utils:CommandResult diffResult = utils:executeCommand(command, gitRoot);
        if !diffResult.success {
            return error(string `could not generate Git diff for ${relativePath}: ${diffResult.stderr.trim()}`);
        }
        if diffResult.stdout.length() > 0 {
            diffs.push(diffResult.stdout);
        }
    }
    string gitDiff = string:'join("\n", ...diffs).trim();
    if gitDiff.length() == 0 {
        printNoVersionChangeAnalysis();
        return;
    }

    AnalysisResult analysis = check analyzeVersionChange(gitDiff);
    string recommended = "";
    string? currentVersion = readPackageVersion(ballerinaDir);
    if currentVersion is string {
        recommended = recommendedVersion(currentVersion, analysis.changeType) ?: "";
    }
    printVersionChangeAnalysis(analysis, recommended);
}
