#!/usr/bin/env node
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const configPath = join(process.env.HOME || ".", ".codex/config.toml");
const authPath = join(process.env.HOME || ".", ".codex/auth.json");
const backupDir = join(process.env.HOME || ".", ".codexplus/backups");
const logPath = join(process.env.HOME || ".", ".codexplus/config-importer.log");

mkdirSync(dirname(logPath), { recursive: true });
mkdirSync(backupDir, { recursive: true });

function log(message, detail = {}) {
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    message,
    ...detail,
  });
  appendFileSync(logPath, `${line}\n`);
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function decodePayload(encoded) {
  return JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
}

function validateIdentifier(value, fieldName) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error(`${fieldName} 只能包含字母、数字、下划线或短横线`);
  }
}

function validateConfigPayload(payload) {
  validateIdentifier(payload.providerId, "provider_id");
  validateIdentifier(payload.profileId, "profile_id");
  const authMode = payload.authMode === "env_key" ? "env_key" : "desktop_auth";
  if (typeof payload.providerName !== "string" || payload.providerName.trim().length === 0) {
    payload.providerName = payload.providerId;
  }
  if (typeof payload.baseUrl !== "string" || payload.baseUrl.trim().length === 0) {
    throw new Error("base_url 不能为空");
  }
  try {
    const url = new URL(payload.baseUrl);
    if (!/^https?:$/.test(url.protocol)) throw new Error("invalid");
  } catch {
    throw new Error("base_url 不是合法 URL");
  }
  if (authMode === "env_key") {
    if (typeof payload.apiKeyEnv !== "string" || !/^[A-Z][A-Z0-9_]*$/.test(payload.apiKeyEnv)) {
      throw new Error("api_key env 名必须像 OPENROUTER_API_KEY 这样的大写环境变量");
    }
  } else if (typeof payload.apiKeyValue !== "string" || payload.apiKeyValue.trim().length === 0) {
    throw new Error("API Key 不能为空");
  }
  if (typeof payload.model !== "string" || payload.model.trim().length === 0) {
    throw new Error("model 不能为空");
  }
  if (payload.httpHeaders && typeof payload.httpHeaders !== "object") {
    throw new Error("http_headers 必须是 JSON 对象");
  }
  const headers = {};
  for (const [key, value] of Object.entries(payload.httpHeaders || {})) {
    if (typeof key !== "string" || key.trim().length === 0) {
      throw new Error("http_headers 的 key 不能为空");
    }
    if (typeof value !== "string") {
      throw new Error(`http_headers["${key}"] 必须是字符串`);
    }
    headers[key] = value;
  }
  return {
    providerId: payload.providerId,
    providerName: payload.providerName.trim(),
    baseUrl: payload.baseUrl.trim(),
    authMode,
    apiKeyEnv: typeof payload.apiKeyEnv === "string" ? payload.apiKeyEnv.trim() : "",
    apiKeyValue: typeof payload.apiKeyValue === "string" ? payload.apiKeyValue.trim() : "",
    model: payload.model.trim(),
    profileId: payload.profileId,
    modelReasoningEffort: typeof payload.modelReasoningEffort === "string" && payload.modelReasoningEffort.trim()
      ? payload.modelReasoningEffort.trim()
      : "high",
    httpHeaders: headers,
  };
}

function tomlString(value) {
  return JSON.stringify(String(value));
}

function tomlInlineTable(entries) {
  const pairs = Object.entries(entries);
  if (!pairs.length) return "{}";
  return `{ ${pairs.map(([key, value]) => `${tomlString(key)} = ${tomlString(value)}`).join(", ")} }`;
}

function renderProviderSection(payload) {
  const lines = [
    `[model_providers.${payload.providerId}]`,
    `name = ${tomlString(payload.providerName)}`,
    `base_url = ${tomlString(payload.baseUrl)}`,
    `wire_api = "responses"`,
  ];
  if (payload.authMode === "env_key") {
    lines.splice(3, 0, `env_key = ${tomlString(payload.apiKeyEnv)}`);
  } else {
    lines.push("requires_openai_auth = true");
  }
  if (Object.keys(payload.httpHeaders).length) {
    lines.push(`http_headers = ${tomlInlineTable(payload.httpHeaders)}`);
  }
  return `${lines.join("\n")}\n`;
}

function renderProfileSection(payload) {
  return [
    `[profiles.${payload.profileId}]`,
    `model_provider = ${tomlString(payload.providerId)}`,
    `model = ${tomlString(payload.model)}`,
    `model_reasoning_effort = ${tomlString(payload.modelReasoningEffort)}`,
    "",
  ].join("\n");
}

function upsertTopLevelSection(text, header, sectionText) {
  const lines = text.split(/\r?\n/);
  const targetHeader = `[${header}]`;
  let start = -1;
  let end = lines.length;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (line === targetHeader) {
      start = index;
      continue;
    }
    if (start !== -1 && /^\[[^\]]+\]\s*$/.test(line)) {
      end = index;
      break;
    }
  }

  const nextLines = [...lines];
  if (start !== -1) {
    nextLines.splice(start, end - start);
  }

  let normalized = nextLines.join("\n").trimEnd();
  if (normalized.length) normalized += "\n\n";
  normalized += sectionText.trimEnd();
  normalized += "\n";
  return normalized;
}

function backupFile(prefix, text, extension) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = join(backupDir, `${prefix}-${stamp}.${extension}`);
  appendFileSync(backupPath, text);
  return backupPath;
}

function readConfigText() {
  try {
    return readFileSync(configPath, "utf8");
  } catch {
    return "";
  }
}

function readAuthJson() {
  try {
    return JSON.parse(readFileSync(authPath, "utf8"));
  } catch {
    return {};
  }
}

function writeConfigText(text) {
  writeFileSync(configPath, text, "utf8");
}

function writeAuthJson(auth) {
  writeFileSync(authPath, `${JSON.stringify(auth, null, 2)}\n`, "utf8");
}

function buildConfigPreview(payload) {
  return {
    providerSnippet: renderProviderSection(payload).trimEnd(),
    profileSnippet: renderProfileSection(payload).trimEnd(),
    warnings: [
      payload.authMode === "desktop_auth"
        ? "当前模式会把地址写进 config.toml，把 API Key 写进 auth.json。"
        : "当前模式只写 env_key，真正的密钥值需要由系统环境变量提供。",
      "配置导入后更适合新开一个 Codex 会话再使用。",
    ],
  };
}

function validateConfigImport(encoded) {
  const payload = validateConfigPayload(decodePayload(encoded));
  return { ok: true, ...buildConfigPreview(payload) };
}

function importConfig(encoded) {
  const payload = validateConfigPayload(decodePayload(encoded));
  const before = readConfigText();
  const authBeforeText = existsSync(authPath) ? readFileSync(authPath, "utf8") : "{}\n";
  const providerSection = renderProviderSection(payload);
  const profileSection = renderProfileSection(payload);
  let merged = upsertTopLevelSection(before, `model_providers.${payload.providerId}`, providerSection);
  merged = upsertTopLevelSection(merged, `profiles.${payload.profileId}`, profileSection);
  const backupPath = backupFile("config", before, "toml");
  let authBackupPath = null;
  writeConfigText(merged);
  if (payload.authMode === "desktop_auth") {
    const auth = readAuthJson();
    auth.auth_mode = "apikey";
    auth.OPENAI_API_KEY = payload.apiKeyValue;
    authBackupPath = backupFile("auth", authBeforeText, "json");
    writeAuthJson(auth);
  }
  log("config_imported", {
    configPath,
    backupPath,
    authPath: payload.authMode === "desktop_auth" ? authPath : null,
    providerId: payload.providerId,
    profileId: payload.profileId,
  });
  return {
    ok: true,
    configPath,
    backupPath,
    authPath: payload.authMode === "desktop_auth" ? authPath : null,
    authBackupPath,
    providerId: payload.providerId,
    profileId: payload.profileId,
    ...buildConfigPreview(payload),
  };
}

function status() {
  return {
    ok: true,
    configPath,
    authPath,
    backupDir,
    logPath,
  };
}

function run() {
  const command = process.argv[2] || "status";

  if (command === "status") {
    printJson(status());
    return;
  }

  if (command === "config-validate") {
    printJson(validateConfigImport(process.argv[3] || ""));
    return;
  }

  if (command === "config-import") {
    printJson(importConfig(process.argv[3] || ""));
    return;
  }

  throw new Error(`Unknown command: ${command}`);
}

try {
  run();
} catch (error) {
  log("fatal", { error: String(error?.stack || error) });
  process.stderr.write(`${String(error?.message || error)}\n`);
  process.exit(1);
}
