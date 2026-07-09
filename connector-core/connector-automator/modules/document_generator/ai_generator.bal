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

import ballerina/ai;
import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/lang.'string as strings;
import wso2/connector_automator.utils;

public function generateAllDocumentation(string connectorPath) returns error? {
    check generateBallerinaReadme(connectorPath);
    check generateTestsReadme(connectorPath);
    check generateExamplesReadme(connectorPath);
    check generateIndividualExampleReadmes(connectorPath);
    check generateMainReadme(connectorPath);
    check generateKeywords(connectorPath);
}

public function generateBallerinaReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateBallerinaContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = substituteVariables(ballerinaReadmeTemplate(), data);

    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string outputPath = ballerinaDir + "/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    utils:logVerbose(string `written: ${outputPath}`);
}

public function generateTestsReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateTestsContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = substituteVariables(testsReadmeTemplate(), data);

    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string outputPath = ballerinaDir + "/tests/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    utils:logVerbose(string `written: ${outputPath}`);
}

public function generateIndividualExampleReadmes(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);

    string examplesPath = connectorPath + "/examples";

    if !check file:test(examplesPath, file:EXISTS) {
        utils:logVerbose("no examples directory found — skipping individual READMEs");
        return;
    }

    file:MetaData[] examples = check file:readDir(examplesPath);
    int exampleCount = 0;
    int successCount = 0;

    foreach file:MetaData example in examples {
        if example.dir {
            string exampleDirName = extractDirectoryName(example.absPath);
            if exampleDirName.startsWith(".") {
                continue;
            }
            string exampleDirPath = examplesPath + "/" + exampleDirName;

            error? result = generateSingleExampleReadme(example.absPath, exampleDirName, metadata);
            if result is error {
                utils:logWarn(string `failed to generate README for ${exampleDirName}: ${result.message()}`);
            } else {
                successCount += 1;
                utils:logVerbose(string `written: ${exampleDirPath}/README.md`);
            }
            exampleCount += 1;
        }
    }

    if exampleCount > 0 {
        utils:logVerbose(string `generated ${successCount}/${exampleCount} individual example READMEs`);
    }
}

function generateSingleExampleReadme(string examplePath, string exampleDirName, ConnectorMetadata metadata) returns error? {
    // Read all .bal files in the example directory
    ExampleData exampleData = check analyzeExampleDirectory(examplePath, exampleDirName);

    // Generate AI content for this specific example
    map<string> aiContent = check generateIndividualExampleContent(exampleData, metadata);

    // Create template data
    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    // Add example-specific data
    data.CONNECTOR_NAME = metadata.connectorName;

    string content = substituteVariables(exampleSpecificTemplate(), data);

    string readmeFileName = "README.md";
    string outputPath = examplePath + "/" + readmeFileName;

    check writeOutput(content, outputPath);
}

function generateIndividualExampleContent(ExampleData exampleData, ConnectorMetadata connectorMetadata) returns map<string>|error {
    map<string> content = {};
    string prompt = createIndividualExamplePrompt(exampleData, connectorMetadata);
    string result = check utils:callAI(prompt);

    content["individual_readme"] = result;
    return content;
}

public function generateExamplesReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateExamplesContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = substituteVariables(examplesReadmeTemplate(), data);

    string outputPath = connectorPath + "/examples/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    utils:logVerbose(string `written: ${outputPath}`);
}

public function generateMainReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateMainContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = substituteVariables(mainReadmeTemplate(), data);

    string outputPath = connectorPath + "/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    utils:logVerbose(string `written: ${outputPath}`);
}

function generateBallerinaContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};

    string overviewPrompt = createBallerinaOverviewPrompt(metadata);
    string overviewResult = check utils:callAI(overviewPrompt);
    content["overview"] = overviewResult;

    string setupPrompt = createBallerinaSetupPrompt(metadata);
    string setupResult = check utils:callAI(setupPrompt);
    content["setup"] = setupResult;

    string quickstartPrompt = createBallerinaQuickstartPrompt(metadata);
    string quickstartResult = check utils:callAI(quickstartPrompt);
    content["quickstart"] = quickstartResult;

    string examplesPrompt = createBallerinaExamplesPrompt(metadata);
    string examplesResult = check utils:callAI(examplesPrompt);
    content["examples"] = examplesResult;

    return content;
}

function generateTestsContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};
    string testsPrompt = createTestReadmePrompt(metadata);
    string testsResult = check utils:callAI(testsPrompt);
    content["testing_approach"] = testsResult;

    return content;
}

function generateExamplesContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};
    string mainExamplesPrompt = createMainExampleReadmePrompt(metadata);
    string mainExamplesResult = check utils:callAI(mainExamplesPrompt);
    content["main_examples_readme"] = mainExamplesResult;

    return content;
}

function generateMainContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};

    content["header_and_badges"] = createHeaderAndBadges(metadata);
    content["useful_links"] = createUsefulLinksSection(metadata);

    string overviewPrompt = createBallerinaOverviewPrompt(metadata);
    string overviewResult = check utils:callAI(overviewPrompt);
    content["overview"] = overviewResult;

    string setupPrompt = createBallerinaSetupPrompt(metadata);
    string setupResult = check utils:callAI(setupPrompt);
    content["setup"] = setupResult;

    string quickstartPrompt = createBallerinaQuickstartPrompt(metadata);
    string quickstartResult = check utils:callAI(quickstartPrompt);
    content["quickstart"] = quickstartResult;

    string examplesPrompt = createBallerinaExamplesPrompt(metadata);
    string examplesResult = check utils:callAI(examplesPrompt);
    content["examples"] = examplesResult;

    return content;
}

// Template processing functions
function substituteVariables(string template, TemplateData data) returns string {
    string result = template;

    // Simple string replacement function
    string connectorName = data.CONNECTOR_NAME ?: "";
    if connectorName != "" {
        result = simpleReplace(result, "{{CONNECTOR_NAME}}", connectorName);
    }

    string version = data.VERSION ?: "";
    if version != "" {
        result = simpleReplace(result, "{{VERSION}}", version);
    }

    string description = data.DESCRIPTION ?: "";
    if description != "" {
        result = simpleReplace(result, "{{DESCRIPTION}}", description);
    }

    string overview = data.AI_GENERATED_OVERVIEW ?: "";
    if overview != "" {
        result = simpleReplace(result, "{{AI_GENERATED_OVERVIEW}}", overview);
    }

    string setup = data.AI_GENERATED_SETUP ?: "";
    if setup != "" {
        result = simpleReplace(result, "{{AI_GENERATED_SETUP}}", setup);
    }

    string quickstart = data.AI_GENERATED_QUICKSTART ?: "";
    if quickstart != "" {
        result = simpleReplace(result, "{{AI_GENERATED_QUICKSTART}}", quickstart);
    }

    string examples = data.AI_GENERATED_EXAMPLES ?: "";
    if examples != "" {
        result = simpleReplace(result, "{{AI_GENERATED_EXAMPLES}}", examples);
    }

    string usage = data.AI_GENERATED_USAGE ?: "";
    if usage != "" {
        result = simpleReplace(result, "{{AI_GENERATED_USAGE}}", usage);
    }

    string testingApproach = data.AI_GENERATED_TESTING_APPROACH ?: "";
    if testingApproach != "" {
        result = simpleReplace(result, "{{AI_GENERATED_TESTING_APPROACH}}", testingApproach);
    }

    string exampleDescriptions = data.AI_GENERATED_EXAMPLE_DESCRIPTIONS ?: "";
    if exampleDescriptions != "" {
        result = simpleReplace(result, "{{AI_GENERATED_EXAMPLE_DESCRIPTIONS}}", exampleDescriptions);
    }

    string gettingStarted = data.AI_GENERATED_GETTING_STARTED ?: "";
    if gettingStarted != "" {
        result = simpleReplace(result, "{{AI_GENERATED_GETTING_STARTED}}", gettingStarted);
    }

    string headerAndBadges = data.AI_GENERATED_HEADER_AND_BADGES ?: "";
    if headerAndBadges != "" {
        result = simpleReplace(result, "{{AI_GENERATED_HEADER_AND_BADGES}}", headerAndBadges);
    }

    string usefulLinks = data.AI_GENERATED_USEFUL_LINKS ?: "";
    if usefulLinks != "" {
        result = simpleReplace(result, "{{AI_GENERATED_USEFUL_LINKS}}", usefulLinks);
    }

    string individualReadme = data.AI_GENERATED_INDIVIDUAL_README ?: "";
    if individualReadme != "" {
        result = simpleReplace(result, "{{AI_GENERATED_INDIVIDUAL_README}}", individualReadme);
    }

    string mainExamplesReadme = data.AI_GENERATED_MAIN_EXAMPLES_README ?: "";
    if mainExamplesReadme != "" {
        result = simpleReplace(result, "{{AI_GENERATED_MAIN_EXAMPLES_README}}", mainExamplesReadme);
    }

    return result;
}

function createTemplateData(ConnectorMetadata metadata) returns TemplateData {
    return {
        CONNECTOR_NAME: metadata.connectorName,
        VERSION: metadata.version
    };
}

public function generateKeywords(string connectorPath) returns error? {

    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    ai:Prompt prompt = createKeywordGenerationPrompt(metadata);

    ai:ModelProvider model = check utils:getAIModel();
    ConnectorKeywords kw = check model->generate(prompt);

    string[] keywords = [kw.cost, kw.vendor, kw.area, "Type/Connector"];
    check writeKeywordsToToml(connectorPath, keywords);

    utils:logInfo(string `✓ keywords written: ${keywords.toString()}`);
}

function writeKeywordsToToml(string connectorPath, string[] keywords) returns error? {
    string tomlPath = connectorPath + "/Ballerina.toml";
    if !check file:test(tomlPath, file:EXISTS) {
        tomlPath = connectorPath + "/ballerina/Ballerina.toml";
    }
    if !check file:test(tomlPath, file:EXISTS) {
        utils:logWarn("writeKeywordsToToml: Ballerina.toml not found — skipping");
        return;
    }

    string content = check io:fileReadString(tomlPath);

    // Serialise the keywords array to TOML format
    string[] quoted = from string kw in keywords select string `"${kw}"`;
    string keywordsLine = string `keywords = [${strings:'join(", ", ...quoted)}]`;

    string updated;
    if content.includes("keywords") {
        // Replace the existing keywords line
        string[] lines = regexp:split(re `\n`, content);
        string[] newLines = [];
        foreach string line in lines {
            if strings:trim(line).startsWith("keywords") {
                newLines.push(keywordsLine);
            } else {
                newLines.push(line);
            }
        }
        updated = strings:'join("\n", ...newLines);
    } else {
        // Insert after the version line
        string[] lines = regexp:split(re `\n`, content);
        string[] newLines = [];
        foreach string line in lines {
            newLines.push(line);
            if strings:trim(line).startsWith("version") {
                newLines.push(keywordsLine);
            }
        }
        updated = strings:'join("\n", ...newLines);
    }

    check io:fileWriteString(tomlPath, updated);
}

function mergeAIContent(TemplateData baseData, map<string> aiContent) returns TemplateData {
    TemplateData merged = baseData.clone();

    foreach var [key, value] in aiContent.entries() {
        match key {
            "overview" => {
                merged.AI_GENERATED_OVERVIEW = value;
            }
            "setup" => {
                merged.AI_GENERATED_SETUP = value;
            }
            "quickstart" => {
                merged.AI_GENERATED_QUICKSTART = value;
            }
            "examples" => {
                merged.AI_GENERATED_EXAMPLES = value;
            }
            "usage" => {
                merged.AI_GENERATED_USAGE = value;
            }
            "testing_approach" => {
                merged.AI_GENERATED_TESTING_APPROACH = value;
            }
            "test_scenarios" => {
                merged.AI_GENERATED_TEST_SCENARIOS = value;
            }
            "example_descriptions" => {
                merged.AI_GENERATED_EXAMPLE_DESCRIPTIONS = value;
            }
            "getting_started" => {
                merged.AI_GENERATED_GETTING_STARTED = value;
            }
            "header_and_badges" => {
                merged.AI_GENERATED_HEADER_AND_BADGES = value;
            }
            "useful_links" => {
                merged.AI_GENERATED_USEFUL_LINKS = value;
            }
            "individual_readme" => {
                merged.AI_GENERATED_INDIVIDUAL_README = value;
            }
            "main_examples_readme" => {
                merged.AI_GENERATED_MAIN_EXAMPLES_README = value;
            }
        }
    }

    return merged;
}
