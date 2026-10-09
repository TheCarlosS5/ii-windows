"""AI chat through ii-shim's streaming WinHTTP transport (exact-match staged-tree edits)."""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit  # noqa: E402

# Require an explicit stage; never patch the running build/ii tree by accident.
ROOT = os.environ['II_STAGE_DIR']


def path(*parts):
    return os.path.join(ROOT, *parts)


edit(path('services', 'Ai.qml'), [
    # StandardPaths (temp folder for the request file) lives in QtCore.
    ('import QtQuick\nimport qs.services.ai\n', 'import QtQuick\nimport QtCore\nimport qs.services.ai\n'),
    ('    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"\n',
     '    property string requestScriptFilePath: `${CF.FileUtils.trimFileProtocol(StandardPaths.writableLocation(StandardPaths.TempLocation))}/quickshell/ai/request.sh`\n'),
    ('''    FileView {
        id: requesterScriptFile
    }
''',
     '''    FileView {
        id: requesterScriptFile
        blockWrites: true // ii-windows: finish writing JSON before the process reads it
        blockAllReads: true // verify fresh disk contents, including failed atomic commits
    }
'''),
    ('        property list<string> baseCommand: ["bash"]\n', ''),
    ('''        function makeRequest() {
            const model = models[currentModelId];
''',
     '''        function makeRequest() {
            // ii-windows: attachment uploads still need the upstream bash setup.
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                root.addMessage(Translation.tr("File attachments are not supported on Windows yet. The attachment was cleared; send your message again without it."), Ai.interfaceRole);
                root.pendingFilePath = "";
                return;
            }
            const model = models[currentModelId];
'''),
    ('''            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
''',
     r'''            let requestHeaders = {
                "Content-Type": "application/json",
            }

            // Strategies return curl's -H "Name: value" (or single quotes).
            // Keep the environment placeholder literal in the JSON file.
            const authHeader = model.requires_key ? requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName) : "";
            if (authHeader) {
                const authMatch = /^-H\s+(["'])([^:]+):\s*(.*?)\1$/.exec(authHeader.trim());
                if (!authMatch) {
                    root.addMessage(Translation.tr("Unsupported AI authorization header format."), Ai.interfaceRole);
                    return;
                }
                requestHeaders[authMatch[2].trim()] = authMatch[3];
            }

            /* Create local message object */
'''),
    ('''            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

''', ''),
    (r'''            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
''',
     r'''            /* Send the request through the Windows streaming transport. */
            const requestPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath).replace(/\.sh$/, "") + "." + Quickshell.instanceId + ".json";
            const requestContent = JSON.stringify({
                "url": endpoint,
                "headers": requestHeaders,
                "body": JSON.stringify(data),
            });
            requesterScriptFile.path = Qt.resolvedUrl(requestPath);
            requesterScriptFile.setText(requestContent);
            requesterScriptFile.reload();
            if (requesterScriptFile.text() !== requestContent) {
                root.addMessage(Translation.tr("Could not save the AI request. Check free disk space and permissions, then send your message again."), Ai.interfaceRole);
                return;
            }

            /* Create local message object only after the request is ready. */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            requester.command = ["ii-shim", "ai-request", requestPath];
            requester.running = true;
'''),
])
