---
name: split-player-model-bodygroup
description: 仅针对 Garry's Mod 玩家模型，把一个复合 bodygroup（例如左右鞋）拆成两个独立 bodygroup，完成 SMD 网格分离、QC 修改、studiomdl 编译、验证与 Lua 槽位同步。
---

# 玩家模型 Bodygroup 拆分（左右鞋）

## 用途与边界

本流程只处理 **玩家模型** 的 bodygroup 拆分，典型需求是：

> 原模型只有 `脚部-鞋子` 一个 bodygroup，希望拆成 `脚部-鞋子L` 和 `脚部-鞋子R`，让左右鞋可以独立显示、隐藏、掉落和拾取。

### 本 skill 只做

- 反编译玩家模型。
- 找到目标复合 bodygroup 对应的 SMD。
- 将一个 SMD 拆成左右两个 SMD。
- 修改玩家模型 QC，增加两个 bodygroup。
- 保留原有全部 bodygroup，不丢失皮肤、表情、材质和动画。
- 编译、验证玩家模型；发布按用户授权执行。
- 如果项目 Lua 使用这些 bodygroup，同步槽位和状态键。

### 本 skill 不做

- 不处理 NPC 模型；除非用户另行明确要求。
- 不制作独立掉落 prop；那属于 `equipment-props.md`。
- 不额外实现掉落、拾取、伤害触发；那属于 `../SKILL.md`。
- 不在未要求时执行 addon 发布；发布属于 `delivery.md`。

如果用户同时要求 NPC、独立 prop、掉落 Lua 或发布，再读取对应 reference。

## 严格执行流程

```text
步骤 1 → 读取项目和现有模型/Lua
步骤 2 → agent 读取成品实际 bodygroup 表，游戏接口可用时交叉验证
步骤 3 → 确认目标复合 bodygroup、状态数和左右方案
步骤 4 → 备份玩家模型文件
步骤 5 → 用 Crowbar 反编译玩家模型
步骤 6 → 分析目标 SMD 的网格连通分量和左右方向
步骤 7 → 用代码拆分 SMD，并用 Blender 复核
步骤 8 → 修改 QC：恢复 bodygroup 名称并替换成左右两个 bodygroup
步骤 9 → 处理 VTA/表情和材质上限问题
步骤 10 → 选择正确编译器并编译玩家模型
步骤 11 → 反编译或解析 MDL 验证 bodygroup 和皮肤
步骤 12 → 游戏内验证
步骤 13 → 如 Lua 使用 bodygroup，同步槽位
步骤 14 → 用户要求发布时才执行发布
```

任何一步无法确认时，不要继续覆盖原模型。

## 步骤 1：读取项目

至少读取：

- 项目根目录的 `AGENTS.md`、`README.md`。
- `lua/autorun/` 下所有 Lua。
- `models/` 目录。
- `materials/` 目录。
- 现有掉落脚本中的模型路径、bodygroup、骨骼、槽位和状态键。

必须从项目中确认：

| 项目 | 要求 |
|---|---|
| 玩家模型 | 实际 `.mdl` 路径 |
| 目标 bodygroup | 实际名称，不能照抄示例 |
| 掉落物模型 | 如果 Lua 已引用，记录左右 prop 路径 |
| 骨骼 | 左右脚/目标部件实际骨骼名 |
| Lua 槽位 | `NET_SLOTS`、`SLOT_LIST`、`RegisterSlot` |
| 发布路径 | 默认为 `.env` 中 `GMOD_ADDONS_DIR` 下的目标 addon 目录 |

不要把 NPC 模型加入本任务，除非用户明确要求。

## 步骤 2：获取真实 bodygroup 列表

agent 直接解析成品 MDL 的 bodypart/submodel，保存组名、顺序、状态数、各态网格/blank，并结合 QC/SMD 和 Lua 确认语义。连接游戏时自行交叉验证当前实体状态；不要求用户手动提取分组。当前状态值不是状态总数，默认态也不保证为0。缺少模型时询问资源位置即可。

后续 QC 和 Lua 映射以此表为准，按名称核对，不能把另一版本的索引直接复制过来。

## 步骤 3：确认拆分方案

确认表格至少包含：

| 项目 | 值 |
|---|---|
| 玩家模型 | 实际路径 |
| 原 bodygroup | 例如 `脚部-鞋子` |
| 新 bodygroup L | 例如 `脚部-鞋子L` |
| 新 bodygroup R | 例如 `脚部-鞋子R` |
| 原状态 | 例如 `0=穿，1=隐藏` |
| 左右鞋是否独立 | 是/否 |
| 左右是否一起掉落 | 是/否 |
| 是否同步 Lua | 是/否 |

关键原则：

- 如果目标只是“视觉上左右独立”，必须真正拆分 SMD 和 bodygroup。
- 如果左右共用一个 bodygroup，Lua 即使分成两个槽位，也无法只隐藏其中一侧。
- bodygroup 新增后，后续 bodygroup 的运行时索引会整体后移；Lua 应优先按名称查找，不要硬编码旧索引。

## 步骤 4：备份玩家模型

编译前备份玩家模型目录中所有运行文件：

- `.mdl`
- `.vvd`
- `.vtx`
- `.phy`

建议放到 `.env` 中 `GMOD_SKILL_ARTIFACTS_DIR` 下的 `backup_模型名/`，不要发布备份。

如果玩家模型正在被 GMod 使用，先关闭 GMod 或准备替换后重启，避免文件锁。

## 步骤 5：用 Crowbar 反编译玩家模型

共享工具路径来自 `.env` 的 `CROWBAR_EXE`：

```text
CROWBAR_DIR/Crowbar.exe
```

输出建议：

```text
GMOD_SKILL_ARTIFACTS_DIR/decompiled/玩家模型名/
```

反编译时注意：

1. 输入必须是玩家模型，不要误选 NPC 模型。
2. 输出模式使用 `Folder`。
3. 等待 QC 和所有 SMD 都写入完成。
4. 不要看到第一个文件出现就终止 Crowbar。
5. 大模型可能需要数分钟；以文件数量稳定为准。
6. 检查 QC 中是否包含 `flexfile`、`$texturegroup`、所有 `$bodygroup` 和动画引用。

在 QC 中找到目标：

```qc
$bodygroup "脚部-鞋子"
{
    studio "Shoes.smd"
    blank
}
```

如果 Crowbar 把中文 bodygroup 名称导出成 `??????`，这是编码丢失，不是模型真实名称。必须使用步骤 2 的游戏内列表恢复。

## 步骤 6：分析 SMD 左右网格

### 6.1 统计连通分量

读取目标 SMD 的 `triangles` 区，按顶点位置构建连通分量，输出：

- 三角面数量。
- 材质。
- 每个连通分量的包围盒。
- X/Y/Z 范围。

如果左右鞋是分离网格，通常会出现左右对称的两组连通分量。

### 6.2 判断哪一侧是左/右

不要只凭 `left/right` 文件名猜方向。优先使用以下证据：

1. 项目内已有的独立左鞋和右鞋 prop。
2. 将角色模型中的鞋网格与独立 prop 的三角面数量、包围盒、材质进行匹配。
3. 必要时计算角色骨架中左右脚的世界方向。

本项目实测数据可作为示例，不能照抄到其他模型：

| 网格 | 三角面 | X 范围 |
|---|---:|---|
| 角色左鞋 | 7804 | `0.848 ~ 4.707` |
| 角色右鞋 | 7804 | `-4.707 ~ -0.848` |
| 独立左鞋 prop | 7804 | 正 X |
| 独立右鞋 prop | 7804 | 负 X |

结论必须能被面数、包围盒和独立 prop 同时支持。

## 步骤 7：拆分 SMD

### 7.1 推荐方式：用代码按连通分量/坐标拆分

代码方式比手动在 Blender 中选择网格更快，也更容易复现：

1. 保留原 SMD 的 `version`、`nodes`、`skeleton`。
2. 保留每个三角面的材质行和三条顶点行。
3. 按连通分量或可靠坐标规则分成 L/R。
4. 分别写成 `Shoes_L.smd`、`Shoes_R.smd`。
5. 不修改顶点坐标，不重新居中，不应用变换。
6. 输出后重新统计面数，确保 L+R 等于原面数。

### 7.2 Blender 只用于复核

使用 Blender Source Tools 导入拆分结果，检查：

- 每侧对象数量。
- 顶点数和面数。
- 包围盒。
- 材质槽。
- 是否只包含目标部件。

Blender 不是替代代码拆分的必选步骤；如果代码已正确，Blender 复核即可。

### 7.3 禁止操作

- 不要移动顶点到世界原点。
- 不要缩放、旋转或应用变换。
- 不要丢弃骨骼权重。
- 不要把 L/R 合并后再用 bodygroup 掩盖。
- 不要删除原 `Shoes.smd` 之前先确认 QC 已不再引用它。

## 步骤 8：修改 QC

修改目标玩家模型 QC。

### 8.1 恢复所有中文 bodygroup 名称

按游戏内 bodygroup 列表逐项恢复，确保没有：

```qc
$bodygroup "??????"
```

### 8.2 替换复合 bodygroup

将：

```qc
$bodygroup "脚部-鞋子"
{
    studio "Shoes.smd"
    blank
}
```

替换为：

```qc
$bodygroup "脚部-鞋子L"
{
    studio "Shoes_L.smd"
    blank
}

$bodygroup "脚部-鞋子R"
{
    studio "Shoes_R.smd"
    blank
}
```

要求：

- 两个新 bodygroup 放在原 bodygroup 的位置。
- 保留原 bodygroup 之后的所有 bodygroup。
- 只增加一个 bodygroup；总数应从 N 变为 N+1。
- 不能删除 `$texturegroup`、表情、动画、attachment、hitbox 或 `$collisionmodel`。

### 8.3 检查引用

确认：

- `Shoes_L.smd`、`Shoes_R.smd` 存在。
- QC 不再引用已废弃的 `Shoes.smd`，或保留它是有意的。
- 所有 QC 引用文件都存在。
- 动画子目录路径正确。

## 步骤 9：处理表情 VTA 和材质上限

### 9.1 Crowbar VTA 导致 studiomdl 崩溃

如果原始 QC 有：

```qc
flexfile "xxx.vta"
```

且当前 studiomdl 在读取 VTA 时崩溃，可使用 Blender Source Tools：

1. 导入 `body.smd`。
2. 导入 VTA。
3. 让 shape keys 落到参考网格。
4. 重新导出干净的 VTA。
5. QC 改为引用新的 VTA。

导入时关注：

- 未匹配 VTA 顶点。
- shape key 数量。
- 是否生成无多边形的临时 `VTA vertices` 对象；导出时不要导出该对象。

### 9.2 特殊 flex 名称

当前 studiomdl 可能无法解析包含以下字符的 flex/controller：
- `^`
- `><`
- `--`
- 大小写不一致

可在 QC 中改成安全名称，例如：

| 原名称 | 安全名称 |
|---|---|
| `mouth_^` | `mouth_hat` |
| `eyebrow_><` | `eyebrow_angle` |
| `eyebrow_--` | `eyebrow_dash` |
| `><` | `face_angle` |

必须同时修改：

- `flexfile` 内的 `flex` 名称。
- `flexcontroller` 名称。
- `%` 映射。
- VTA/Blender 导出结果中必要的对应名称。

### 9.3 材质和 skin-tools 上限

GMod 自带 studiomdl 常见报错：

```text
Too many materials used, max 64
UseTextureAsMaterial() - overflowed MAXSTUDIOSKINSTOOLS
```

这通常与拆分 bodygroup 无关；不拆分的原 QC 也可能失败。

不要：

- 直接删除 `$texturegroup`。
- 丢失白色、紫色等已有皮肤。
- 二进制暴力修改 GMod 自带 studiomdl 的判断指令。

原因是 `MAXSTUDIOSKINS` / `MAXSTUDIOSKINSTOOLS` 往往对应固定数组和内存布局，只改比较值可能造成越界。

推荐使用社区编译器：

[StudioMDL-CE](https://github.com/DeadZoneLuna/StudioMDL-CE)

其文档说明：

- 面向 Source Filmmaker 和 Garry's Mod。
- 材质上限提高到 128。
- 提供 Windows x86/x64。
- 去除多项 flex、顶点和缓冲限制。

使用时：

1. 工具路径来自 `.env`：

   ```text
   STUDIOMDL_CE_X64_EXE
   STUDIOMDL_CE_X86_EXE
   ```

   exe 必须和同目录 DLL 放在一起。
2. 不要把编译器发布进 addon。
3. 优先使用 x64 处理大模型。
4. 下载后先确认主程序和依赖 DLL 文件大小非零。
5. 编译前保留原模型备份。

### 9.4 MDL 版本兼容

StudioMDL-CE 当前可能输出 MDL `version 49`，GMod 自带编译器常见输出为 `version 48`。

CE 的 changelog 仍把“输出 47/48 以保持向后兼容”列为 TODO。因此编译成功不等于 GMod 一定能加载。

最终必须在游戏中验证模型加载；若 GMod 不接受 version 49，不要强行覆盖原模型，应回退备份并重新评估编译方案。

## 步骤 10：编译玩家模型

编译前检查：

- [ ] 备份已完成。
- [ ] QC 只修改目标玩家模型。
- [ ] 所有 SMD/VTA/动画文件存在。
- [ ] bodygroup 名称不是 `??????`。
- [ ] L/R 面数总和正确。
- [ ] `$texturegroup` 未被无故删除。
- [ ] 使用了能通过材质上限的编译器。
- [ ] 没有把 NPC 模型混入本任务。

成功标准：

- 编译器输出 `Completed "...qc"`。
- 生成 `.mdl`。
- 生成 `.vvd`。
- 生成 `.vtx`。
- 生成 `.phy`。
- 没有 `ERROR`。

注意：

- StudioMDL-CE 可能只写 `dx90.vtx`。
- 如果目标目录残留旧编译器的 `dx80.vtx`，要确认是否应删除，避免新旧网格混用。
- 不要把测试输出目录发布到 addon。

## 步骤 11：验证编译结果

### 11.1 解析 MDL header

至少读取：

- `version`
- `numtextures`
- `numskinref`
- `numskinfamilies`
- `numbodyparts`

验证：

- 皮肤数量与原 QC `$texturegroup` 行数一致。
- bodypart 数量相对原模型增加 1。
- 左右鞋 bodygroup 名称以 UTF-8 存在于 MDL。
- 原有蝴蝶结等 bodygroup 仍存在。

### 11.2 Crowbar 反编译复核

重新反编译新 `.mdl`，检查 QC：

```qc
$bodygroup "脚部-鞋子L"
{
    studio "Shoes_L.smd"
    blank
}

$bodygroup "脚部-鞋子R"
{
    studio "Shoes_R.smd"
    blank
}
```

还要检查：

- 未出现 `??????` 以外的意外名称丢失。
- `$texturegroup` 行数正确。
- 所有 bodygroup 仍存在。
- 表情和动画仍在。

### 11.3 Blender 复核

再次导入 L/R SMD：

- 面数正确。
- 包围盒左右对称。
- 材质正确。
- 没有被重新居中。

## 步骤 12：GMod 内验证

重启 GMod 或换图，然后执行：

```lua
lua_run local p=player.GetAll()[1] for i=0,80 do local n=p:GetBodygroupName(i) if n then print(i,n,p:GetBodygroup(i)) end end
```

验证：

- 新 L/R bodygroup 出现。
- 原 bodygroup 顺序变化符合预期。
- 模型可见、无粉红材质。
- 表情正常。
- 动画正常。
- 白色/紫色皮肤可切换。
- NPC 未被修改。
- 没有编译版本不兼容错误。

## 步骤 13：同步 Lua（仅在项目使用 bodygroup 时）

如果掉落脚本使用这些 bodygroup，必须同步：

### 状态模块

```lua
local NET_SLOTS = { "Shoe_L", "Shoe_R" }
```

### 客户端

```lua
local SLOT_LIST = { "Shoe_L", "Shoe_R" }

local SLOT_BG = {
    Shoe_L = "脚部-鞋子L",
    Shoe_R = "脚部-鞋子R",
}
```

### 服务端注册

```lua
EQ.RegisterSlot("Shoe_L", "脚部-鞋子L", 1, 1)
EQ.RegisterSlot("Shoe_R", "脚部-鞋子R", 1, 1)
```

`maxState` / `dropState` 必须来自真实状态数。

必须检查：

- `NET_SLOTS` 与 `SLOT_LIST` 逐项一致。
- 两个 bodygroup 名称与游戏内输出一致。
- 左右骨骼分别使用真实 L/R 骨骼。
- 概率、掉落、拾取是否需要独立。
- `UnregisterDrop` 在 `SafeRemoveEntity` 之前。
- 日志受 ConVar 控制。
- 不注册 NPC，除非用户要求。

如果用户只要求模型拆分，不要额外修改掉落逻辑。

## 关键坑点

1. **只处理玩家模型**：不要顺手改 NPC；用户未要求时，NPC 必须保持不变。
2. **中文名称不能靠 Crowbar**：Crowbar 可能把中文导出为 `??????`，必须用游戏内 bodygroup 列表恢复。
3. **不要过早终止 Crowbar**：第一个文件出现不代表全部 SMD 完成。
4. **不要凭文件名判断左右**：必须用面数、包围盒和独立 prop 对照。
5. **不要重新居中**：顶点坐标、骨骼权重和原点必须保持。
6. **不要丢 bodygroup**：新增 L/R 后，原蝴蝶结、装饰、服装 bodygroup 必须保留。
7. **两个槽位不能共用一个视觉 bodygroup**：否则无法独立隐藏。
8. **固定上限不能只改比较指令**：GMod studiomdl 的材质/skin-tools 可能关联固定数组。
9. **完整皮肤优先**：不要为了编译通过随意删 `$texturegroup`。
10. **MDL version 要实测**：CE 的 version 49 必须通过 GMod 加载验证。
11. **新旧 vtx 不混用**：清理与新编译器不匹配的旧 `.dx80.vtx`。
12. **先备份再覆盖**：编译失败时必须能回滚。
13. **测试目录不发布**：`artifacts`、反编译结果、CE 编译器均不进入 addon。
14. **发布是独立步骤**：只有用户明确要求时才读取并执行 `delivery.md`。

## 交付前检查清单

- [ ] 只修改了玩家模型，没有修改 NPC。
- [ ] 读取了游戏内真实 bodygroup 列表。
- [ ] 原玩家模型已备份。
- [ ] Crowbar 已完整反编译。
- [ ] 目标 SMD 左右连通分量已分析。
- [ ] L/R 三角面总和等于原网格。
- [ ] Blender 已复核面数、包围盒、材质和权重。
- [ ] QC 中所有中文 bodygroup 名称已恢复。
- [ ] 复合 bodygroup 已替换成 L/R 两个 bodygroup。
- [ ] 原有全部 bodygroup 均保留。
- [ ] `$texturegroup` 和完整皮肤保留。
- [ ] 表情 VTA 可编译。
- [ ] 使用了不会触发 64 材质上限的编译器。
- [ ] 编译输出无 `ERROR`。
- [ ] `.mdl/.vvd/.vtx/.phy` 齐全。
- [ ] 旧的不匹配 `.dx80.vtx` 已处理。
- [ ] MDL header 的 skin/bodypart 数量正确。
- [ ] 反编译 QC 中 L/R bodygroup 正确。
- [ ] GMod 内模型可加载。
- [ ] 所有原 bodygroup 可见。
- [ ] 白色/紫色皮肤正常。
- [ ] Lua 的 `NET_SLOTS`、`SLOT_LIST`、`SLOT_BG` 一致（如需要）。
- [ ] 未执行未要求的 NPC 修改、prop 制作或发布。
