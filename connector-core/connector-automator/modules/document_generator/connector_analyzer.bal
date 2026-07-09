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
import ballerina/lang.'string as strings;
import ballerina/lang.regexp;

public function analyzeConnector(string connectorPath) returns ConnectorMetadata|error {
    file:MetaData|error pathMeta = file:getMetaData(connectorPath);
    if pathMeta is error {
        return error("Invalid connector path: " + connectorPath);
    }

    if !pathMeta.dir {
        return error("Connector path must be a directory");
    }

    ConnectorMetadata metadata = {
        connectorName: "",
        version: "1.0.0",
        examples: [],
        clientBalContent: "",
        typesBalContent: "",
        existingKeywords: [],
        description: (),
        icon: ()
    };

    // Analyze Ballerina.toml
    check analyzeBallerinaToml(connectorPath, metadata);

    // Get client.bal and types.bal content
    check analyzeClientAndTypesFiles(connectorPath, metadata);

    // Analyze examples directory
    check analyzeExamples(connectorPath, metadata);

    return metadata;
}

function analyzeClientAndTypesFiles(string connectorPath, ConnectorMetadata metadata) returns error? {
    // Get client.bal content
    string[] possibleClientPaths = [
        connectorPath + "/ballerina/client.bal",
        connectorPath + "/client.bal"
    ];

    foreach string clientPath in possibleClientPaths {
        if check file:test(clientPath, file:EXISTS) {
            metadata.clientBalContent = check io:fileReadString(clientPath);
            break;
        }
    }

    // Get types.bal content
    string[] possibleTypesPaths = [
        connectorPath + "/ballerina/types.bal",
        connectorPath + "/types.bal"
    ];

    foreach string typesPath in possibleTypesPaths {
        if check file:test(typesPath, file:EXISTS) {
            metadata.typesBalContent = check io:fileReadString(typesPath);
            break;
        }
    }
}

function analyzeBallerinaToml(string connectorPath, ConnectorMetadata metadata) returns error? {
    string ballerinaTomlPath = connectorPath + "/Ballerina.toml";

    if !check file:test(ballerinaTomlPath, file:EXISTS) {
        ballerinaTomlPath = connectorPath + "/ballerina/Ballerina.toml";
    }

    if check file:test(ballerinaTomlPath, file:EXISTS) {
        string content = check io:fileReadString(ballerinaTomlPath);

        string[] lines = regexp:split(re `\n`, content);
        foreach string line in lines {
            string trimmedLine = strings:trim(line);
            if strings:startsWith(trimmedLine, "name") {
                string[] parts = regexp:split(re `=`, trimmedLine);
                if parts.length() > 1 {
                    metadata.connectorName = strings:trim(regexp:replaceAll(re `"`, parts[1], ""));
                }
            }
            if strings:startsWith(trimmedLine, "version") {
                string[] parts = regexp:split(re `=`, trimmedLine);
                if parts.length() > 1 {
                    metadata.version = strings:trim(regexp:replaceAll(re `"`, parts[1], ""));
                }
            }
            if strings:startsWith(trimmedLine, "description") {
                string[] parts = regexp:split(re `=`, trimmedLine);
                if parts.length() > 1 {
                    metadata.description = strings:trim(regexp:replaceAll(re `"`, parts[1], ""));
                }
            }
            if strings:startsWith(trimmedLine, "icon") {
                string[] parts = regexp:split(re `=`, trimmedLine);
                if parts.length() > 1 {
                    metadata.icon = strings:trim(regexp:replaceAll(re `"`, parts[1], ""));
                }
            }
            if strings:startsWith(trimmedLine, "keywords") {
                int? bracketOpen = trimmedLine.indexOf("[");
                int? bracketClose = trimmedLine.lastIndexOf("]");
                if bracketOpen is int && bracketClose is int && bracketClose > bracketOpen {
                    string arrayContent = trimmedLine.substring(bracketOpen + 1, bracketClose);
                    string[] tokens = regexp:split(re `,`, arrayContent);
                    string[] keywords = [];
                    foreach string token in tokens {
                        string kw = strings:trim(regexp:replaceAll(re `"`, token, ""));
                        if kw.length() > 0 {
                            keywords.push(kw);
                        }
                    }
                    metadata.existingKeywords = keywords;
                }
            }

        }
    }
}

function analyzeExamples(string connectorPath, ConnectorMetadata metadata) returns error? {
    string examplesPath = connectorPath + "/examples";

    if check file:test(examplesPath, file:EXISTS) {
        file:MetaData[] examples = check file:readDir(examplesPath);

        foreach file:MetaData example in examples {
            if example.dir {
                string exampleName = example.absPath.substring(examplesPath.length());
                string normalizedExampleName = trimLeadingPathSeparators(exampleName);
                if !normalizedExampleName.startsWith(".") && !normalizedExampleName.startsWith("./") &&
                        !normalizedExampleName.startsWith(".\\") {
                    metadata.examples.push(normalizedExampleName);
                }
            }
        }
    }
}

public function getConnectorSummary(ConnectorMetadata metadata) returns string {
    string summary = "Connector: " + metadata.connectorName + "\n";
    summary += "Version: " + metadata.version + "\n";
    summary += "Examples: " + strings:'join(", ", ...metadata.examples) + "\n";

    return summary;
}

public function analyzeExampleDirectory(string examplePath, string exampleDirName) returns ExampleData|error {
    ExampleData exampleData = {
        exampleName: formatExampleName(exampleDirName),
        exampleDirName: exampleDirName,
        balFiles: [],
        balFileContents: [],
        mainBalContent: ""
    };

    file:MetaData[] files = check file:readDir(examplePath);

    foreach file:MetaData fileInfo in files {
        if !fileInfo.dir && fileInfo.absPath.endsWith(".bal") {
            // Fix: Get just the filename without the leading slash
            string fileName = fileInfo.absPath.substring(examplePath.length());
            // Remove leading slash if present
            if fileName.startsWith("/") {
                fileName = fileName.substring(1);
            }

            string content = check io:fileReadString(fileInfo.absPath);

            exampleData.balFiles.push(fileName);
            exampleData.balFileContents.push(content);

            // If it's main.bal, store it separately
            if fileName == "main.bal" {
                exampleData.mainBalContent = content;
            }
        }
    }

    return exampleData;
}

