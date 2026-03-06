import fs from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ensureClaudeRuntimeState } from "./claude-config.mjs";

const rawArgs = process.argv.slice(2);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const bridgeScript = path.join(__dirname, "claude-ipv4-bridge.mjs");
const homeDir = process.env.HOME ?? "/home/node";
const wrapperPaths = new Set([
  path.join(homeDir, ".local", "agent-bin", "claude"),
  path.join(homeDir, ".local", "bin", "claude"),
]);
const watchIntervalMs = 250;
const maxWatchIterations = 80;

let bridgeStartedForPort = null;
let stdoutBuffer = "";
let stderrBuffer = "";
let watcherCancelled = false;

let autoStartClaude = process.env.CLAUDE_LOGIN_NO_START !== "1";
const extraArgs = [];

for (const arg of rawArgs) {
  if (arg === "--login-only") {
    autoStartClaude = false;
    continue;
  }
  extraArgs.push(arg);
}

function isExecutable(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function resolveClaudeBinary() {
  const pathEntries = (process.env.PATH ?? "").split(":").filter(Boolean);
  for (const entry of pathEntries) {
    const candidate = path.join(entry, "claude");
    if (wrapperPaths.has(candidate)) continue;
    if (isExecutable(candidate)) {
      return candidate;
    }
  }
  return null;
}

function resolveClaudeLauncher() {
  for (const candidate of [
    path.join(homeDir, ".local", "bin", "claude"),
    path.join(homeDir, ".local", "agent-bin", "claude"),
  ]) {
    if (isExecutable(candidate)) {
      return candidate;
    }
  }

  return resolveClaudeBinary();
}

function claudeRootConfigPath() {
  return path.join(homeDir, ".claude.json");
}

function claudePersistRootConfigPath() {
  return path.join(homeDir, ".persist", "claude", ".claude.json");
}

function syncFileIfNewer(source, target) {
  try {
    if (!fs.existsSync(source)) {
      return;
    }

    fs.mkdirSync(path.dirname(target), { recursive: true });
    if (!fs.existsSync(target)) {
      fs.copyFileSync(source, target);
      return;
    }

    const sourceStat = fs.statSync(source);
    const targetStat = fs.statSync(target);
    if (sourceStat.mtimeMs > targetStat.mtimeMs) {
      fs.copyFileSync(source, target);
    }
  } catch (err) {
    process.stderr.write(`[claude-login] Warnung: Claude-Root-Config konnte nicht synchronisiert werden: ${err.message}\n`);
  }
}

function restoreClaudeRootConfig() {
  syncFileIfNewer(claudePersistRootConfigPath(), claudeRootConfigPath());
}

function persistClaudeRootConfig() {
  syncFileIfNewer(claudeRootConfigPath(), claudePersistRootConfigPath());
}

function ensureClaudeOnboardingState() {
  try {
    ensureClaudeRuntimeState(homeDir);
  } catch (err) {
    process.stderr.write(`[claude-login] Warnung: Claude-Onboarding-Status konnte nicht aktualisiert werden: ${err.message}\n`);
  }
}

function tryExtractPort(text) {
  const patterns = [
    /redirect_uri=http:\/\/localhost:(\d+)\/callback/gi,
    /redirect_uri=http%3A%2F%2Flocalhost%3A(\d+)%2Fcallback/gi,
    /http:\/\/localhost:(\d+)\/callback/gi,
    /http:\/\/localhost:(\d+)\/success/gi,
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

function withIpv4FirstNodeOptions(env) {
  const current = env.NODE_OPTIONS ?? "";
  if (/(^|\s)--dns-result-order=/.test(current)) {
    return env;
  }

  const nextValue = current.trim()
    ? `--dns-result-order=ipv4first ${current.trim()}`
    : "--dns-result-order=ipv4first";

  return {
    ...env,
    NODE_OPTIONS: nextValue,
  };
}

function parseSocketInode(linkTarget) {
  const match = /^socket:\[(\d+)\]$/.exec(linkTarget);
  return match ? match[1] : null;
}

function reverseBytePairs(hex) {
  return hex.match(/../g)?.reverse().join("") ?? "";
}

function normalizeProcAddress(hex, family) {
  if (family === 4) {
    return reverseBytePairs(hex);
  }

  const groups = hex.match(/.{8}/g) ?? [];
  return groups.map(reverseBytePairs).join("");
}

function classifyListenerHost(hex, family) {
  const normalized = normalizeProcAddress(hex, family);
  if (family === 4 && normalized === "7F000001") {
    return "127.0.0.1";
  }

  if (family === 6) {
    if (normalized === "00000000000000000000000000000001") {
      return "::1";
    }
    if (normalized === "00000000000000000000FFFF7F000001") {
      return "::ffff:127.0.0.1";
    }
  }

  return null;
}

function readListenerTable(procFile, family) {
  try {
    const content = fs.readFileSync(procFile, "utf8");
    const lines = content.trim().split("\n").slice(1);
    const listeners = [];

    for (const line of lines) {
      const parts = line.trim().split(/\s+/);
      if (parts.length < 10 || parts[3] !== "0A") continue;

      const [localAddress, portHex] = parts[1].split(":");
      const port = Number.parseInt(portHex, 16);
      const host = classifyListenerHost(localAddress, family);
      if (!host || !Number.isInteger(port) || port < 1 || port > 65535) continue;

      listeners.push({
        family,
        host,
        inode: parts[9],
        port,
      });
    }

    return listeners;
  } catch {
    return [];
  }
}

function getOwnedSocketInodes(pid) {
  const fdDir = `/proc/${pid}/fd`;
  try {
    const entries = fs.readdirSync(fdDir);
    const inodes = new Set();

    for (const entry of entries) {
      try {
        const target = fs.readlinkSync(path.join(fdDir, entry));
        const inode = parseSocketInode(target);
        if (inode) inodes.add(inode);
      } catch {
        // Ignore fds that disappear while we inspect the process.
      }
    }

    return inodes;
  } catch {
    return new Set();
  }
}

function detectLoopbackListener(pid, expectedPort = null) {
  const ownedInodes = getOwnedSocketInodes(pid);
  if (ownedInodes.size === 0) {
    return null;
  }

  const candidates = [
    ...readListenerTable("/proc/net/tcp6", 6),
    ...readListenerTable("/proc/net/tcp", 4),
  ].filter((listener) => {
    if (!ownedInodes.has(listener.inode)) return false;
    if (expectedPort !== null && listener.port !== expectedPort) return false;
    return true;
  });

  const preferredHosts = ["::1", "::ffff:127.0.0.1", "127.0.0.1"];
  candidates.sort((left, right) => {
    const hostDelta = preferredHosts.indexOf(left.host) - preferredHosts.indexOf(right.host);
    if (hostDelta !== 0) return hostDelta;
    return left.port - right.port;
  });

  return candidates[0] ?? null;
}

function maybeStartBridge(port, source) {
  if (!port || bridgeStartedForPort === port) {
    return;
  }

  bridgeStartedForPort = port;
  process.stderr.write(`[claude-login] Starte automatische IPv4->IPv6 Bridge auf Port ${port} (${source})\n`);

  const bridge = spawn(process.execPath, [bridgeScript, String(port)], {
    stdio: "inherit",
    detached: false,
  });

  bridge.on("error", (err) => {
    process.stderr.write(`[claude-login] Bridge-Fehler: ${err.message}\n`);
  });
}

function handleDetectedListener(listener, source) {
  if (!listener) return false;

  if (listener.host === "127.0.0.1") {
    process.stderr.write(
      `[claude-login] OAuth-Callback-Port ${listener.port} erkannt (${source}, IPv4 ${listener.host}); keine Bridge nötig\n`,
    );
    return true;
  }

  if (listener.host === "::1" || listener.host === "::ffff:127.0.0.1") {
    maybeStartBridge(listener.port, `${source}, ${listener.host}`);
    return true;
  }

  return false;
}

function startLoopbackWatcher(pid) {
  if (!pid) return () => {};

  let iterations = 0;
  let timeoutId = null;

  const tick = () => {
    if (watcherCancelled) return;
    iterations += 1;

    const listener = detectLoopbackListener(pid);
    if (handleDetectedListener(listener, "socket-detect")) {
      return;
    }

    if (iterations >= maxWatchIterations) {
      process.stderr.write("[claude-login] Kein OAuth-Callback-Port per Socket-Detection gefunden\n");
      return;
    }

    timeoutId = setTimeout(tick, watchIntervalMs);
    timeoutId.unref?.();
  };

  timeoutId = setTimeout(tick, watchIntervalMs);
  timeoutId.unref?.();

  return () => {
    watcherCancelled = true;
    if (timeoutId) clearTimeout(timeoutId);
  };
}

function inspectPortHint(port, pid, source) {
  const listener = detectLoopbackListener(pid, port);
  if (handleDetectedListener(listener, source)) {
    return;
  }

  process.stderr.write(
    `[claude-login] OAuth-Callback-Port ${port} erkannt (${source}), Listener-Familie noch unbekannt\n`,
  );
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
    inspectPortHint(port, child.pid, "stdout-regex");
  }
}

const realClaude = resolveClaudeBinary();
if (!realClaude) {
  process.stderr.write("[claude-login] Claude-Binary nicht gefunden. Prüfe die Feature-Installation.\n");
  process.exit(1);
}

const args = ["auth", "login", ...extraArgs];
process.stderr.write(`[claude-login] Starte: ${realClaude} ${args.join(" ")}\n`);
process.stderr.write("[claude-login] Erzwinge fuer Claude-Login IPv4-first DNS-Reihenfolge\n");

const childEnv = withIpv4FirstNodeOptions(process.env);
restoreClaudeRootConfig();
ensureClaudeOnboardingState();

const child = spawn(realClaude, args, {
  stdio: ["inherit", "pipe", "pipe"],
  env: childEnv,
});
const stopWatcher = startLoopbackWatcher(child.pid);

child.stdout.on("data", (chunk) => {
  process.stdout.write(chunk);
  inspectChunk(chunk, "stdout");
});

child.stderr.on("data", (chunk) => {
  process.stderr.write(chunk);
  inspectChunk(chunk, "stderr");
});

child.on("error", (err) => {
  stopWatcher();
  ensureClaudeOnboardingState();
  persistClaudeRootConfig();
  process.stderr.write(`[claude-login] Fehler beim Start von Claude: ${err.message}\n`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  stopWatcher();
  ensureClaudeOnboardingState();
  persistClaudeRootConfig();
  if (signal) {
    process.stderr.write(`[claude-login] Claude beendet durch Signal ${signal}\n`);
    process.exit(1);
  }

  const shouldAutoLaunch =
    (code ?? 0) === 0 &&
    autoStartClaude &&
    !extraArgs.includes("--help") &&
    !extraArgs.includes("-h");

  if (shouldAutoLaunch) {
    const launcher = resolveClaudeLauncher();
    if (!launcher) {
      process.stderr.write("[claude-login] Login erfolgreich, aber Claude-Launcher wurde nicht gefunden\n");
      process.exit(1);
    }

    process.stderr.write(`[claude-login] Login erfolgreich. Starte jetzt: ${launcher}\n`);
    const next = spawn(launcher, {
      stdio: "inherit",
      env: process.env,
    });

    next.on("error", (err) => {
      process.stderr.write(`[claude-login] Fehler beim Start von Claude: ${err.message}\n`);
      process.exit(1);
    });

    next.on("exit", (nextCode, nextSignal) => {
      if (nextSignal) {
        process.stderr.write(`[claude-login] Claude beendet durch Signal ${nextSignal}\n`);
        process.exit(1);
      }
      process.exit(nextCode ?? 0);
    });
    return;
  }

  process.exit(code ?? 0);
});
