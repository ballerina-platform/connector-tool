import ballerina/io;
import ballerina/time;

public const OUTPUT_DIR = "./artifacts/execution-prompt";

# Saves the execution prompt content to a Markdown file in the output directory.
# The filename includes the goal slug and a timestamp.
#
# + content  - the full execution prompt content
# + goalSlug - a short hyphenated slug derived from the goal
# + return   - the absolute file path on success, or an error
public function saveExecutionPrompt(string content, string goalSlug) returns string|error {
    // Ensure output directory exists
    check io:fileWriteString(OUTPUT_DIR + "/.keep", "");

    // Generate filename with short goal + timestamp
    time:Utc now = time:utcNow();
    time:Civil civil = time:utcToCivil(now);
    string timestamp = string `${civil.year}-${civil.month < 10 ? "0" : ""}${civil.month}-${civil.day < 10 ? "0" : ""}${civil.day}_${civil.hour < 10 ? "0" : ""}${civil.hour}-${civil.minute < 10 ? "0" : ""}${civil.minute}-${civil.second < 10d ? "0" : ""}${civil.second.toString()}`;
    string filename = string `${goalSlug}_execution_prompt_${timestamp}.md`;
    string filePath = OUTPUT_DIR + "/" + filename;

    // Write the execution prompt to file
    check io:fileWriteString(filePath, content);
    return filePath;
}
