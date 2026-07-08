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
import ballerina/io;
import ballerina/lang.runtime;

configurable RetryConfig retryConfig = {};

public function generateDescriptionsBatchWithRetry(DescriptionRequest[] requests, string apiContext, RetryConfig? config = ()) returns BatchDescriptionResponse[]|error {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchDescriptionResponse[]|error result = generateDescriptionsBatch(requests, apiContext);

        if result is BatchDescriptionResponse[] {
            if attempt > 0 {
                utils:logVerbose(string `batch description generation succeeded after retry (attempt ${attempt})`);
            }
            return result;
        } else {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch description generation failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch description generation: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch description generation failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`);
            runtime:sleep(delay);
            attempt += 1;
        }
    }

    return error("Unexpected error in retry logic");
}

public function generateOperationIdsBatchWithRetry(OperationIdRequest[] requests, string apiContext, string[] existingOperationIds, RetryConfig? config = ()) returns BatchOperationIdResponse[]|error {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchOperationIdResponse[]|error result = generateOperationIdsBatch(requests, apiContext, existingOperationIds);

        if result is BatchOperationIdResponse[] {
            if attempt > 0 {
                utils:logVerbose(string `batch operationId generation succeeded after retry (attempt ${attempt})`);
            }
            return result;
        } else {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch operationId generation failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch operationId generation: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch operationId generation failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`);
            runtime:sleep(delay);
            attempt += 1;
        }
    }

    return error("Unexpected error in retry logic");
}

public function generateSchemaNamesBatchWithRetry(SchemaRenameRequest[] requests, string apiContext, string[] existingNames, RetryConfig? config = ()) returns BatchRenameResponse[]|error {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchRenameResponse[]|error result = generateSchemaNamesBatch(requests, apiContext, existingNames);

        if result is BatchRenameResponse[] {
            if attempt > 0 {
                utils:logVerbose(string `batch schema naming succeeded after retry (attempt ${attempt})`);
            }
            return result;
        } else {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch schema naming failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch schema naming: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch schema naming failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`);
            runtime:sleep(delay);
            attempt += 1;
        }
    }

    return error("Unexpected error in retry logic");
}

public function addMissingDescriptionsBatchWithRetry(string specFilePath, RetryConfig? config = ()) returns DescriptionEnhancementResult|error {
    utils:logVerbose(string `processing spec for missing descriptions: ${specFilePath} (batch size ${BATCH_SIZE})`);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;
    int descriptionsAdded = 0;

    if specJson is map<json> {
        map<json> specMap = <map<json>>specJson;
        string apiContext = extractApiContext(specJson);

        DescriptionRequest[] allRequests = [];
        map<string> requestToLocationMap = {};

        json|error componentsResult = specMap.get("components");
        if componentsResult is map<json> {
            json|error schemasResult = componentsResult.get("schemas");
            if schemasResult is map<json> {
                map<json> schemas = <map<json>>schemasResult;

                foreach string schemaName in schemas.keys() {
                    json|error schemaResult = schemas.get(schemaName);
                    if schemaResult is map<json> {
                        map<json> schemaMap = <map<json>>schemaResult;
                        collectDescriptionRequests(schemaMap, schemaName, "", allRequests, requestToLocationMap, specJson);
                    }
                }
            }
        }

        collectParameterDescriptionRequests(specJson, allRequests, requestToLocationMap);
        collectOperationDescriptionRequests(specJson, allRequests, requestToLocationMap);

        int totalRequests = allRequests.length();
        utils:logVerbose(string `collected ${totalRequests} description requests`);

        int startIdx = 0;
        while startIdx < totalRequests {
            int endIdx = startIdx + BATCH_SIZE;
            if endIdx > totalRequests {
                endIdx = totalRequests;
            }

            DescriptionRequest[] batch = allRequests.slice(startIdx, endIdx);
            int batchNum = (startIdx / BATCH_SIZE) + 1;
            utils:logVerbose(string `processing descriptions batch ${batchNum} (${batch.length()} items)`);

            BatchDescriptionResponse[]|error batchResult = generateDescriptionsBatchWithRetry(batch, apiContext, config);
            if batchResult is BatchDescriptionResponse[] {
                utils:logVerbose(string `batch ${batchNum} complete (${batchResult.length()} descriptions)`);

                foreach BatchDescriptionResponse response in batchResult {
                    string? location = requestToLocationMap[response.id];
                    if location is string {
                        error? updateResult = ();

                        if location.startsWith("paths.") && location.includes("parameters[name=") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateParameterDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else if location.startsWith("paths.") && location.includes(".responses.") && location.endsWith(".description") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateResponseDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else if location.startsWith("paths.") && !location.includes(".properties.") && !location.includes(".responses.") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateOperationDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else {
                            json|error componentsResult2 = specMap.get("components");
                            if componentsResult2 is map<json> {
                                json|error schemasResult2 = componentsResult2.get("schemas");
                                if schemasResult2 is map<json> {
                                    updateResult = updateDescriptionInSpec(<map<json>>schemasResult2, location, response.description);
                                }
                            }
                        }

                        if updateResult is () {
                            descriptionsAdded += 1;
                        } else {
                            utils:logError(string `failed to apply description for ${response.id}: ${updateResult.message()}`);
                        }
                    }
                }
            } else {
                utils:logError(string `descriptions batch ${batchNum} failed after all retries: ${batchResult.message()}`);
            }
            startIdx += BATCH_SIZE;
        }
    }

    string|error prettifiedResult = jsondata:prettify(specJson);
    if prettifiedResult is error {
        return error("Failed to prettify JSON", prettifiedResult);
    }

    error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
    if writeResult is error {
        return error("Failed to write updated OpenAPI spec", writeResult);
    }

    return {descriptionsAdded: descriptionsAdded, summariesAdded: 0};
}

public function improveOperationSummariesBatchWithRetry(string specFilePath, RetryConfig? config = ()) returns int|error {
    utils:logVerbose(string `processing spec for operation summaries: ${specFilePath} (batch size ${BATCH_SIZE})`);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;
    int summariesImproved = 0;

    if specJson is map<json> {
        map<json> specMap = <map<json>>specJson;
        string apiContext = extractApiContext(specJson);

        DescriptionRequest[] allRequests = [];
        map<string> requestToLocationMap = {};

        collectOperationSummaryRequests(specJson, allRequests, requestToLocationMap);

        int totalRequests = allRequests.length();
        utils:logVerbose(string `collected ${totalRequests} summary requests`);

        int startIdx = 0;
        while startIdx < totalRequests {
            int endIdx = startIdx + BATCH_SIZE;
            if endIdx > totalRequests {
                endIdx = totalRequests;
            }

            DescriptionRequest[] batch = allRequests.slice(startIdx, endIdx);
            int batchNum = (startIdx / BATCH_SIZE) + 1;
            utils:logVerbose(string `processing summaries batch ${batchNum} (${batch.length()} items)`);

            BatchDescriptionResponse[]|error batchResult = generateDescriptionsBatchWithRetry(batch, apiContext, config);
            if batchResult is BatchDescriptionResponse[] {
                utils:logVerbose(string `batch ${batchNum} complete (${batchResult.length()} summaries)`);

                foreach BatchDescriptionResponse response in batchResult {
                    string? location = requestToLocationMap[response.id];
                    if location is string {
                        json|error pathsResult = specMap.get("paths");
                        if pathsResult is map<json> {
                            error? updateResult = updateOperationSummaryInSpec(<map<json>>pathsResult, location, response.description);
                            if updateResult is () {
                                summariesImproved += 1;
                            } else {
                                utils:logError(string `failed to apply summary for ${response.id}: ${updateResult.message()}`);
                            }
                        }
                    }
                }
            } else {
                utils:logError(string `summaries batch ${batchNum} failed after all retries: ${batchResult.message()}`);
            }
            startIdx += BATCH_SIZE;
        }
    }

    string|error prettifiedResult = jsondata:prettify(specJson);
    if prettifiedResult is error {
        return error("Failed to prettify JSON", prettifiedResult);
    }

    error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
    if writeResult is error {
        return error("Failed to write updated OpenAPI spec", writeResult);
    }

    return summariesImproved;
}

public function renameInlineResponseSchemasBatchWithRetry(string specFilePath, RetryConfig? config = ()) returns int|error {
    utils:logVerbose(string `processing spec to rename InlineResponse schemas: ${specFilePath}`);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;

    if !(specJson is map<json>) {
        return error("spec is not a valid JSON object");
    }

    map<json> specMap = <map<json>>specJson;

    json|error componentsResult = specMap.get("components");
    if !(componentsResult is map<json>) {
        return error("No components section found in OpenAPI spec");
    }

    map<json> componentsMap = <map<json>>componentsResult;
    json|error schemasResult = componentsMap.get("schemas");
    if !(schemasResult is map<json>) {
        return error("No schemas section found in components");
    }

    map<json> schemasMap = <map<json>>schemasResult;

    string[] allExistingNames = [];
    foreach string schemaName in schemasMap.keys() {
        if (!schemaName.startsWith("InlineResponse")) {
            allExistingNames.push(schemaName);
        }
    }

    SchemaRenameRequest[] renameRequests = [];
    string apiContext = extractApiContext(specMap);

    foreach string schemaName in schemasMap.keys() {
        if (schemaName.startsWith("InlineResponse") || schemaName.endsWith("AllOf2") || schemaName.endsWith("OneOf2")) {
            json|error schemaResult = schemasMap.get(schemaName);
            if (schemaResult is map<json>) {
                string schemaDefinition = (<map<json>>schemaResult).toJsonString();
                string usageContext = extractSchemaUsageContext(schemaName, specMap);

                renameRequests.push({
                    originalName: schemaName,
                    schemaDefinition: schemaDefinition,
                    usageContext: usageContext
                });
            }
        }
    }

    if renameRequests.length() == 0 {
        utils:logVerbose("no InlineResponse schemas found to rename");
        return 0;
    }

    map<string> nameMapping = {};
    int renamedCount = 0;
    int totalRequests = renameRequests.length();
    utils:logVerbose(string `collected ${totalRequests} schema rename requests`);

    int startIdx = 0;
    while startIdx < totalRequests {
        int endIdx = startIdx + BATCH_SIZE;
        if endIdx > totalRequests {
            endIdx = totalRequests;
        }

        SchemaRenameRequest[] batch = renameRequests.slice(startIdx, endIdx);
        int batchNum = (startIdx / BATCH_SIZE) + 1;
        utils:logVerbose(string `processing schema rename batch ${batchNum} (${batch.length()} schemas)`);

        BatchRenameResponse[]|error batchResult = generateSchemaNamesBatchWithRetry(batch, apiContext, allExistingNames, config);
        if batchResult is BatchRenameResponse[] {
            utils:logVerbose(string `schema rename batch ${batchNum} complete (${batchResult.length()} schemas)`);

            foreach BatchRenameResponse response in batchResult {
                string newName = response.newName;

                if (isValidSchemaName(newName)) {
                    if (!isNameTaken(newName, allExistingNames, nameMapping)) {
                        allExistingNames.push(newName);
                        nameMapping[response.originalName] = newName;
                        renamedCount += 1;
                    } else {
                        utils:logWarn(string `duplicate schema name generated for '${response.originalName}': '${newName}', using fallback`);
                        string fallbackName = newName + "Alt";
                        int counter = 1;
                        while (isNameTaken(fallbackName, allExistingNames, nameMapping)) {
                            fallbackName = newName + "Alt" + counter.toString();
                            counter += 1;
                        }
                        allExistingNames.push(fallbackName);
                        nameMapping[response.originalName] = fallbackName;
                        renamedCount += 1;
                    }
                } else {
                    utils:logWarn(string `invalid schema name generated for '${response.originalName}': '${newName}', using fallback`);
                    string suffix = response.originalName;
                    if response.originalName.startsWith("InlineResponse") && response.originalName.length() > 14 {
                        suffix = response.originalName.substring(14);
                    }
                    string fallbackBaseName = "Schema" + suffix;
                    string fallbackName = fallbackBaseName;
                    int counter = 1;
                    while (isNameTaken(fallbackName, allExistingNames, nameMapping)) {
                        fallbackName = fallbackBaseName + counter.toString();
                        counter += 1;
                    }
                    allExistingNames.push(fallbackName);
                    nameMapping[response.originalName] = fallbackName;
                    renamedCount += 1;
                }
            }
        } else {
            utils:logError(string `schema rename batch ${batchNum} failed after all retries: ${batchResult.message()}`);
        }

        startIdx += BATCH_SIZE;
    }

    if (nameMapping.length() > 0) {
        map<json> newSchemas = {};
        foreach string oldName in schemasMap.keys() {
            json|error schemaValueResult = schemasMap.get(oldName);
            if (schemaValueResult is json) {
                if (nameMapping.hasKey(oldName)) {
                    string? newNameResult = nameMapping[oldName];
                    if (newNameResult is string) {
                        newSchemas[newNameResult] = schemaValueResult;
                    }
                } else {
                    newSchemas[oldName] = schemaValueResult;
                }
            }
        }

        componentsMap["schemas"] = newSchemas;
        specMap["components"] = componentsMap;

        json updatedSpecResult = updateSchemaReferences(specMap, nameMapping);

        string|error prettifiedResult = jsondata:prettify(updatedSpecResult);
        if prettifiedResult is error {
            return error("Failed to prettify JSON", prettifiedResult);
        }

        error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
        if writeResult is error {
            return error("Failed to write updated OpenAPI spec", writeResult);
        }
    }

    return renamedCount;
}

public function improveOperationIdsBatchWithRetry(string specFilePath, map<map<string>>? priorOperationIds) returns int|error {
    
    utils:logVerbose(string `processing spec for operationId improvement: ${specFilePath}`);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error("Failed to read OpenAPI spec file", specResult);
    }
    json specJson = specResult;
    if !(specJson is map<json>) {
        return error("spec is not a valid JSON object");
    }
    map<json> specMap = <map<json>>specJson;

    json|error pathsResult = specMap.get("paths");
    if !(pathsResult is map<json>) {
        return error("No paths section found in OpenAPI spec");
    }
    map<json> paths = <map<json>>pathsResult;
    string apiContext = extractApiContext(specMap);

    // Pass A: Deterministic restoration from prior map.
    int reuseCount = 0;
    if priorOperationIds is map<map<string>> {
        string[] httpMethods = ["get", "post", "put", "delete", "patch", "head", "options", "trace"];
        foreach string path in paths.keys() {
            json|error pathItem = paths.get(path);
            if pathItem is map<json> {
                map<json> pathItemMap = <map<json>>pathItem;
                foreach string method in httpMethods {
                    if pathItemMap.hasKey(method) {
                        map<string>? methodMap = priorOperationIds[path];
                        string? priorId = methodMap is map<string> ? methodMap[method] : ();
                        if priorId is string {
                            error? updateResult = updateOperationIdInSpec(paths, path, method, priorId);
                            if updateResult is () {
                                reuseCount += 1;
                            } else {
                                utils:logError(string `failed to restore operationId for ${method} ${path}: ${updateResult.message()}`);
                            }
                        }
                    }
                }
            }
        }
        if reuseCount > 0 {
            utils:logInfo(string `  ✓ reused ${reuseCount} operationId${reuseCount == 1 ? "" : "s"} from previous run`);
        }
    }

    // Collect all current operationIds (including those just restored in Pass A) as reserved names
    string[] existingOperationIds = [];
    collectExistingOperationIds(paths, existingOperationIds, priorOperationIds);

    // Pass B: AI improvement for operations not covered by Pass A
    OperationIdRequest[] requests = [];
    map<OperationLocation> requestToLocationMap = {};
    collectOperationIdRequests(paths, requests, requestToLocationMap, apiContext, priorOperationIds);

    int totalRequests = requests.length();
    int aiImproved = 0;
    if totalRequests == 0 {
        utils:logVerbose("no operations to improve with AI");
    } else {
        utils:logVerbose(string `collected ${totalRequests} operationId improvement request${totalRequests == 1 ? "" : "s"}`);

        int startIdx = 0;
        while startIdx < totalRequests {
            int endIdx = startIdx + BATCH_SIZE;
            if endIdx > totalRequests { endIdx = totalRequests; }
            OperationIdRequest[] batch = requests.slice(startIdx, endIdx);
            int batchNum = (startIdx / BATCH_SIZE) + 1;
            utils:logVerbose(string `processing operationId batch ${batchNum} (${batch.length()} operations)`);

            BatchOperationIdResponse[]|error batchResult = generateOperationIdsBatchWithRetry(batch, apiContext, existingOperationIds);
            if batchResult is BatchOperationIdResponse[] {
                utils:logVerbose(string `operationId batch ${batchNum} complete (${batchResult.length()} operations)`);
                foreach BatchOperationIdResponse response in batchResult {
                    OperationLocation? loc = requestToLocationMap[response.id];
                    if loc is OperationLocation {
                        error? updateResult = updateOperationIdInSpec(paths, loc.path, loc.method, response.operationId);
                        if updateResult is () {
                            existingOperationIds.push(response.operationId);
                            aiImproved += 1;
                        } else {
                            utils:logError(string `failed to apply operationId for ${response.id}: ${updateResult.message()}`);
                        }
                    }
                }
            } else {
                utils:logError(string `operationId batch ${batchNum} failed after all retries: ${batchResult.message()}`);
            }
            startIdx += BATCH_SIZE;
        }
    }

    // Uniqueness guard: warn on duplicate operationIds (client gen will also surface them)
    map<string[]> seenIds = {};
    string[] httpMethodsCheck = ["get", "post", "put", "delete", "patch", "head", "options", "trace"];
    foreach string path in paths.keys() {
        json|error pathItem = paths.get(path);
        if pathItem is map<json> {
            map<json> pathItemMap = <map<json>>pathItem;
            foreach string method in httpMethodsCheck {
                if pathItemMap.hasKey(method) {
                    json|error operationResult = pathItemMap.get(method);
                    if operationResult is map<json> {
                        map<json> operation = <map<json>>operationResult;
                        if operation.hasKey("operationId") {
                            json|error opIdResult = operation.get("operationId");
                            if opIdResult is string {
                                string opId = <string>opIdResult;
                                string[] locs = seenIds[opId] ?: [];
                                locs.push(string `${method.toUpperAscii()} ${path}`);
                                seenIds[opId] = locs;
                            }
                        }
                    }
                }
            }
        }
    }
    foreach string opId in seenIds.keys() {
        string[] locs = seenIds[opId] ?: [];
        if locs.length() > 1 {
            utils:logWarn(string `duplicate operationId "${opId}" at: ${string:'join(", ", ...locs)}`);
        }
    }

    string|error prettifiedResult = jsondata:prettify(specJson);
    if prettifiedResult is error {
        return error("Failed to prettify JSON", prettifiedResult);
    }
    error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
    if writeResult is error {
        return error("Failed to write updated OpenAPI spec", writeResult);
    }

    return aiImproved;
}
