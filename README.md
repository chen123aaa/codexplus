# codexplus

一个只服务 Codex 的轻量工具。

它不做代理，不做管理面板，不做一堆和日常使用关系不大的功能。目标很直接：把真正常用、又确实能省事的能力单独拎出来，做成一个打开就能用的小工具。

## 致谢

这个项目的思路和早期实现，参考了开源项目 [CodexPlusPlus](https://github.com/BigPizzaV3/CodexPlusPlus)。

先说结论：这个项目给了我不少启发，我也确实从里面提取了一些我觉得有用的部分，尤其是围绕 Codex 插件能力、调试入口和一些可行的增强方式。

也正因为实际用了很久，才有了现在这个轻量版。

## 为什么重新做一个轻量版

我自己在使用 `CodexPlusPlus` 的过程中，最明显的感受就是它启动偏慢。

尤其是每次重启 Codex 之后，从打开到真正进入聊天界面，中间会卡很久。这个问题我没有完全定位清楚，可能和它接管的能力比较多、初始化链路比较长有关，但至少从体验上说，这件事非常影响日常使用。

后来我想过要不要继续往原来的方向修，想了一圈之后，决定不再往“大而全”的方向堆，而是换个思路：

- 只保留最有用的功能
- 只服务 Codex
- 能直接运行就直接运行
- 不折腾额外代理、证书、后台网络服务

所以就有了 `codexplus`。

## 这个项目现在在做什么

`codexplus` 目前把功能收在一个原生 macOS 小界面里，只有两个页签：

- `启动器`
- `配置导入`

它现在已经实现的功能有：

- 启动 Codex
- 保持 Codex 插件入口可用
- 开启 `goals` 目标模式
- 提供一个轻量的 `Codex Config Importer`
- 用表单填写 Provider / Profile 参数
- 自动生成 `model_providers` 和 `profiles` 配置片段
- 一键 merge 到 `~/.codex/config.toml`
- 导入前自动备份旧配置
- 支持 JSON 导出 / 导入，方便备份和迁移

## 配置导入支持字段

目前表单支持这些字段：

- `provider_id`
- `provider name`
- `base_url`
- `api_key env`
- `model`
- `profile_id`
- `model_reasoning_effort`
- 可选 `http_headers`

生成出来的配置大致是这样：

```toml
[model_providers.openrouter]
name = "OpenRouter"
base_url = "https://openrouter.ai/api/v1"
env_key = "OPENROUTER_API_KEY"
wire_api = "responses"

[profiles.openrouter_gpt5]
model_provider = "openrouter"
model = "gpt-5.4"
model_reasoning_effort = "high"
```

导入时会先备份旧配置到：

```text
~/.codexplus/backups/
```

## 和 CodexPlusPlus 的区别

这不是 `CodexPlusPlus` 的替代壳，也不是换皮版。

我想做的是一个更小、更稳、更好维护的工具，所以一开始就把边界定得很死：

- 不做代理
- 不改证书
- 不做大而全的管理工具
- 不依赖复杂的后台常驻逻辑
- 不去碰一堆现在 Codex 官方新版已经逐步适配掉的功能

说白了，很多以前要靠管理工具去补的东西，Codex 新版自己已经在补了。既然这样，就没必要继续把工具做得越来越重。

`codexplus` 只把现在还真正有价值、而且我自己每天确实在用的东西留下来。

## 兼容性和更新方式

这个项目会尽量跟着最新版 Codex 去适配。

思路不是让你在什么管理工具里反复更新一堆组件，而是尽量把东西收在这个项目本身里。正常情况下，只需要下载新的 `CodexPlus` 版本，安装后直接运行就行，不需要再去管理工具里单独折腾更新。

当然，Codex 官方如果后面改了内部结构，这边也会继续跟着调整。

## 安装

```bash
./install-macos.sh
```

安装完成后，打开：

```text
/Applications/CodexPlus.app
```

第一次安装会调用系统自带 `swiftc` 编译原生 macOS 界面，所以本机需要安装 Xcode Command Line Tools。

## 使用

### 1. 启动器

如果你只是想正常打开 Codex，并保持插件入口和目标模式可用，直接打开 `CodexPlus.app`，在 `启动器` 页签点击：

```text
启动并解锁 Codex
```

### 2. 配置导入

如果你想省掉手改 `~/.codex/config.toml` 的过程，就切到 `配置导入`：

1. 填 Provider 参数
2. 填 Profile 参数
3. 先点 `校验配置`
4. 确认没问题后点 `导入到 Codex`

更适合新开一个 Codex 会话之后生效，不保证无缝切到当前已经在运行的会话。

## 日志

运行日志在这里：

```text
~/.codexplus/unlocker.log
```

## 卸载

```bash
rm -rf "/Applications/CodexPlus.app"
rm -rf "/Applications/Codex 插件解锁.app"
rm -rf ~/.codexplus
```

## 后续

后面会继续更新，但还是同一个原则：

只做最有用的功能，只服务 Codex，不往臃肿的方向走。
