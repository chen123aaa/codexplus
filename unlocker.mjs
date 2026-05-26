#!/usr/bin/env node
import { spawn, execFileSync } from "node:child_process";
import { mkdirSync, appendFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const debugPort = Number(process.env.CODEX_PLUGIN_UNLOCK_PORT || "9229");
const codexAppPath = process.env.CODEX_APP_PATH || "/Applications/Codex.app";
const codexExecutable = join(codexAppPath, "Contents/MacOS/Codex");
const codexCliExecutable = process.env.CODEX_CLI_PATH || join(codexAppPath, "Contents/Resources/codex");
const nodeExecutable = process.execPath;
const scriptPath = fileURLToPath(import.meta.url);
const logPath = join(process.env.HOME || ".", ".codexplus/unlocker.log");
const pollMs = 2000;
const startupTimeoutMs = 30000;
const serviceArg = "service";
const oneShotServiceArg = "service-once";

mkdirSync(dirname(logPath), { recursive: true });

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

function notify(title, message) {
  log("notify_skipped", { title, message });
}

async function fetchJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  if (!response.ok) throw new Error(`HTTP ${response.status} for ${url}`);
  return response.json();
}

async function codexTargets() {
  try {
    const targets = await fetchJson(`http://127.0.0.1:${debugPort}/json/list`);
    return targets.filter((target) => target.type === "page" && String(target.url || "").startsWith("app://-/index.html"));
  } catch {
    return [];
  }
}

function codexInstalled() {
  return existsSync(codexExecutable);
}

function codexProcessRunning() {
  try {
    const output = execFileSync("pgrep", ["-f", "/Applications/Codex.app/Contents/MacOS/Codex"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return output.trim().length > 0;
  } catch {
    return false;
  }
}

function codexMainProcesses() {
  try {
    const output = execFileSync("ps", ["-axo", "pid=,command="], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return output
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const match = line.match(/^(\d+)\s+(.+)$/);
        if (!match) return null;
        return { pid: Number(match[1]), command: match[2] };
      })
      .filter((entry) => entry && entry.command.includes("/Applications/Codex.app/Contents/MacOS/Codex"));
  } catch {
    return [];
  }
}

function unlockerServiceRunning() {
  try {
    const output = execFileSync("pgrep", ["-f", `${scriptPath} ${serviceArg}`], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return output
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .some((pid) => Number(pid) !== process.pid);
  } catch {
    return false;
  }
}

function killLegacyUnlockers() {
  const legacyPatterns = [
    "/Applications/Codex 插件解锁.app/Contents/Resources/unlocker.mjs",
  ];

  for (const pattern of legacyPatterns) {
    try {
      const output = execFileSync("pgrep", ["-f", pattern], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
      const pids = output
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean);
      for (const pid of pids) {
        execFileSync("kill", [pid], { stdio: ["ignore", "ignore", "ignore"] });
        log("legacy_unlocker_killed", { pid, pattern });
      }
    } catch {
      // No legacy process running.
    }
  }
}

function killCurrentUnlockerServices() {
  try {
    const output = execFileSync("pgrep", ["-f", `${scriptPath} ${serviceArg}`], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const pids = output
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .filter((pid) => Number(pid) !== process.pid);
    for (const pid of pids) {
      execFileSync("kill", [pid], { stdio: ["ignore", "ignore", "ignore"] });
      log("current_unlocker_service_killed", { pid });
    }
  } catch {
    // No current service running.
  }
}

function activateCodex() {
  if (!codexInstalled()) return;
  try {
    execFileSync("open", ["-a", codexAppPath], { stdio: ["ignore", "ignore", "ignore"] });
  } catch (error) {
    log("activate_codex_failed", { error: String(error?.message || error) });
  }
}

function quitCodex() {
  try {
    execFileSync("pkill", ["-f", "/Applications/Codex.app/Contents/MacOS/Codex"], {
      stdio: ["ignore", "ignore", "ignore"],
    });
    log("codex_quit_requested");
  } catch (error) {
    log("codex_quit_request_failed", { error: String(error?.message || error) });
  }
}

async function waitForCodexExit(timeoutMs = 15000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (!codexProcessRunning()) return true;
    await new Promise((resolve) => setTimeout(resolve, 300));
  }
  return false;
}

async function restartCodexInUnlockMode() {
  quitCodex();
  const exited = await waitForCodexExit();
  if (!exited) {
    try {
      execFileSync("pkill", ["-f", "/Applications/Codex.app/Contents/MacOS/Codex"], {
        stdio: ["ignore", "ignore", "ignore"],
      });
      log("codex_force_killed_for_restart");
    } catch (error) {
      log("codex_force_kill_failed", { error: String(error?.message || error) });
    }
    await waitForCodexExit(5000);
  }
  launchCodex();
}

function codexNeedsRelaunchForUnlock(targets) {
  const processes = codexMainProcesses();
  const hasDebugProcess = processes.some((process) => process.command.includes("--remote-debugging-port="));
  const hasPlainProcess = processes.some((process) => !process.command.includes("--remote-debugging-port="));
  return targets.length === 0 || hasPlainProcess || !hasDebugProcess || processes.length !== 1;
}

function launchCodex() {
  if (!codexInstalled()) {
    throw new Error(`Codex executable not found: ${codexExecutable}`);
  }
  const child = spawn(
    codexExecutable,
    [
      `--remote-debugging-port=${debugPort}`,
      `--remote-allow-origins=http://127.0.0.1:${debugPort}`,
    ],
    {
      detached: true,
      stdio: "ignore",
    },
  );
  child.unref();
  log("codex_launch_requested", { codexExecutable, debugPort });
}

function codexCli(args) {
  return execFileSync(codexCliExecutable, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    timeout: 10000,
  });
}

function effectiveFeatureState(featureName) {
  if (!existsSync(codexCliExecutable)) return null;
  const output = codexCli(["features", "list"]);
  const line = output
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .find((entry) => entry.startsWith(`${featureName} `));
  if (!line) return null;
  const state = line.split(/\s+/).at(-1);
  if (state === "true") return true;
  if (state === "false") return false;
  return null;
}

function enableGoalFeatureFlag() {
  if (!existsSync(codexCliExecutable)) {
    log("goal_feature_skipped", { reason: "codex_cli_missing", codexCliExecutable });
    return { enabled: false, changed: false, error: `Codex CLI not found: ${codexCliExecutable}` };
  }

  try {
    const before = effectiveFeatureState("goals");
    if (before === true) {
      log("goal_feature_already_enabled");
      return { enabled: true, changed: false };
    }

    const output = codexCli(["features", "enable", "goals"]);
    const after = effectiveFeatureState("goals");
    log("goal_feature_enable_requested", { before, after, output: output.trim() });
    return { enabled: after === true, changed: after === true };
  } catch (error) {
    log("goal_feature_enable_failed", { error: String(error?.message || error), codexCliExecutable });
    return { enabled: false, changed: false, error: String(error?.message || error) };
  }
}

async function waitForTargets() {
  const started = Date.now();
  while (Date.now() - started < startupTimeoutMs) {
    const targets = await codexTargets();
    if (targets.length) return targets;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return [];
}

function cdpCall(ws, id, method, params = {}) {
  ws.send(JSON.stringify({ id, method, params }));
}

async function evaluateOnTarget(target, expression) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    const timeout = setTimeout(() => {
      try {
        ws.close();
      } catch {
        // ignore
      }
      reject(new Error(`CDP timeout for ${target.url}`));
    }, 5000);
    let nextId = 1;
    ws.onopen = () => {
      cdpCall(ws, nextId++, "Runtime.enable");
      cdpCall(ws, nextId++, "Runtime.evaluate", {
        expression,
        awaitPromise: true,
        returnByValue: true,
      });
    };
    ws.onerror = () => {
      clearTimeout(timeout);
      reject(new Error(`CDP websocket error for ${target.url}`));
    };
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.id !== 2) return;
      clearTimeout(timeout);
      try {
        ws.close();
      } catch {
        // ignore
      }
      if (message.error) {
        reject(new Error(message.error.message || "Runtime.evaluate failed"));
      } else {
        resolve(message.result?.result?.value || null);
      }
    };
  });
}

const unlockerScript = String.raw`
(() => {
  const version = "codexplus-v2";
  const existing = window.__codexPlusUnlockerController;
  if (existing && existing.version === version && typeof existing.tick === "function") {
    return { status: "already-installed", ...existing.tick() };
  }

  const selectors = {
    disabledInstallButton: 'button:disabled, button[aria-disabled="true"], [role="button"][aria-disabled="true"], button[data-disabled], [role="button"][data-disabled], button.cursor-not-allowed, [role="button"].cursor-not-allowed, button.pointer-events-none, [role="button"].pointer-events-none',
    disabledInteractive: 'button:disabled, button[aria-disabled="true"], [role="button"][aria-disabled="true"], button[data-disabled], [role="button"][data-disabled], button.cursor-not-allowed, [role="button"].cursor-not-allowed, button.pointer-events-none, [role="button"].pointer-events-none',
    pluginNavButton: 'nav[role="navigation"] button.h-token-nav-row.w-full',
    pluginSvgPath: 'svg path[d^="M7.94562 14.0277"]',
  };

  function reactFiberFrom(element) {
    const fiberKey = Object.keys(element).find((key) => key.startsWith("__reactFiber"));
    return fiberKey ? element[fiberKey] : null;
  }

  function authContextValueFrom(element) {
    for (let fiber = reactFiberFrom(element); fiber; fiber = fiber.return) {
      for (const value of [fiber.memoizedProps?.value, fiber.pendingProps?.value]) {
        if (value && typeof value === "object" && typeof value.setAuthMethod === "function" && "authMethod" in value) {
          return value;
        }
      }
    }
    return null;
  }

  function spoofChatGPTAuthMethod(element) {
    const auth = authContextValueFrom(element);
    if (!auth || auth.authMethod === "chatgpt") return false;
    auth.setAuthMethod("chatgpt");
    return true;
  }

  function pluginEntryButton() {
    const byIcon = document.querySelector(selectors.pluginNavButton + " " + selectors.pluginSvgPath)?.closest("button");
    if (byIcon) return byIcon;
    return Array.from(document.querySelectorAll(selectors.pluginNavButton))
      .find((button) => /^(插件|Plugins)(\s+-\s+.*)?$/i.test((button.textContent || "").trim())) || null;
  }

  function labelUnlockedPluginEntry(button) {
    const labelTextNode = Array.from(button.querySelectorAll("span, div")).reverse()
      .flatMap((node) => Array.from(node.childNodes))
      .find((node) => node.nodeType === 3 && /^(插件|Plugins)( - 已解锁| - Unlocked)?$/i.test((node.nodeValue || "").trim()));
    if (!labelTextNode) return;
    const current = (labelTextNode.nodeValue || "").trim();
    labelTextNode.nodeValue = /^Plugins/i.test(current) ? "Plugins - Unlocked" : "插件 - 已解锁";
  }

  function patchReactDisabledProps(element) {
    Object.keys(element)
      .filter((key) => key.startsWith("__reactProps"))
      .forEach((key) => {
        const props = element[key];
        if (!props || typeof props !== "object") return;
        props.disabled = false;
        props["aria-disabled"] = false;
        props["data-disabled"] = undefined;
      });
  }

  function clearDisabledState(element) {
    if (!(element instanceof HTMLElement)) return;
    if ("disabled" in element) element.disabled = false;
    element.removeAttribute("disabled");
    element.removeAttribute("aria-disabled");
    element.removeAttribute("data-disabled");
    element.removeAttribute("inert");
    element.classList.remove("disabled", "opacity-50", "cursor-not-allowed", "pointer-events-none");
    element.style.pointerEvents = "auto";
    element.style.opacity = "";
    element.style.cursor = "pointer";
    element.tabIndex = 0;
    patchReactDisabledProps(element);
  }

  function reactPropsFrom(element) {
    return Object.keys(element)
      .filter((key) => key.startsWith("__reactProps"))
      .map((key) => element[key])
      .filter(Boolean);
  }

  function triggerReactClick(element) {
    for (const props of reactPropsFrom(element)) {
      if (typeof props.onClick === "function") {
        try {
          props.onClick({
            currentTarget: element,
            target: element,
            preventDefault() {},
            stopPropagation() {},
            nativeEvent: {},
          });
          return true;
        } catch {
          // ignore and try normal click
        }
      }
    }
    return false;
  }

  function safeClick(element) {
    if (!(element instanceof HTMLElement)) return false;
    try {
      element.click();
      return true;
    } catch {
      return triggerReactClick(element);
    }
  }

  function enablePluginEntry() {
    const pluginButton = pluginEntryButton();
    if (!pluginButton) return false;
    spoofChatGPTAuthMethod(pluginButton);
    clearDisabledState(pluginButton);
    pluginButton.style.display = "";
    pluginButton.querySelectorAll("*").forEach((node) => {
      node.style.display = "";
    });
    labelUnlockedPluginEntry(pluginButton);
    if (pluginButton.dataset.codexPluginEnabled !== "true") {
      pluginButton.dataset.codexPluginEnabled = "true";
      pluginButton.addEventListener("click", () => spoofChatGPTAuthMethod(pluginButton), true);
    }
    return true;
  }

  function installButtonLabel(element) {
    return (element.textContent || "").trim();
  }

  function isInstallButtonLabel(text) {
    return /^安装\s*/.test(text) || /^Install\s*/i.test(text) || text === "强制安装";
  }

  function pluginInstallCandidates() {
    const nodes = Array.from(document.querySelectorAll(selectors.disabledInstallButton));
    return Array.from(new Set(nodes.map((node) => node.closest?.("button, [role='button']") || node)));
  }

  function installButtonUnlockNodes(button) {
    const nodes = [button];
    button.querySelectorAll?.("button, [role='button'], [disabled], [aria-disabled], [data-disabled], .cursor-not-allowed, .pointer-events-none")
      .forEach((node) => nodes.push(node));
    let parent = button.parentElement;
    for (let depth = 0; parent && depth < 3; depth += 1, parent = parent.parentElement) {
      if (parent.matches?.("button, [role='button'], [disabled], [aria-disabled], [data-disabled], .cursor-not-allowed, .pointer-events-none")) {
        nodes.push(parent);
      }
    }
    return Array.from(new Set(nodes));
  }

  function labelForcedInstallButton(button) {
    const walker = document.createTreeWalker(button, NodeFilter.SHOW_TEXT);
    let textNode = null;
    while (!textNode && walker.nextNode()) {
      const node = walker.currentNode;
      if (isInstallButtonLabel((node.nodeValue || "").trim())) textNode = node;
    }
    if (textNode) textNode.nodeValue = "强制安装";
  }

  function installForcedInstallGuard(button) {
    if (button.dataset.codexForceInstallUnlocked === "true") return;
    button.dataset.codexForceInstallUnlocked = "true";
    const keepUnlocked = () => installButtonUnlockNodes(button).forEach(clearDisabledState);
    ["pointerdown", "mousedown", "mouseup", "click", "focus"].forEach((eventName) => {
      button.addEventListener(eventName, keepUnlocked, true);
    });
  }

  function unblockPluginInstallButtons() {
    let count = 0;
    pluginInstallCandidates().forEach((button) => {
      const text = installButtonLabel(button);
      if (!isInstallButtonLabel(text)) return;
      installButtonUnlockNodes(button).forEach(clearDisabledState);
      installForcedInstallGuard(button);
      labelForcedInstallButton(button);
      count += 1;
    });
    return count;
  }

  function isGoalControl(element) {
    const text = [
      element.textContent,
      element.getAttribute?.("aria-label"),
      element.getAttribute?.("title"),
      element.getAttribute?.("data-testid"),
      element.getAttribute?.("data-test-id"),
    ].filter(Boolean).join(" ");
    return /\bgoal\b|目标|设置目标|清除目标|Goal/i.test(text);
  }

  function unblockGoalControls() {
    let count = 0;
    Array.from(document.querySelectorAll(selectors.disabledInteractive)).forEach((node) => {
      const button = node.closest?.("button, [role='button']") || node;
      if (!isGoalControl(button)) return;
      clearDisabledState(button);
      button.querySelectorAll?.("[disabled], [aria-disabled], [data-disabled], .cursor-not-allowed, .pointer-events-none")
        .forEach(clearDisabledState);
      count += 1;
    });
    return count;
  }

  function localModeCandidates() {
    const interactive = Array.from(document.querySelectorAll('button,[role="button"],[role="tab"],a'));
    return interactive.filter((element) => {
      const text = [
        element.textContent,
        element.getAttribute("aria-label"),
        element.getAttribute("title"),
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
      if (!text) return false;
      return /(^|\s)(Local|Locally|本地)(\s|$)/i.test(text) && !/(Cloud|云)/i.test(text);
    });
  }

  function localThreadRowsVisible() {
    return Array.from(document.querySelectorAll('[role="button"],[role="listitem"],button,div'))
      .some((element) => /vscode/i.test((element.textContent || "").trim()));
  }

  function preferLocalThreadView() {
    const candidates = localModeCandidates();
    let switched = false;
    for (const element of candidates) {
      if (element.getAttribute("aria-selected") === "true" || element.getAttribute("data-state") === "active") {
        return { switched: false, alreadyLocal: true, candidates: candidates.length };
      }
      if (safeClick(element)) {
        switched = true;
        break;
      }
    }
    return {
      switched,
      alreadyLocal: false,
      candidates: candidates.length,
      rowsVisible: localThreadRowsVisible(),
    };
  }

  function tick() {
    const entryUnlocked = enablePluginEntry();
    const installUnlocked = unblockPluginInstallButtons();
    const goalControlsUnlocked = unblockGoalControls();
    const localView = preferLocalThreadView();
    return { entryUnlocked, installUnlocked, goalControlsUnlocked, localView };
  }

  window.__codexPlusUnlockerController = { version, tick };
  tick();
  window.__codexPluginUnlockerTimer = setInterval(tick, 1000);
  new MutationObserver(tick).observe(document.documentElement, { childList: true, subtree: true });

  return { status: "installed", ...tick() };
})()
`;

async function injectAllTargets() {
  const targets = await codexTargets();
  for (const target of targets) {
    try {
      const result = await evaluateOnTarget(target, unlockerScript);
      log("inject_ok", { target: target.url, result });
    } catch (error) {
      log("inject_failed", { target: target.url, error: String(error?.message || error) });
    }
  }
  return targets.length;
}

async function statusSnapshot() {
  const targets = await codexTargets();
  return {
    codexInstalled: codexInstalled(),
    codexRunning: codexProcessRunning(),
    unlockerRunning: unlockerServiceRunning(),
    goalsEnabled: effectiveFeatureState("goals") === true,
    debugTargetCount: targets.length,
    logPath,
  };
}

function spawnService(mode = serviceArg) {
  const child = spawn(nodeExecutable, [scriptPath, mode], {
    detached: true,
    stdio: "ignore",
  });
  child.unref();
}

async function serviceMain({ oneShot = false } = {}) {
  killLegacyUnlockers();
  log("unlocker_start", { debugPort, codexExecutable });
  const goalFeature = enableGoalFeatureFlag();
  let targets = await codexTargets();
  if (codexNeedsRelaunchForUnlock(targets)) {
    if (codexProcessRunning()) {
      log("codex_restart_needed_for_clean_unlock_mode", {
        targets: targets.length,
        processes: codexMainProcesses(),
      });
      notify("CodexPlus", "检测到当前 Codex 不是单一解锁实例，正在自动重启到插件解锁模式。");
      await restartCodexInUnlockMode();
    } else {
      launchCodex();
    }
    targets = await waitForTargets();
  }
  activateCodex();

  if (!targets.length) {
    notify("CodexPlus", "没有检测到 Codex 调试页面。请先完全退出 Codex，再重新打开本工具。");
    log("no_targets_after_launch");
  } else {
    const message = goalFeature.changed
      ? "已开启目标模式配置。若 Codex 之前已经打开，请完全退出后重新打开 CodexPlus 让后端生效。"
      : "已启动，正在保持插件入口和目标模式解锁。";
    notify("CodexPlus", message);
  }

  if (oneShot) {
    const injectedCount = await injectAllTargets();
    log("one_shot_unlock_completed", { injectedCount });
    setTimeout(() => {
      log("one_shot_unlock_exit");
      process.exit(0);
    }, 2500);
    return;
  }

  let emptyTargetTicks = 0;
  setInterval(async () => {
    const count = await injectAllTargets();
    if (count === 0) emptyTargetTicks += 1;
    else emptyTargetTicks = 0;
    if (emptyTargetTicks > 30 && !codexProcessRunning()) {
      log("codex_not_running_exit");
      process.exit(0);
    }
  }, pollMs);

  await injectAllTargets();
}

async function run() {
  const command = process.argv[2] || serviceArg;

  if (command === "status") {
    printJson(await statusSnapshot());
    return;
  }

  if (command === "enable-goals") {
    printJson(enableGoalFeatureFlag());
    return;
  }

  if (command === "launch-codex") {
    launchCodex();
    activateCodex();
    printJson({ ok: true });
    return;
  }

  if (command === "activate-codex") {
    activateCodex();
    printJson({ ok: true });
    return;
  }

  if (command === "start-service") {
    killLegacyUnlockers();
    killCurrentUnlockerServices();
    const feature = enableGoalFeatureFlag();
    spawnService(oneShotServiceArg);
    log("service_spawned_from_ui", { goalFeatureEnabled: feature.enabled, mode: oneShotServiceArg });
    activateCodex();
    printJson({ ok: true, goalsEnabled: feature.enabled, serviceRunning: true });
    return;
  }

  if (command === serviceArg) {
    await serviceMain({ oneShot: false });
    return;
  }

  if (command === oneShotServiceArg) {
    await serviceMain({ oneShot: true });
    return;
  }

  throw new Error(`Unknown command: ${command}`);
}

run().catch((error) => {
  log("fatal", { error: String(error?.stack || error) });
  if (process.argv[2] === serviceArg || !process.argv[2]) {
    notify("CodexPlus 解锁失败", String(error?.message || error));
  } else {
    process.stderr.write(`${String(error?.message || error)}\n`);
  }
  process.exit(1);
});
