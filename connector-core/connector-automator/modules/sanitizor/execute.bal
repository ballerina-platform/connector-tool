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

public function executeSanitizor(string inputSpecPath, string specDir) returns error? {
    utils:logVerbose(string `input: ${inputSpecPath}`);
    utils:logVerbose(string `output: ${specDir}/aligned_ballerina_openapi.json`);

    // Conditional step:  create path+method:operationId map 
    map<map<string>>? priorIds = ();
    string existingAlignedSpec = specDir + "/aligned_ballerina_openapi.json";
    boolean|file:Error alignedSpecExists = file:test(existingAlignedSpec, file:EXISTS);
    if alignedSpecExists is file:Error {
        return error("Failed to check for previous aligned spec: " + alignedSpecExists.message());
    } else if alignedSpecExists {
        map<map<string>>|error priorMap = buildOperationIdMap(existingAlignedSpec);
        if priorMap is map<map<string>> && priorMap.length() > 0 {
            priorIds = priorMap;
        } else {
            utils:logVerbose("previous aligned spec found but contains no operationIds — all IDs will be AI-improved");
        }
    }

    error? llmInitResult = utils:initAIService();
    if llmInitResult is error {
        return error("AI service initialization failed — cannot run sanitization", llmInitResult);
    }

    // Step 1: Flatten
    utils:logVerbose("flattening OpenAPI specification");
    string flattenedSpecPath = specDir;
    error? createDirResult = file:createDir(flattenedSpecPath, file:RECURSIVE);
    if createDirResult is error {
        return error("Failed to create output directory: " + flattenedSpecPath + ", reason: " + createDirResult.message());
    }
    utils:CommandResult flattenResult = utils:executeBalFlatten(inputSpecPath, flattenedSpecPath);
    if !utils:isCommandSuccessfull(flattenResult) {
        utils:logWarn(string `flatten operation failed: ${flattenResult.stderr.trim()}`);
    } else {
        utils:logVerbose("✓ spec flattened");
    }

    // Step 2: Align
    utils:logVerbose("aligning OpenAPI specification");
    string alignedSpecPath = specDir;

    string flattenedSpec;
    if isYamlFormat(inputSpecPath) {
        string yamlFlattenedSpec = flattenedSpecPath + "/flattened_openapi.yaml";
        string ymlFlattenedSpec = flattenedSpecPath + "/flattened_openapi.yml";
        boolean|file:Error yamlExists = file:test(yamlFlattenedSpec, file:EXISTS);
        if yamlExists is boolean && yamlExists {
            flattenedSpec = yamlFlattenedSpec;
        } else {
            boolean|file:Error ymlExists = file:test(ymlFlattenedSpec, file:EXISTS);
            if ymlExists is boolean && ymlExists {
                flattenedSpec = ymlFlattenedSpec;
            } else {
                flattenedSpec = yamlFlattenedSpec;
            }
        }
    } else {
        flattenedSpec = flattenedSpecPath + "/flattened_openapi.json";
    }

    utils:CommandResult alignResult = utils:executeBalAlign(flattenedSpec, alignedSpecPath);
    if !utils:isCommandSuccessfull(alignResult) {
        utils:logWarn(string `align operation failed: ${alignResult.stderr.trim()}`);
    } else {
        utils:logVerbose("✓ spec aligned");
    }

    if isYamlFormat(inputSpecPath) {
        utils:logVerbose("converting aligned YAML spec to JSON");
        error? conversionResult = convertAlignedYamlToJson(alignedSpecPath);
        if conversionResult is error {
            utils:logWarn(string `YAML to JSON conversion failed: ${conversionResult.message()}`);
            return error("YAML to JSON conversion failed: " + conversionResult.message());
        }
        utils:logVerbose("✓ YAML spec converted to JSON");
    }

    string alignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    // Conditional step: improve operationIds
    utils:logVerbose("improving operationIds");
    int|error operationIdResult = improveOperationIds(alignedSpec, priorIds);
    if operationIdResult is error {
        utils:logWarn(string `operationId improvement failed: ${operationIdResult.message()}`);
    } else {
        utils:logInfo(string `  improved ${operationIdResult} operationId${operationIdResult == 1 ? "" : "s"}`);
    }

    // Step 3: Schema renaming
    utils:logVerbose("renaming InlineResponse schemas");
    int|error schemaRenameResult = renameInlineResponseSchemasBatchWithRetry(alignedSpec);
    if schemaRenameResult is error {
        utils:logWarn(string `schema renaming failed: ${schemaRenameResult.message()}`);
    } else {
        utils:logInfo(string `  renamed ${schemaRenameResult} schema${schemaRenameResult == 1 ? "" : "s"} to meaningful names`);
    }

    // Step 4: Adding missing descriptions
    utils:logVerbose("enhancing field descriptions");
    DescriptionEnhancementResult|error descriptionsResult = addMissingDescriptionsBatchWithRetry(alignedSpec);
    if descriptionsResult is error {
        utils:logWarn(string `description enhancement failed: ${descriptionsResult.message()}`);
    } else {
        utils:logInfo(string `  added ${descriptionsResult.descriptionsAdded} missing description${descriptionsResult.descriptionsAdded == 1 ? "" : "s"}`);
    }

    // Step 5: Operation summary improvement
    utils:logVerbose("improving operation summaries");
    int|error summariesResult = improveOperationSummariesBatchWithRetry(alignedSpec);
    if summariesResult is error {
        utils:logWarn(string `summary improvement failed: ${summariesResult.message()}`);
    } else {
        utils:logInfo(string `  updated ${summariesResult} operation summar${summariesResult == 1 ? "y" : "ies"}`);
    }
}
