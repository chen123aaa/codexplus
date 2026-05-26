# codexplus

轻量版 CodexPlusPlus，只保留 API 登录模式下解锁 Codex 桌面端插件功能和 Goal 目标模式。

它比 CodexPlusPlus 少一个 `plus`，也少掉中转、广告、会话管理、Provider 同步等重功能。

## 功能

codexplus 只做两件事：

- 通过本机 Chromium DevTools Protocol 解锁 Codex 桌面端左侧的 `插件 / Plugins` 入口和插件页安装按钮。
- 通过 Codex 官方 feature flag 打开实验性的 `goals` 目标模式，避免后端返回 `goals feature is disabled`。

它不会：

- 写入模型供应商、代理、base_url 等配置
- 配置或代理任何 `base_url`
- 同步 provider
- 删除、导出、移动会话
- 拉取广告或远程推荐内容
- 修改 `/Applications/Codex.app`

## 原理

1. 以 `--remote-debugging-port=9229` 启动 Codex 桌面端。
2. 通过 CDP 连接 `app://-/index.html` 页面。
3. 注入一段极小的前端脚本：
   - 将插件入口按钮从 disabled 状态恢复；
   - 在 API 登录模式下临时伪装插件入口所需的 ChatGPT authMethod；
   - 解锁插件页里被前端禁用的安装按钮；
   - 解除目标模式相关按钮的前端 disabled 状态。
4. 启动前执行等价于 `codex features enable goals` 的操作，只写入 `~/.codex/config.toml` 里的 `[features].goals = true`。

## 安装

```bash
./install-macos.sh
```

安装后打开：

```text
/Applications/CodexPlus.app
```

如果 Codex 已经用普通方式打开，并且没有调试端口，建议先完全退出 Codex，再打开这个工具。

日志位置：

```text
~/.codexplus/unlocker.log
```

## 卸载

```bash
rm -rf "/Applications/CodexPlus.app"
rm -rf "/Applications/Codex 插件解锁.app"
rm -rf ~/.codexplus
```

## 说明

codexplus 不修改 Codex 安装文件，也不改变模型供应商配置。模型请求走哪里完全取决于你自己的 `~/.codex/config.toml`。

Goal 目标模式是 Codex 自带的实验性功能。本工具只负责打开本地 feature flag；如果未来官方移除或改名，工具会在日志里记录失败原因。
