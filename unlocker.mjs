#!/usr/bin/env node
import { spawn, execFileSync } from "node:child_process";
import { mkdirSync, appendFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const debugPort = Number(process.env.CODEX_PLUGIN_UNLOCK_PORT || "9229");
const codexAppPath = process.env.CODEX_APP_PATH || "/Applications/Codex.app";
const codexExecutable = join(codexAppPath, "Contents/MacOS/Codex");
const logPath = join(process.env.HOME || ".", ".codex-plugin-unlocker/unlocker.log");
const pollMs = 2000;
const startupTimeoutMs = 30000;

mkdirSync(dirname(logPath), { recursive: true });

function log(message, detail = {}) {
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    message,
    ...detail,
  });
  appendFileSync(logPath, `${line}\n`);
}

function notify(title, message) {
  try {
    execFileSync("osascript", [
      "-e",
      `display notification ${JSON.stringify(message)} with title ${JSON.stringify(title)}`,
    ]);
  } catch {
    // Notifications are convenience only.
  }
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

function launchCodex() {
  if (!existsSync(codexExecutable)) {
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
  if (window.__codexPluginUnlockerInstalled === "1") {
    return { status: "already-installed" };
  }
  window.__codexPluginUnlockerInstalled = "1";

  const selectors = {
    disabledInstallButton: 'button:disabled, button[aria-disabled="true"], [role="button"][aria-disabled="true"], button[data-disabled], [role="button"][data-disabled], button.cursor-not-allowed, [role="button"].cursor-not-allowed, button.pointer-events-none, [role="button"].pointer-events-none',
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

  function tick() {
    const entryUnlocked = enablePluginEntry();
    const installUnlocked = unblockPluginInstallButtons();
    return { entryUnlocked, installUnlocked };
  }

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

async function main() {
  log("unlocker_start", { debugPort, codexExecutable });
  let targets = await codexTargets();
  if (!targets.length) {
    launchCodex();
    targets = await waitForTargets();
  }
  if (!targets.length) {
    notify("Codex 插件解锁", "没有检测到 Codex 调试页面。请先完全退出 Codex，再重新打开本工具。");
    log("no_targets_after_launch");
  } else {
    notify("Codex 插件解锁", "已启动，正在保持插件入口解锁。");
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

main().catch((error) => {
  log("fatal", { error: String(error?.stack || error) });
  notify("Codex 插件解锁失败", String(error?.message || error));
  process.exit(1);
});
