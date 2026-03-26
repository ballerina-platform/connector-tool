
# Builds the user message containing only the dynamic/variable parts:
# goal, code-server URL, and absolute artifact paths. All rules, template
# structure, and formatting instructions live in system_prompt.bal.
#
# + userGoal      - The goal definition
# + codeServerUrl - The URL where code-server is running
# + projectRoot   - Absolute path to the project root directory
# + return - the user message string
public function buildUserMessage(string userGoal, string codeServerUrl, string projectRoot) returns string {
    string screenshotsDir = projectRoot + "/artifacts/screenshots";
    string workflowDocsDir = projectRoot + "/artifacts/workflow-docs";
    return string `Generate a highly detailed execution prompt for the following goal.

THE MAIN GOAL (this must be the central focus of the ENTIRE execution prompt):
${userGoal}

Make sure the goal above is clearly reflected in:
- The prompt TITLE (name the goal explicitly)
- The OVERVIEW section (first sentence must state the goal)
- The OBJECTIVES (list goal-specific implementation objectives)
- The IMPLEMENTATION STAGES (Stage 5+ must break down this exact goal into detailed, actionable steps with specific UI element names, fields to fill, buttons to click)
- The DELIVERABLES (filename should reflect the goal)
- The SUCCESS CRITERIA (what does achieving THIS goal look like?)

CODE-SERVER URL: ${codeServerUrl}
(Use this exact URL in Stage 1 when navigating to the code-server instance)

Screenshots directory: ${screenshotsDir}
Workflow docs directory: ${workflowDocsDir}
IMPORTANT: Use these ABSOLUTE paths when specifying filenames for browser_take_screenshot and when writing workflow documentation. Do NOT use relative paths.`;
}
