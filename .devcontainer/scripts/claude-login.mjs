import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const realClaude = process.argv[2];
const extraArgs = process.argv.slice(3);

if (!realClaude) {
  console.error("Usage: node .devcontainer/scripts/claude-login.mjs <real-claude-binary> [additional args]");
  process.exit(1);
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const bridgeScript = path.join(__dirname, "claude-ipv4-bridge.mjs");

let bridgeStartedForPort = null;
let stdoutBuffer = "";
let stderrBuffer = "";

function tryExtractPort(text) {
  const patterns = [
    /redirect_uri=http:\/\/localhost:(\d+)\/callback/gi,
    /redirect_uri=http%3A%2F%2Flocalhost%3A(\d+)%2Fcallback/gi,
    /http:\/\/localhost:(\d+)\/callback/gi,
    /http:\/\/localhost:(\d+)\/success/gi
  ];

  for (const pattern of patterns) {
    let match;
    while ((match = pattern.exec(text)) !== null) {
      const port = Number(match[1]);
      if (Number.isInteger(port) && port > 0 && port < 65536) {
        return port;
      }
    }
  }
  return null;
}

function maybeStartBridge(port) {
  if (!port || bridgeStartedForPort === port) {
    return;
  }

  bridgeStartedForPort = port;
  process.stderr.write(`[claude-login] Starte automatische IPv4->IPv6 Bridge auf Port ${port}\n`);

  const bridge = spawn(process.execPath, [bridgeScript, String(port)], {
    stdio: "inherit",
    detached: false
  });

  bridge.on("error", (err) => {
    process.stderr.write(`[claude-login] Bridge-Fehler: ${err.message}\n`);
  });
}

function inspectChunk(chunk, streamName) {
  const text = chunk.toString();
  if (streamName === "stdout") {
    stdoutBuffer += text;
    if (stdoutBuffer.length > 12000) stdoutBuffer = stdoutBuffer.slice(-12000);
  } else {
    stderrBuffer += text;
    if (stderrBuffer.length > 12000) stderrBuffer = stderrBuffer.slice(-12000);
  }

  const port = tryExtractPort(text) || tryExtractPort(stdoutBuffer) || tryExtractPort(stderrBuffer);
  if (port) {
    maybeStartBridge(port);
  }
}

const args = ["auth", "login", ...extraArgs];

process.stderr.write(`[claude-login] Starte: ${realClaude} ${args.join(" ")}\n`);

const child = spawn(realClaude, args, {
  stdio: ["inherit", "pipe", "pipe"],
  env: process.env
});

child.stdout.on("data", (chunk) => {
  process.stdout.write(chunk);
  inspectChunk(chunk, "stdout");
});

child.stderr.on("data", (chunk) => {
  process.stderr.write(chunk);
  inspectChunk(chunk, "stderr");
});

child.on("error", (err) => {
  process.stderr.write(`[claude-login] Fehler beim Start von Claude: ${err.message}\n`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.stderr.write(`[claude-login] Claude beendet durch Signal ${signal}\n`);
    process.exit(1);
  }
  process.exit(code ?? 0);
});