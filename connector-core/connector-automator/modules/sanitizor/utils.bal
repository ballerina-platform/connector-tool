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

import ballerina/data.jsondata;
import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/yaml;

// Helper function to generate unique request IDs
function generateRequestId(string schemaName, string path, string requestType) returns string {
    string cleanPath = regexp:replaceAll(re `_`, path, "_u");
    cleanPath = regexp:replaceAll(re `\.`, cleanPath, "_d");
    cleanPath = regexp:replaceAll(re `\[`, cleanPath, "_l");
    cleanPath = regexp:replaceAll(re `\]`, cleanPath, "_r");
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
    return regexp:isFullMatch(re `[A-Z][a-zA-Z0-9]*`, name);
}

// Helper function to generate unique request IDs for operationId requests
function generateOperationRequestId(string path, string method) returns string {
    string cleanPath = regexp:replaceAll(re `_`, path, "_u");
    cleanPath = regexp:replaceAll(re `\.`, cleanPath, "_d");
    cleanPath = regexp:replaceAll(re `\[`, cleanPath, "_l");
    cleanPath = regexp:replaceAll(re `\]`, cleanPath, "_r");
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

function writeJsonAtomically(string targetPath, json content) returns error? {
    string|error prettyResult = jsondata:prettify(content);
    if prettyResult is error {
        return prettyResult;
    }
    string temporaryPath = targetPath + ".tmp";
    error? writeResult = io:fileWriteString(temporaryPath, prettyResult);
    if writeResult is error {
        return writeResult;
    }

    string backupPath = targetPath + ".bak";
    boolean|file:Error targetExists = file:test(targetPath, file:EXISTS);
    if targetExists is file:Error {
        do {
            check file:remove(temporaryPath);
        } on fail {
        }
        return targetExists;
    }
    if targetExists {
        boolean|file:Error backupExists = file:test(backupPath, file:EXISTS);
        if backupExists is file:Error {
            do {
                check file:remove(temporaryPath);
            } on fail {
            }
            return backupExists;
        }
        if backupExists {
            check file:remove(backupPath);
        }
        error? backupResult = file:rename(targetPath, backupPath);
        if backupResult is error {
            do {
                check file:remove(temporaryPath);
            } on fail {
            }
            return backupResult;
        }
    }

    error? renameResult = file:rename(temporaryPath, targetPath);
    if renameResult is error {
        do {
            check file:remove(temporaryPath);
        } on fail {
        }
        if targetExists {
            do {
                check file:rename(backupPath, targetPath);
            } on fail {
            }
        }
        return renameResult;
    }
    if targetExists {
        do {
            check file:remove(backupPath);
        } on fail {
        }
    }
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

        string escapedPath = "'" + regexp:replaceAll(re `'`, yamlAlignedSpec, "'\\''") + "'";

        utils:CommandResult yqResult = utils:executeCommand(
            string `yq -o=json '.' ${escapedPath}`,
            "."
        );

        if utils:isCommandSuccessfull(yqResult) && yqResult.stdout.length() > 0 {
            json|error yqJson = yqResult.stdout.fromJsonString();
            if yqJson is json {
                check writeJsonAtomically(jsonAlignedSpec, yqJson);
                utils:logVerbose("converted YAML to JSON via yq");
                return;
            }
            utils:logVerbose("yq produced invalid JSON, trying Python fallback");
        }

        utils:CommandResult pythonResult = utils:executeCommand(
            string `python3 -c 'import sys,yaml,json; print(json.dumps(yaml.safe_load(sys.stdin), indent=2))' < ${escapedPath}`,
            "."
        );

        if utils:isCommandSuccessfull(pythonResult) && pythonResult.stdout.length() > 0 {
            json|error pythonJson = pythonResult.stdout.fromJsonString();
            if pythonJson is json {
                check writeJsonAtomically(jsonAlignedSpec, pythonJson);
                utils:logVerbose("converted YAML to JSON via Python");
                return;
            }
        }

        return error("Failed to parse YAML content: " + jsonData.message() +
            ". Fallback tools (yq, python) also failed or not available.");
    }

    check writeJsonAtomically(jsonAlignedSpec, jsonData);

    utils:logVerbose("✓ converted YAML aligned spec to JSON");
    return;
}
