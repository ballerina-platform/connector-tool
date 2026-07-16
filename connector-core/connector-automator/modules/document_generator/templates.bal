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

function ballerinaReadmeTemplate() returns string {
    return string `# {{CONNECTOR_NAME}} Connector

## Overview
{{AI_GENERATED_OVERVIEW}}

## Setup guide
{{AI_GENERATED_SETUP}}

## Quickstart
{{AI_GENERATED_QUICKSTART}}

## Examples
{{AI_GENERATED_EXAMPLES}}
`;
}

function testsReadmeTemplate() returns string {
    return string `{{AI_GENERATED_TESTING_APPROACH}}
`;
}

function exampleSpecificTemplate() returns string {
    return string `{{AI_GENERATED_INDIVIDUAL_README}}
`;
}

function examplesReadmeTemplate() returns string {
    return string `{{AI_GENERATED_MAIN_EXAMPLES_README}}
`;
}

function mainReadmeTemplate() returns string {
    return string `# {{CONNECTOR_NAME}}

{{AI_GENERATED_HEADER_AND_BADGES}}

## Overview
{{AI_GENERATED_OVERVIEW}}

## Setup guide
{{AI_GENERATED_SETUP}}

## Quickstart
{{AI_GENERATED_QUICKSTART}}

## Examples
{{AI_GENERATED_EXAMPLES}}

## Useful Links
{{AI_GENERATED_USEFUL_LINKS}}
`;
}
