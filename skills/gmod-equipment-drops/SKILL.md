---
name: gmod-equipment-drops
license: AGPL-3.0-only
description: 为 Garry's Mod 已有玩家模型适配装备掉落、拾取与状态同步，支持任意伤害、爆头、尸体区域伤害及左右独立多装备。用于生成、修改或排查相关 GLua；缺少独立道具时从已有模型提取、编译，并按需拆分装备 bodygroup；不处理从零制作整个人物。
---

# GMod 装备掉落与拾取

根据目标 addon 的实际模型和需求适配 GLua。技能包含参考模板，不是可直接安装到游戏的 addon，也不附带通用扫描器或一键生成器。

## 执行关口

开始实现前读[实现与验证关口](references/workflow-gates.md)，保留实际输入、状态方案、行为测试和部署核对证据。新建/重构走完整流程；局部修复只走相关步骤和回归。

尸体必须绑定创建时的生命记录，不能借用玩家当前生命；每生命每槽位最多一个有效掉落物，生成、隐藏与拾取使用同一权威状态。左右骨骼分别核实，缺失时跳过并报告，禁止回退实体原点。核实实际尸体创建入口，不假定第三方插件使用标准 hook。模板可等价实现，但不能省略这些行为。

静态检查、Lua 状态测试、源/部署哈希一致性、真实游戏验证分别报告；缺少证据就标记未验证，不以增加 Think 覆写或文字清单代替行为验证。

## 环境准备

先按 [环境配置与校验](references/environment.md) 加载目标 addon 和工具目录。运行与当前任务对应的 `scripts/check_environment.ps1`；只改 Lua 不要求模型工具链。配置文件仅保存在本地，不打包进 addon。

## 先确定输入

确定目标 addon 根目录、当前实际注册的玩家模型、已有脚本与生成入口。读取成品 MDL、QC/SMD 或已连接游戏，记录 bodygroup 名称、索引、状态语义、骨骼、独立装备 prop 路径和 skin 对应。只处理本次要求支持的模型；不自动添加 NPC 或其他变体。

模型输入和资源缺失处理见 [模型契约](references/model-contract.md)。不能按文件名、二态/三态数量或示例数值猜测实际语义。已有授权与已核实输入可以沿用，仅缺少关键资源或行为选择时询问。

## 缺少独立模型或分组时

已有独立装备 prop 时直接检查复用；缺失时读取 [独立装备提取](references/equipment-props.md)，优先使用已有 QC/SMD/Blender 工程，必要时反编译当前实际 MDL，提取网格、保留材质与 UV、处理原点和碰撞，隔离编译并回读成品后接入掉落逻辑。不能仅记录缺失后就结束任务。

原人物分组不能独立控制所需装备（例如左右鞋共组）时，另读 [bodygroup 拆分](references/bodygroup-split.md)，同步修改人物模型和 Lua。保留完整皮肤、其他分组、表情、材质及动作，沿用已确定的模型名与运行路径；不擅自重命名玩家模型。

按实际执行步骤分别运行 decompile、compile 校验，或用 model 一次检查反编译与编译前提；已有源工程时无需强制反编译。需要 Blender 编辑或复核时加 -RequireBlender，并实际确认 Source Tools 可导入/导出，文件存在不能替代插件可用性检查。真实资源或工具缺失时说明具体阻塞，不伪造模型或验证结果。

## 选择并适配实现

1. 读 [配置与模式](references/overview.md)，记录槽位、触发方式、概率和默认状态。
2. 读 [共享状态](references/state-template.md)、[客户端同步](references/client-template.md) 和 [脚本结构](references/script-structure.md)。状态模块、事件处理与客户端一起适配，依赖通过实际初始化保证，不依赖文件名字母序。
3. 按需求选择 [A 任意伤害](references/mode-a.md)、[B 爆头](references/mode-b.md) 或 [C 尸体区域伤害](references/mode-c.md)。不同装备确需不同模式时共享同一状态权威，避免重复 hooks 或竞争处理。
4. 多部件、左右独立或共享事件预算时，加读 [多装备规则](references/multi-equipment.md)。它是旧单件模板之上的扩展，冲突处统一实现，不机械拼接。
5. 需要眼镜景深时读 [DOF](references/glasses-dof.md)；确有目标插件与集成需求时读 [外部集成](references/external-integrations.md)。默认不依赖第三方手环或布娃娃插件。

保留原有玩家选择与完整皮肤可见性。掉落只控制目标装备；不通过隐藏皮肤解决穿模。不擅自重命名已有模型或改变运行路径。

## 验证与交付

按 [验证与坑点](references/validation.md) 检查状态、槽位顺序、重复事件、生成失败回滚、拾取、死亡、重生、换模与清理。优先运行项目已有的相关测试；Lua/GLua 执行结果与静态文本检查分别报告，不能混称游戏验证。没有游戏连接也可完成静态开发，明确留下最小实机复测步骤。

API 签名或 realm 不确定时查 [Garry's Mod Wiki](https://wiki.facepunch.com/gmod/)，不假设安装了本地 API 数据库或专用工具。

按 [交付约定](references/delivery.md) 输出实际 Lua、使用说明及验证范围。若项目已有生成器，同步修改生成入口，避免下次构建覆盖修复。

