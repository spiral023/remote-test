import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const defaultHomeDir = process.env.HOME ?? "/home/node";
const defaultTheme = "dark";

function readJsonFile(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function writeJsonFile(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

function detectClaudeVersion() {
  const candidates = [
    "/usr/local/share/npm-global/lib/node_modules/@anthropic-ai/claude-code/package.json",
    "/usr/local/lib/node_modules/@anthropic-ai/claude-code/package.json",
    path.join(__dirname, "..", "..", "node_modules", "@anthropic-ai", "claude-code", "package.json"),
  ];

  for (const candidate of candidates) {
    const pkg = readJsonFile(candidate);
    if (pkg?.version) {
      return pkg.version;
    }
  }

  return null;
}

function hasClaudeAuth(rootConfig, credentials) {
  return Boolean(
    rootConfig?.oauthAccount?.accountUuid ||
      rootConfig?.oauthAccount?.emailAddress ||
      credentials?.claudeAiOauth?.accessToken,
  );
}

export function getClaudeConfigPaths(homeDir = defaultHomeDir) {
  return {
    credentialsPath: path.join(homeDir, ".claude", ".credentials.json"),
    rootConfigPath: path.join(homeDir, ".claude.json"),
  };
}

export function ensureClaudeRuntimeState(homeDir = defaultHomeDir) {
  const { credentialsPath, rootConfigPath } = getClaudeConfigPaths(homeDir);
  const rootConfig = readJsonFile(rootConfigPath) ?? {};
  const credentials = readJsonFile(credentialsPath) ?? {};

  if (!hasClaudeAuth(rootConfig, credentials)) {
    return { changed: false, reason: "no-auth" };
  }

  let changed = false;

  if (!rootConfig.theme) {
    rootConfig.theme = defaultTheme;
    changed = true;
  }

  if (rootConfig.hasCompletedOnboarding !== true) {
    rootConfig.hasCompletedOnboarding = true;
    changed = true;
  }

  const version = detectClaudeVersion();
  if (version && !rootConfig.lastOnboardingVersion) {
    rootConfig.lastOnboardingVersion = version;
    changed = true;
  }

  if (!changed) {
    return { changed: false, reason: "up-to-date", config: rootConfig };
  }

  writeJsonFile(rootConfigPath, rootConfig);
  return { changed: true, reason: "updated", config: rootConfig };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const result = ensureClaudeRuntimeState();
  if (process.argv.includes("--verbose")) {
    process.stdout.write(`${JSON.stringify(result)}\n`);
  }
}
