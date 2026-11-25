# GMod Skills

面向 Garry's Mod 开发的独立 AI skills 集合，每个 skill 可单独安装。

## 技能目录

| Skill | 用途 | 依赖 |
|---|---|---|
| [gmod-equipment-drops](skills/gmod-equipment-drops/SKILL.md) | 装备掉落、拾取、状态同步，支持左右独立和多装备 | 目标 addon 与实际玩家模型；缺独立 prop 时需相应提取及编译工具；游戏运行需要 Garry's Mod |

掉落 skill 提供工作流和 GLua 参考模板，并非开箱即用的游戏 addon。缺少独立装备 prop 时，包含从已有模型提取、制作碰撞和编译的流程；必要时拆分人物装备 bodygroup。不附带通用生成器、第三方工具二进制或模型资产。眼镜景深与外部插件适配按需求启用。

## 安装

将所需的 `skills/<skill-name>` 整个文件夹复制到个人 `~/.agents/skills/` 或项目 `.agents/skills/` 下。Windows 个人目录例如 `%USERPROFILE%\.agents\skills\gmod-equipment-drops`。

也可让 Codex 的 `$skill-installer` 从本仓库安装，并指定 `skills/gmod-equipment-drops` 路径。不要把整个多 skill 仓库当作一个 skill 安装。

## 环境配置

掉落 skill 附带 `.env.example`、路径加载脚本和按任务校验入口。安装后按[环境配置说明](skills/gmod-equipment-drops/references/environment.md)设置本地 `.env`；可指定共享工具目录或覆盖单个工具路径。本机配置不提交 Git。

## 使用示例

```text
使用 $gmod-equipment-drops，为这个 addon 的玩家模型添加眼镜爆头掉落和拾取。
先读取实际模型、bodygroup、骨骼及装备 prop，再适配脚本。
```

```text
使用 $gmod-equipment-drops，排查左右鞋掉落后隐藏错误部位的问题，
检查槽位顺序、bodygroup 映射和客户端快照。
```

## 目录与维护

每个 skill 以 `skills/<skill-name>/SKILL.md` 为入口，所需参考、脚本或资源放在自身目录中，不跨 skill 引用相对路径。只创建实际需要的目录。新增 skill 时同步更新上方目录。

模型、贴图、第三方商业资产和本地工程产物不默认随仓库分发。

## 验证范围

当前为独立迁移候选：保留已有 Lua 参考代码，调整入口、文档依赖与安装说明，并迁入独立装备提取和 bodygroup 拆分参考。迁移检查覆盖 skill 元数据、内部链接、Lua 代码块一致性和本地路径残留；不代表已在所有游戏模式中验证。生成到具体 addon 后，仍需按 skill 验证清单复测。

## 许可证

本仓库采用 [GNU AGPL v3.0](LICENSE)（SPDX：AGPL-3.0-only）。第三方材料如有单独声明，按其原许可证执行。
