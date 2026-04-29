import ballerina/io;

# Inject a connector entry into the Docusaurus sidebars.ts file under the
# "Connector Catalog" category, in alphabetical order.
#
# + sidebarPath  - Absolute path to sidebars.ts
# + name         - Connector display name, e.g. "HubSpot"
# + module       - Module slug, e.g. "hubspot"
# + categorySlug - Category slug, e.g. "crm-sales"
# + hasSetup     - Whether a setup-guide.md was generated
# + hasTriggers  - Whether a trigger-reference.md was generated
# + return       - nil on success, or an error
public function injectConnector(
    string sidebarPath,
    string name,
    string module,
    string categorySlug,
    boolean hasSetup,
    boolean hasTriggers
) returns error? {
    string|io:Error fileResult = io:fileReadString(sidebarPath);
    if fileResult is io:Error {
        return error(string `Sidebar file not found: ${sidebarPath}`);
    }
    string text = <string>fileResult;

    // Guard: already present
    if text.includes(string `/${module}/overview`) {
        return error(string `Connector '${module}' already exists in sidebar`);
    }

    // Build the connector sidebar block
    string basePath = string `connectors/catalog/${categorySlug}/${module}`;
    string items = "";
    if hasSetup {
        items += string `            '${basePath}/setup-guide',` + "\n";
    }
    items += string `            '${basePath}/action-reference',` + "\n";
    if hasTriggers {
        items += string `            '${basePath}/trigger-reference',` + "\n";
    }

    string connectorBlock = string `        {
          type: 'category',
          label: '${name}',
          link: { type: 'doc', id: '${basePath}/overview' },
          items: [
${items}          ],
        },`;

    // Find "Connector Catalog" label
    string searchLabel = "Connector Catalog";
    int? labelPos = text.indexOf(string `label: '${searchLabel}'`);
    if labelPos is () {
        // Try with double quotes
        labelPos = text.indexOf(string `label: "${searchLabel}"`);
    }
    if labelPos is () {
        return error(string `'${searchLabel}' not found in ${sidebarPath}`);
    }

    // Find items: [ after the label
    int? itemsPos = text.indexOf("items: [", labelPos);
    if itemsPos is () {
        return error(string `Could not find items array for '${searchLabel}'`);
    }
    int itemsStart = itemsPos + "items: [".length();

    // Count brackets to find the matching closing "]"
    int closingBracketPos = findClosingBracket(text, itemsStart);
    if closingBracketPos < 0 {
        return error(string `Could not find closing bracket for '${searchLabel}' items`);
    }

    // Find all existing connector labels in this items block for alphabetical ordering
    string itemsText = text.substring(itemsStart, closingBracketPos);
    int insertPos = findAlphabeticalInsertPos(itemsText, itemsStart, closingBracketPos, name, text);

    string newText;
    if insertPos == closingBracketPos {
        // Append at end of items list
        newText = text.substring(0, insertPos) + "\n" + connectorBlock + "\n" + text.substring(insertPos);
    } else {
        // Insert before an existing entry
        newText = text.substring(0, insertPos) + connectorBlock + "\n" + text.substring(insertPos);
    }

    io:Error? writeErr = io:fileWriteString(sidebarPath, newText);
    if writeErr is io:Error {
        return error("Failed to write sidebar: " + writeErr.message());
    }
}

// Find the position of the closing "]" by counting bracket depth.
// Returns -1 if not found.
function findClosingBracket(string text, int startPos) returns int {
    int depth = 1;
    int pos = startPos;
    while pos < text.length() && depth > 0 {
        string ch = text.substring(pos, pos + 1);
        if ch == "[" {
            depth += 1;
        } else if ch == "]" {
            depth -= 1;
        }
        pos += 1;
    }
    if depth != 0 {
        return -1;
    }
    return pos - 1;
}

// Find the alphabetical insertion position within the items text.
// Returns closingBracketPos to append at end if no later entry is found.
function findAlphabeticalInsertPos(
    string itemsText,
    int itemsStart,
    int closingBracketPos,
    string newName,
    string fullText
) returns int {
    string nameLower = newName.toLowerAscii();

    // Collect existing label strings
    string remaining = itemsText;
    int baseOffset = itemsStart;
    string labelPrefix = "label: '";

    while remaining.length() > 0 {
        int? lpos = remaining.indexOf(labelPrefix);
        if lpos is () {
            break;
        }
        int labelStart = lpos + labelPrefix.length();
        int? labelEnd = remaining.indexOf("'", labelStart);
        if labelEnd is () {
            break;
        }
        string existingLabel = remaining.substring(labelStart, labelEnd);

        if nameLower < existingLabel.toLowerAscii() {
            // Insert before this connector's opening brace
            // Search backwards from the label position for the opening "{"
            string beforeLabel = fullText.substring(0, baseOffset + lpos);
            int? bracePos = lastIndexOf(beforeLabel, "        {");
            if bracePos is int {
                return bracePos;
            }
        }

        remaining = remaining.substring(labelEnd + 1);
        baseOffset += labelEnd + 1;
    }

    // Append at end
    return closingBracketPos;
}

// Find the last occurrence of searchStr in text. Returns () if not found.
function lastIndexOf(string text, string searchStr) returns int? {
    int? lastFound = ();
    int searchFrom = 0;
    while searchFrom <= text.length() - searchStr.length() {
        int? pos = text.indexOf(searchStr, searchFrom);
        if pos is () {
            break;
        }
        lastFound = pos;
        searchFrom = pos + 1;
    }
    return lastFound;
}
