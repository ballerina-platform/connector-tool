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
import ballerina/lang.regexp;

function generateMockServer(string connectorPath, string specPath) returns error? {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string testsDir = ballerinaDir + "/tests";
    int operationCount = check countOperationsInSpec(specPath);
    utils:logVerbose(string `total operations in spec: ${operationCount}`);

    string absSpecPath = check file:getAbsolutePath(specPath);
    string absTestsDir = check file:getAbsolutePath(testsDir);

    check file:createDir(testsDir, file:RECURSIVE);

    string command;

    if operationCount <= MAX_OPERATIONS {
        utils:logVerbose(string `using all ${operationCount} operations`);
        command = string `bal openapi -i ${absSpecPath} --mode service -o ${absTestsDir}`;
    } else {
        utils:logVerbose(string `filtering from ${operationCount} to ${MAX_OPERATIONS} most useful operations`);
        string operationsList = check selectOperationsUsingAI(specPath);
        utils:logVerbose(string `selected operations: ${operationsList}`);
        command = string `bal openapi -i ${absSpecPath} --mode service -o ${absTestsDir} --operations ${operationsList}`;
    }

    utils:CommandResult result = utils:executeCommand(command, ballerinaDir);
    if !result.success {
        return error("Failed to generate mock server using ballerina openAPI tool" + result.stderr);
    }

    // Rename the generated service scaffold to mock_service.bal
    string serviceFileOld = testsDir + "/aligned_ballerina_openapi_service.bal";
    string serviceFileNew = testsDir + "/mock_service.bal";
    if check file:test(serviceFileOld, file:EXISTS) {
        check file:rename(serviceFileOld, serviceFileNew);
        utils:logVerbose("renamed service file to mock_service.bal");
    } else {
        return error(string `bal openapi --mode service succeeded but expected scaffold not found: ${serviceFileOld}`);
    }

    // Merge service-unique types (e.g. AnydataDefault) into root types.bal, then delete tests/types.bal.
    // bal openapi --mode service generates types in tests/types.bal that differ from the client-side root
    // types.bal — notably AnydataDefault, which is used throughout mock_service.bal as a return type.
    check mergeServiceTypes(testsDir + "/types.bal", ballerinaDir + "/types.bal");
}

// Appends type definitions from serviceTypesPath that are not already in rootTypesPath, then deletes
// serviceTypesPath. This preserves service-only types (e.g. AnydataDefault) that mock_service.bal
// references but the client-generated root types.bal does not define.
function mergeServiceTypes(string serviceTypesPath, string rootTypesPath) returns error? {
    if !(check file:test(serviceTypesPath, file:EXISTS)) {
        return;
    }

    string rootContent = check io:fileReadString(rootTypesPath);
    string serviceContent = check io:fileReadString(serviceTypesPath);

    // Collect type names already declared in root types.bal
    string[] rootTypeNames = [];
    regexp:Span[] typeDecls = re`(?:public )?type [A-Za-z][A-Za-z0-9_]* `.findAll(rootContent);
    foreach regexp:Span span in typeDecls {
        string decl = span.substring();
        int? typeKw = decl.indexOf("type ");
        if typeKw is int {
            string afterType = decl.substring(typeKw + 5);
            int? trailingSpace = afterType.indexOf(" ");
            if trailingSpace is int {
                rootTypeNames.push(afterType.substring(0, trailingSpace));
            }
        }
    }

    // Walk tests/types.bal, collecting import lines missing from root and type blocks not in root
    string[] serviceLines = re`\n`.split(serviceContent);
    string missingImports = "";
    string uniqueDefinitions = "";
    int lineIdx = 0;

    while lineIdx < serviceLines.length() {
        string line = serviceLines[lineIdx];

        // Carry over any import that root types.bal does not already have
        if line.trim().startsWith("import ") {
            if !rootContent.includes(line.trim()) {
                missingImports += line + "\n";
            }
            lineIdx += 1;
        } else {
            regexp:Span? typeStart = re`^(?:public )?type [A-Za-z][A-Za-z0-9_]* `.find(line);
            if typeStart is regexp:Span {
                // Extract type name from the matched prefix
                string matched = typeStart.substring();
                int? typeKw = matched.indexOf("type ");
                string typeName = "";
                if typeKw is int {
                    string afterType = matched.substring(typeKw + 5);
                    int? trailingSpace = afterType.indexOf(" ");
                    if trailingSpace is int {
                        typeName = afterType.substring(0, trailingSpace);
                    }
                }

                if typeName.length() > 0 && rootTypeNames.indexOf(typeName) is () {
                    // Unique to service — collect the full definition block
                    string block = line + "\n";
                    int depth = re`\{`.findAll(line).length() - re`\}`.findAll(line).length();
                    boolean blockDone = depth == 0 && line.endsWith(";");
                    lineIdx += 1;

                    while !blockDone && lineIdx < serviceLines.length() {
                        string blockLine = serviceLines[lineIdx];
                        block += blockLine + "\n";
                        depth += re`\{`.findAll(blockLine).length() - re`\}`.findAll(blockLine).length();
                        lineIdx += 1;
                        blockDone = depth <= 0 && (blockLine.endsWith("};") || blockLine.endsWith("|};") || blockLine.endsWith(";"));
                        // Safety: negative depth means we have overshot — stop to avoid consuming unrelated lines
                        if depth < 0 {
                            break;
                        }
                    }
                    uniqueDefinitions += block + "\n";
                } else {
                    lineIdx += 1;
                }
            } else {
                lineIdx += 1;
            }
        }
    }

    if uniqueDefinitions.trim().length() > 0 || missingImports.length() > 0 {
        check io:fileWriteString(rootTypesPath, "\n" + missingImports + uniqueDefinitions, io:APPEND);
        utils:logVerbose("merged service-unique types into root types.bal");
    }

    check file:remove(serviceTypesPath);
    utils:logVerbose("removed generated tests/types.bal (connector types merged into root)");
}

function countOperationsInSpec(string specPath) returns int|error {
    string specContent = check io:fileReadString(specPath);
    regexp:RegExp operationIdPattern = re `"operationId"\s*:\s*"[^"]*"`;
    regexp:Span[] matches = operationIdPattern.findAll(specContent);
    return matches.length();
}
