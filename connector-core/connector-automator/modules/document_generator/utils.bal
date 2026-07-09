// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/os;
import ballerina/lang.regexp;
import ballerina/lang.'string as strings;

function validateApiKey() returns error? {
    string? apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is () || apiKey.trim().length() == 0 {
        return error("ANTHROPIC_API_KEY not configured");
    }
}

function ensureDirectoryExists(string dirPath) returns error? {
    if !check file:test(dirPath, file:EXISTS) {
        check file:createDir(dirPath, file:RECURSIVE);
    }
}

function writeOutput(string content, string outputPath) returns error? {
    string normalized = normalizeGeneratedMarkdown(content);
    check io:fileWriteString(outputPath, normalized);
}

function normalizeGeneratedMarkdown(string content) returns string {
    string[] lines = regexp:split(re `\n`, content);
    string[] cleaned = [];
    string previousHeading = "";

    foreach string line in lines {
        string trimmed = line.trim();
        boolean isHeading = trimmed.startsWith("#");

        if isHeading {
            if previousHeading == trimmed {
                continue;
            }
            previousHeading = trimmed;
        } else if trimmed.length() > 0 {
            previousHeading = "";
        }

        cleaned.push(line);
    }

    string output = string:'join("\n", ...cleaned);

    string previous = "";
    while previous != output {
        previous = output;
        output = simpleReplace(output, "\n\n\n", "\n\n");
    }

    return output.trim() + "\n";
}

function simpleReplace(string text, string searchFor, string replaceWith) returns string {
    string result = text;
    int? index = result.indexOf(searchFor);
    while index is int {
        string before = result.substring(0, index);
        string after = result.substring(index + searchFor.length());
        result = before + replaceWith + after;
        index = result.indexOf(searchFor);
    }
    return result;
}

function extractDirectoryName(string fullPath) returns string {
    string[] pathParts = regexp:split(re `/`, fullPath);
    if pathParts.length() > 0 {
        return pathParts[pathParts.length() - 1];
    }
    return fullPath;
}

function trimLeadingPathSeparators(string path) returns string {
    string normalized = path;
    while normalized.startsWith("/") || normalized.startsWith("\\") {
        normalized = normalized.substring(1);
    }
    return normalized;
}

public function formatExampleName(string dirName) returns string {
    string[] parts = regexp:split(re `[-_]`, dirName);
    string[] capitalizedParts = [];

    foreach int i in 0 ..< parts.length() {
        string part = parts[i];
        if part.length() > 0 {
            if i == 0 {
                capitalizedParts.push(part.substring(0, 1).toUpperAscii() + part.substring(1).toLowerAscii());
            } else {
                capitalizedParts.push(part.toLowerAscii());
            }
        }
    }

    return strings:'join(" ", ...capitalizedParts);
}
