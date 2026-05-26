# codexplus

`codexplus` 现在拆成了两个独立工具：

- `CodexPlus`
  - 无界面插件解锁器
  - 只负责启动 Codex、开启 `goals`、解锁插件入口
- `Codex Config Importer`
  - 独立配置导入器
  - 只负责表单生成配置并写入 `~/.codex/config.toml` / `~/.codex/auth.json`

这样拆开之后，插件解锁器不再和配置导入器耦合，权限链也更干净。

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
- 开启 `goals` 目标模式
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

它会完成一次性启动和注入，然后自行退出，不长期驻留。

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
- 配置导入更适合新开一个 Codex 会话后生效

## 后续

后面仍然只做最有用的功能，只服务 Codex，不往臃肿方向走。
