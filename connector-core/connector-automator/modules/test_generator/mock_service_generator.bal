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

function generateMockServerStub(string connectorPath, string specPath, string[]? selectedOperations) returns error? {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string testsDir = ballerinaDir + "/tests";

    string absSpecPath = check file:getAbsolutePath(specPath);
    string absTestsDir = check file:getAbsolutePath(testsDir);

    check file:createDir(testsDir, file:RECURSIVE);

    // Generating mock server stub.
    string command;
    if selectedOperations is () {
        command = string `bal openapi -i ${absSpecPath} --mode service -o ${absTestsDir}`;
    } else {
        string operationsList = string:'join(",", ...selectedOperations);
        command = string `bal openapi -i ${absSpecPath} --mode service -o ${absTestsDir} --operations ${operationsList}`;
    }

    utils:CommandResult result = utils:executeCommand(command, ballerinaDir);
    if !result.success {
        return error("Failed to generate mock server stub using ballerina openAPI tool" + result.stderr);
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

    // Delete duplicate types.bal
    string serviceTypesPath = testsDir + "/types.bal";
    if check file:test(serviceTypesPath, file:EXISTS) {
        check file:remove(serviceTypesPath);
        utils:logVerbose("removed generated tests/types.bal");
    }
}
