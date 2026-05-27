# codexplus

`codexplus` 现在拆成了两个独立工具：

- `CodexPlus`
  - 无界面插件解锁器
  - 只负责启动 Codex、开启 `goals`、解锁插件入口
- `Codex Config Importer`
  - 独立配置导入器
  - 只负责表单生成配置并写入 `~/.codex/config.toml` / `~/.codex/auth.json`

这样拆开之后，插件解锁器不再和配置导入器耦合，权限链也更干净。

## 平台

当前版本只适配 macOS。

原因很直接：这两个工具都依赖 `Codex.app` 的 macOS 应用结构，以及 `open`、`launchctl`、`swiftc`、`LSUIElement` 这些本地能力，所以现在还不是跨平台版本。

## 致谢

这个项目的思路和早期实现参考了开源项目 [CodexPlusPlus](https://github.com/BigPizzaV3/CodexPlusPlus)。

我从里面提取了一些真正有用的部分，尤其是围绕 Codex 插件能力、调试入口和增强方式的思路。也正是因为长期实际使用，才慢慢把它收成了现在这种更轻的形态。

## 为什么这样拆

一开始我把启动器和配置导入都塞进了一个 app 里，后面发现问题很明显：

- 启动器做成独立 GUI app 之后，更容易碰到 macOS 权限和宿主上下文问题
- 配置导入本来就是另一类需求，没必要和插件解锁绑死
- 两种功能放一起，维护和排错都容易互相影响

所以现在改成：

- `CodexPlus` 回退到第一版那种无界面脚本模式
- `Codex Config Importer` 单独做成一个独立 app

## CodexPlus

### 作用

`CodexPlus` 现在只做这些事：

- 以带调试端口的方式启动 Codex
- 解锁插件入口和插件安装按钮
- 兼容新版 `添加到 Codex` / `Add to Codex` 按钮
- 自动确认 `plugins` / `apps` / `browser_use` / `computer_use` / `image_generation` 等 Codex feature 已开启
- 开启 `goals` 目标模式
- 开启运行时防止系统休眠
- 开启接通电源时远程控制保持唤醒
- 尽量保持本地线程视图优先

它不会再承担配置导入功能。

### 安装

```bash
./install-macos.sh
```

安装后得到：

```text
/Applications/CodexPlus.app
```

这是一个无界面 app。打开后不会出现窗口，只会执行解锁流程。

### 使用

直接打开：

```text
/Applications/CodexPlus.app
```

也可以在终端里执行：

```bash
open -a /Applications/CodexPlus.app
```

它会完成一次性启动和注入，然后自行退出，不长期驻留。

### Codex 更新后的处理

Codex 更新后如果插件入口还在，但安装或添加按钮不听话，通常是两类原因：

- 官方 UI 文案或 DOM 改了，比如新版把 `安装` 改成了 `添加到 Codex`
- 页面里还留着旧版 CodexPlus 注入脚本，需要提高注入版本号后重新覆盖

当前版本已经把注入脚本更新到 `codexplus-v3`，并兼容 `添加到 Codex` / `Add to Codex`。

### 唤醒 / 锁屏相关

CodexPlus 会写入 Codex 官方配置：

```toml
[desktop]
preventSleepWhileRunning = true
keepRemoteControlAwakeWhilePluggedIn = true
```

这两个开关对应的是：

- Codex 运行对话时，尽量防止系统自动休眠
- 接通电源时，远程控制保持唤醒

之前看到的“锁屏状态下使用 Mac 应用程序”入口，属于 Codex 官方远程控制 / 手机连接相关界面。这个入口在新版 Codex 里还存在，但会受登录方式、账号能力、远程控制状态影响，不一定每次都显示。

所以 CodexPlus 现在做的是：把本地能打开的底层配置先打开，并在前端注入时尽量解除相关按钮的禁用状态；如果官方后端没有给当前账号开放入口，它不会伪造后端能力。

### 日志

```text
~/.codexplus/unlocker.log
```

## Codex Config Importer

### 作用

这是单独的配置导入器，和插件解锁器完全分离。

它支持：

- 填写 `provider_id`
- 填写 `provider name`
- 填写 `base_url`
- 选择认证模式
  - `Desktop auth.json`
  - `Env Key`
- 填写 `API Key` 或 `API Key Env`
- 填写 `model`
- 填写 `profile_id`
- 填写 `model_reasoning_effort`
- 可选 `http_headers`
- 校验配置
- 导入配置
- 导出 / 导入 JSON

### 安装

```bash
./install-config-importer.sh
```

安装后得到：

```text
/Applications/Codex Config Importer.app
```

### 使用

直接打开：

```text
/Applications/Codex Config Importer.app
```

也可以在终端里执行：

```bash
open -a "/Applications/Codex Config Importer.app"
```

### 导入逻辑

默认推荐 `Desktop auth.json` 模式：

- `config.toml` 写 `model_providers` / `profiles` / `base_url`
- `auth.json` 写 API Key

高级模式 `Env Key`：

- `config.toml` 只写 `env_key`
- 真正密钥值由系统环境变量提供

导入前会自动备份到：

```text
~/.codexplus/backups/
```

## 推荐使用顺序

如果你两个都要用，推荐这样：

1. 先运行 `CodexPlus.app`，完成插件解锁
2. 再打开官方 `Codex`
3. 需要配模型时，再单独打开 `Codex Config Importer.app`

## 卸载

```bash
rm -rf "/Applications/CodexPlus.app"
rm -rf "/Applications/Codex Config Importer.app"
rm -rf "/Applications/Codex 插件解锁.app"
rm -rf ~/.codexplus
```

## 说明

- `CodexPlus` 不改 `/Applications/Codex.app`
- 不做代理，不改证书，不挂额外网络服务
- 唤醒配置写在 `~/.codex/config.toml`，可以随时手动删除
- 配置导入更适合新开一个 Codex 会话后生效

## 后续

后面仍然只做最有用的功能，只服务 Codex，不往臃肿方向走。
