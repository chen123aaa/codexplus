# codexplus

`codexplus` 现在做两件事，而且都只服务 Codex：

- 启动 Codex，并保持插件入口和 `goals` 目标模式可用
- 作为一个轻量的 `Codex Config Importer`，把表单配置 merge 到 `~/.codex/config.toml`

它不是代理器，也不是“大一统切换器”。

## 界面

`CodexPlus.app` 现在有两个页签：

- `启动器`
  - 启动并解锁 Codex
  - 打开 Codex
  - 查看日志
- `配置导入`
  - 新增 Provider 参数
  - 新增 Profile 参数
  - 校验配置
  - 导入到 Codex
  - 导出 / 导入 JSON 备份

## 配置导入支持字段

- `provider_id`
- `provider name`
- `base_url`
- `api_key env`
- `model`
- `profile_id`
- `model_reasoning_effort`
- 可选 `http_headers`

生成结果会自动转成类似下面的片段，并 merge 到用户级 `~/.codex/config.toml`：

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

## 安装

```bash
./install-macos.sh
```

安装后打开：

```text
/Applications/CodexPlus.app
```

第一次安装会用系统自带 `swiftc` 编译原生 macOS 界面，所以需要本机装有 Xcode Command Line Tools。

## 日志

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

- `CodexPlus` 不修改 `/Applications/Codex.app`
- 不做代理，不改证书，不常驻额外网络服务
- 配置导入更适合新开一个 Codex 会话后生效，不保证无缝切当前正在跑的会话
