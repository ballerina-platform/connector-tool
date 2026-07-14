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

import wso2/connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/regex;
import ballerina/yaml;

// Helper function to generate unique request IDs
function generateRequestId(string schemaName, string path, string requestType) returns string {
    string cleanPath = regex:replaceAll(path, "_", "_u");
    cleanPath = regex:replaceAll(cleanPath, "\\.", "_d");
    cleanPath = regex:replaceAll(cleanPath, "\\[", "_l");
    cleanPath = regex:replaceAll(cleanPath, "\\]", "_r");
    return string `${schemaName}_${requestType}_${cleanPath}`;
}

// Helper function to validate if a generated name is safe for schema naming
function isValidSchemaName(string name) returns boolean {
    // Check basic requirements for a valid schema name
    if (name.length() == 0 || name.length() > 100) {
        return false;
    }

    // Should not contain spaces, special characters that could break JSON
    if (name.includes(" ") || name.includes("\n") || name.includes("\t") ||
        name.includes("\"") || name.includes("'") || name.includes("`") ||
        name.includes("{") || name.includes("}") || name.includes("[") || name.includes("]") ||
        name.includes(",") || name.includes(":") || name.includes(";") ||
        name.includes("?") || name.includes("!") || name.includes("\\") ||
        name.includes("/") || name.includes("<") || name.includes(">")) {
        return false;
    }

    // Should start with uppercase letter (PascalCase)
    string firstChar = name.substring(0, 1);
    if (!(firstChar >= "A" && firstChar <= "Z")) {
        return false;
    }

    // Should only contain alphanumeric characters
    return regex:matches(name, "[A-Z][a-zA-Z0-9]*");
}

// Helper function to check if a name is already taken
function isNameTaken(string name, string[] existingNames, map<string> nameMapping) returns boolean {
    // Check against existing schema names
    foreach string existingName in existingNames {
        if (existingName == name) {
            return true;
        }
    }

    // Check against already mapped names
    foreach string key in nameMapping.keys() {
        string? mappedName = nameMapping[key];
        if (mappedName is string && mappedName == name) {
            return true;
        }
    }

    return false;
}

// Helper function to generate unique request IDs for operationId requests
function generateOperationRequestId(string path, string method) returns string {
    string cleanPath = regex:replaceAll(path, "_", "_u");
    cleanPath = regex:replaceAll(cleanPath, "\\.", "_d");
    cleanPath = regex:replaceAll(cleanPath, "\\[", "_l");
    cleanPath = regex:replaceAll(cleanPath, "\\]", "_r");
    return string `${method}_${cleanPath}`;
}

function isYamlFormat(string filePath) returns boolean {
    string lowerPath = filePath.toLowerAscii();
    return lowerPath.endsWith(".yaml") || lowerPath.endsWith(".yml");
}

function fileExists(string filePath) returns boolean {
    boolean|file:Error exists = file:test(filePath, file:EXISTS);
    return exists is boolean ? exists : false;
}

function convertAlignedYamlToJson(string alignedSpecPath) returns error? {
    string yamlAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.yaml";
    string jsonAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    boolean|file:Error yamlExists = file:test(yamlAlignedSpec, file:EXISTS);
    if yamlExists is file:Error || !yamlExists {
        string ymlAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.yml";
        boolean|file:Error ymlExists = file:test(ymlAlignedSpec, file:EXISTS);
        if ymlExists is file:Error || !ymlExists {
            utils:logVerbose(string `no YAML aligned spec found to convert at ${yamlAlignedSpec}`);
            return;
        }
        yamlAlignedSpec = ymlAlignedSpec;
    }

    string|io:Error yamlContent = io:fileReadString(yamlAlignedSpec);
    if yamlContent is io:Error {
        return error("Failed to read YAML aligned spec file: " + yamlContent.message());
    }

    json|yaml:Error jsonData = yaml:readString(yamlContent);

    if jsonData is yaml:Error {
        utils:logVerbose(string `Ballerina YAML parser failed, trying yq fallback: ${jsonData.message()}`);

        string escapedPath = "'" + regex:replaceAll(yamlAlignedSpec, "'", "'\\\\''") + "'";

        utils:CommandResult yqResult = utils:executeCommand(
            string `yq -o=json '.' ${escapedPath}`,
            "."
        );

        if utils:isCommandSuccessfull(yqResult) && yqResult.stdout.length() > 0 {
            io:Error? writeResult = io:fileWriteString(jsonAlignedSpec, yqResult.stdout);
            if writeResult is io:Error {
                return error("Failed to write JSON aligned spec file: " + writeResult.message());
            }
            utils:logVerbose("converted YAML to JSON via yq");
            return;
        }

        utils:CommandResult pythonResult = utils:executeCommand(
            string `python3 -c 'import sys,yaml,json; print(json.dumps(yaml.safe_load(sys.stdin), indent=2))' < ${escapedPath}`,
            "."
        );

        if utils:isCommandSuccessfull(pythonResult) && pythonResult.stdout.length() > 0 {
            io:Error? writeResult = io:fileWriteString(jsonAlignedSpec, pythonResult.stdout);
            if writeResult is io:Error {
                return error("Failed to write JSON aligned spec file: " + writeResult.message());
            }
            utils:logVerbose("converted YAML to JSON via Python");
            return;
        }

        return error("Failed to parse YAML content: " + jsonData.message() +
            ". Fallback tools (yq, python) also failed or not available.");
    }

    io:Error? writeResult = io:fileWriteJson(jsonAlignedSpec, jsonData);
    if writeResult is io:Error {
        return error("Failed to write JSON aligned spec file: " + writeResult.message());
    }

    utils:logVerbose("✓ converted YAML aligned spec to JSON");
    return;
}

