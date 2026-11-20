# 致谢与来源

本项目不是从零写起的。核心汉化能力来自以下开源工作，按 MIT 许可证使用并保留署名。

## 上游项目

**[zhonghugo/antigravity-zh](https://github.com/zhonghugo/antigravity-zh)** — MIT，v1.3.1（2026-10-21）

沿用其：

- `install.py`：解包 / 注入 / 重打包 / 备份 / 还原 / 状态检测的主体逻辑。
- `asar.py`：纯 Python 的 asar 解包与打包实现（与 `@electron/asar` 对齐）。
- `dicts/engine.js`：DOM 实时翻译引擎、动态正则规则、覆盖率门槛、思考链跳过规则、外部词典热重载。
- `dicts/zh_cn.json`：5982 条社区校对词条。

上游原始许可证全文保留在 [LICENSE.upstream](LICENSE.upstream)。

## 本项目的改动

- **跨平台**：`install.py` 扩展 Windows 多候选路径与注册表探测、Windows 进程检测、Linux 路径与进程检测；新增 `AGZH_ASAR` 环境变量与 `--info` JSON 输出；签名步骤严格限定为 macOS。
- **可恢复机制**：新增 `ag-zh`（macOS / Linux）与 `ag-zh.ps1` + `ag-zh.cmd`（Windows），提供 `status / install / backup-full / restore / restore-full`。首次安装自动建立整个应用的快照；`restore-full` 可把 macOS 的 Google 官方签名一并恢复；所有回滚都保留旧目录而非删除。
- **版本适配**：词典扩充至 5992 条，补齐 Antigravity 2.33.x 欢迎页新增文案与「本地检出」等条目；引擎新增 2 条整串锚定的动态规则，覆盖官方随机轮播的问候语（用户名动态匹配，词典内不含任何真实账号名）。
- **隐私处理**：展示截图中的历史会话、工作区名与账号名均已遮盖；自检会拦截硬编码的本机路径。
- **工程质量**：`tests/selftest.py` 跨平台自检（asar 往返、词典完整性、注入产物、`--info`、编码与隐私检查）与 GitHub Actions 三平台 CI。
- **缺陷修复**：`asar.list_files()` 原先未拆解 `_read_header()` 的返回值元组，`python asar.py list` 会抛 `AttributeError`；本仓库已修复并加入自检回归。

## 其他参考

词典与术语统一还参考了社区公开项目（AntigravityCN、Antigravity-Chinese-Localization、Zero-Touch 等）的公开词条，这些内容已由上游项目合并整理，详情见上游 README 的更新日志。

## 商标声明

Google、Antigravity、Gemini 等名称归其各自权利人所有。本项目与 Google 及 Antigravity 官方团队无任何关联，仓库内不包含 Antigravity 的任何二进制内容。
