# codexplus

轻量版 CodexPlusPlus，只保留 API 登录模式下解锁 Codex 桌面端插件功能。

它比 CodexPlusPlus 少一个 `plus`，也少掉中转、广告、会话管理、Provider 同步等重功能。

## 功能

codexplus 只做一件事：通过本机 Chromium DevTools Protocol 解锁 Codex 桌面端左侧的 `插件 / Plugins` 入口和插件页安装按钮。

它不会：

- 写入 `~/.codex/config.toml`
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
   - 解锁插件页里被前端禁用的安装按钮。

## 安装

```bash
./install-macos.sh
```

安装后打开：

```text
/Applications/Codex 插件解锁.app
```

如果 Codex 已经用普通方式打开，并且没有调试端口，建议先完全退出 Codex，再打开这个工具。

日志位置：

```text
~/.codex-plugin-unlocker/unlocker.log
```

## 卸载

```bash
rm -rf "/Applications/Codex 插件解锁.app"
rm -rf ~/.codex-plugin-unlocker
```

## 说明

codexplus 不修改 Codex 安装文件，也不改变模型供应商配置。模型请求走哪里完全取决于你自己的 `~/.codex/config.toml`。

