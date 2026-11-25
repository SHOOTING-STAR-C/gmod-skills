# 环境配置与校验

脚本适用于 PowerShell 5.1 / 7。在 skill 根目录复制 `.env.example` 为 `.env`，填写目标 addon 和需要的工具路径。配置模板不包含任何本机真实路径。

```powershell
Copy-Item -LiteralPath .env.example -Destination .env
. ./scripts/load_gmod_env.ps1
$config = Import-GmodEnv
$tools = $config['GMOD_TOOLS_DIR']
```

也可用 `Import-GmodEnv -Path <配置路径>` 读取已有配置。加载器返回 hashtable，并将结果写入当前进程环境，不修改系统环境变量。它不执行 `.env` 中的代码。

## 路径规则

显式配置值优先于派生默认值。相对路径基于 `.env` 所在目录；支持引号和 `${VARIABLE}` 引用，未定义或循环引用会报错。行尾注释不被剥离，请单独写注释行。文件未定义的引用可使用进程环境变量；普通字段不会自动从进程继承。

| 变量 | 默认来源 |
|---|---|
| GMOD_ADDON_DIR | 显式指定；校验时 -AddonRoot 优先 |
| GARRYSMOD_DIR | GMOD_ROOT/garrysmod |
| GMOD_ADDONS_DIR | GARRYSMOD_DIR/addons |
| GMOD_TOOLS_DIR | GARRYSMOD_DIR/bakmod/tools |
| CROWBAR_EXE | GMOD_TOOLS_DIR/Crowbar/Crowbar.exe |
| CROWBAR_CLI_EXE | GMOD_TOOLS_DIR/CrowbarCLI.exe |
| STUDIOMDL_EXE | GMOD_ROOT/bin/studiomdl.exe |
| STUDIOMDL_CE_X64_EXE | GMOD_TOOLS_DIR/StudioMDL-CE/x64/cestudiomdl.exe |
| GMOD_PYTHON_EXE | python；非 PATH 命令时请使用绝对路径 |

工具布局不同时直接填写对应变量。无需为了改 Lua 配置 GMod 安装路径。

## 按任务校验

```powershell
pwsh -File scripts/check_environment.ps1 -Task lua
pwsh -File scripts/check_environment.ps1 -Task scan
pwsh -File scripts/check_environment.ps1 -Task decompile
pwsh -File scripts/check_environment.ps1 -Task compile -Compiler ce-x64
pwsh -File scripts/check_environment.ps1 -Task model -RequireBlender
```

Windows PowerShell 可将 `pwsh` 替换为 `powershell`。可传 `-EnvFile` 与 `-AddonRoot`。

所有任务检查目标 addon 目录及基础布局；scan 额外运行 Python 版本检查（3.9+）；decompile 检查 Crowbar CLI 文件；compile 检查所选编译器及游戏内容目录。GUI Crowbar 路径只供人工操作，不视为 CLI 可用。

输出 JSON，成功退出码 0，失败为 1。工具文件检查通过不表示可启动、版本兼容或功能通过；实际调用时仍需检查退出码和输出。此校验不安装工具、不扫描模型、不启动游戏，也不替代 bodygroup 或游戏实测。model 同时检查反编译与编译前提；-RequireBlender 额外检查 BLENDER_EXE 文件。已有源工程时按实际需要单独选择 compile，不要求反编译工具。当前 skill 仍未附带 MDL 扫描器。

模型制作入口见 [独立装备提取](equipment-props.md) 与 [分组拆分](bodygroup-split.md)。BLENDER_EXE 必须按实际安装填写；Source Tools 的启用和导入/导出应实际验证。GMOD_SKILL_ARTIFACTS_DIR 默认指向 skill 根目录的 artifacts，可覆盖为项目构建目录，构建备份不随 addon 发布。
