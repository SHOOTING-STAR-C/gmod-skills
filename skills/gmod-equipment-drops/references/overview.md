返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。


# GMod 装备掉落/拾取系统生成器 (v15)

导航见 [掉落系统入口](../SKILL.md)。

## 用途

为任意 GMod playermodel 生成完整的装备掉落/拾取 Lua autorun 脚本。用户只需提供物品配置，skill 生成可直接使用的 Lua autorun 脚本。

> **配套效果**：如果掉落的是**眼镜**，可以再配一个「掉了之后画面变模糊」的景深效果；
> 步骤、模板和检查项见同目录的 [DOF 参考](glasses-dof.md)。

## ⚠ 严格执行流程（所有模式必须按顺序完成，不可跳步）

```
步骤 1 → 扫描目录，获取所有 .mdl 模型路径
步骤 2 → 识别角色模型（pm/ npc/）和掉落物模型（shoes/ arms/）
步骤 3 → agent 直接读取成品 MDL 的 bodypart/submodel，结合 QC/SMD 和 Lua 确认分组
步骤 4 → 生成分组名称、状态数、状态语义及实际子网格对应表
步骤 5 → 生成确认表格：每个部位的模式、触发方式、概率 ConVar、默认值
步骤 6 → 沿用已确定的方案；仅未明确且影响行为的选择需询问
步骤 7 → 创建或编辑 3 个文件，写入下面约定的路径
步骤 8 → 告知用户文件已生成，提醒检查
```

**每一步都必须完成才能进入下一步，不可跳过。**

## ⚠ 严格生成规则（所有模式必须遵守）

1. **模板是基础实现**：保留状态权威、同步、概率和回滚不变量；按实际模型和需求适配。旧单件模板与多装备扩展冲突时，读取多装备规则并统一实现，不能逐行照抄后拼接。
2. **坑点全部应用**：生成前逐条检查「关键坑点」（18 条），每条都必须在生成代码中体现
3. **占位符必须替换**：`<MOD>`、`<前缀>`、`<maxState>`、`<dropState>` 等占位符必须替换为实际值，不允许保留任何 `<>` 占位符
4. **槽位顺序一致**：服务端 `NET_SLOTS` 与客户端 `SLOT_LIST` 必须逐项一致，改一边必须同步改另一边
5. **概率全部 ConVar**：所有概率必须通过 ConVar 在游戏中可调，不允许硬编码
6. **日志受 ConVar 控制**：`M.Log()` / `M.Warn()` 受 `<MOD>_Log` ConVar 控制，默认关闭

## ⚠ 文件输出路径（必须严格遵守）

**所有文件写入当前工作目录（addon 根目录）下的子目录。**

**目标 addon 根目录以用户指定或项目核实结果为准。** 当前目录不是目标 addon 时，显式切换或传入目标路径，不按启动目录猜测。

> ⚠️ 本文档里出现的任何具体路径、模块名、模型路径、ConVar 名都是**示例**，换一个项目就完全不同。
> **永远以实际工作目录为准** —— 不要照抄文档里的路径。走错目录会导致改了另一个 addon 的文件，
> 而用户测试的是他当前的项目，表现为「改了没反应」。

生成 3 个文件，写入以下路径：

| 文件 | 写入路径 | 说明 |
|---|---|---|
| 状态模块 | `lua/autorun/server/0_<mod>_State.lua` | `0_` 为组织约定，依赖需显式初始化 |
| 客户端同步 | `lua/autorun/client/0_<mod>_Client.lua` | client 目录无加载顺序，但保持命名一致 |
| 掉落脚本 | `lua/autorun/server/<name>.lua` | 字母开头，一定排在状态模块后面 |

**示例**（假设模块名 `MyMod`，脚本名 `Eyewear`）：

```
lua/autorun/server/0_MyMod_State.lua    ← 组织前缀，不能替代依赖初始化
lua/autorun/client/0_MyMod_Client.lua
lua/autorun/server/Eyewear.lua          ← 字母 E，排后面
```

**加载依赖**：可保留 `0_<mod>_State.lua` 等约定前缀以便组织，但字母序不保证跨 realm、热重载或第三方脚本的依赖就绪。依赖由实际 include/初始化流程保证；重复加载应幂等，调用前检查模块接口，避免用无界 timer 等待掩盖加载错误。

## 前置步骤：获取模型 bodygroup 信息

agent 自行获取分组信息，不要求用户提取 bodygroup 或回传控制台输出。

1. 从玩家模型注册和当前任务确定实际 MDL，区分玩家、NPC、手模和其他变体。
2. 直接解析成品 MDL 的 bodypart/submodel：名称、索引、状态数、每个状态的模型/空白状态；也可使用已有可靠反编译工具。以最终成品为准，QC/SMD 用于补充语义与几何来源。
3. 对照 Lua 默认值、菜单和生成器确认穿戴/隐藏/悬挂语义。0 不一定是穿戴态，blank 不一定是最后状态；不能按二态/三态数量自动认定含义。
4. 检查该状态是否混入联动机械身体、皮肤或其他衣物，确定掉落应隐藏/恢复哪些实际装备网格。缺独立装备模型时由 agent 从工程或精确编译输入制作，流程见 [独立装备模型](equipment-props.md)。
5. 输出事实表：模型路径、bg_name、实际索引、bg_states、每态语义、源子网格、掉落物路径、依据。运行端按名称查找并检查状态范围，不能跨模型复用编号。
6. 游戏已连接时由 agent 查询实际实体状态作交叉验证；没有游戏接口也可先完成静态读取和开发。只有缺失模型文件或无法推断用户想要的行为时才询问相应信息。

当前实体的 GetBodygroup 值只代表选中状态，不能用它当状态总数。不要再用“问玩家有几个值”替代成品解析。

### 确认掉落方案

读取实际分组后列出模式和概率表，沿用用户已确定的值；只有缺少影响行为的选择时才询问，不把生成表格当作重复审批要求。

**确认表格格式：**

```
根据 bodygroup 输出，确认以下掉落方案：

| 部位 | bg_name | 模式 | 触发方式 | 概率 ConVar | 默认值 |
|------|---------|------|---------|------------|--------|
| 耳机 | Headset | B | 爆头 | <前缀>_hp_Headshot | 0.4 |
|      |         |     | 死亡   | <前缀>_hp_Death    | 0.3 |
| 帽子 | Hat     | B | 爆头 | <前缀>_lt_Headshot | 0.4 |
|      |         |     | 死亡   | <前缀>_lt_Death    | 0.3 |
| 左鞋 | Shoe_L  | C(3态) | 伤害 | <前缀>_ExpP (L)  | 0.5 |
|      |         |     | 死亡   | <前缀>_DeathP (L)  | 0.15 |
| 右鞋 | Shoe_R  | C(3态) | 伤害 | <前缀>_ExpP (R)  | 0.5 |
|      |         |     | 死亡   | <前缀>_DeathP (R)  | 0.12 |

确认后开始生成。
```

方案已明确即可实现；用户后续调整时同步配置、文档与验证。

- 实体生命周期管理（重生时状态重置）
- 装备槽位注册和状态追踪
- 布娃娃绑定（死亡 → 布娃娃状态转移）+ `ApplyRagdollSnapshot`
- 地面掉落物追踪（`RegisterDrop` / `UnregisterDrop` / `HasDrop` / `FindDrop` / `GetDropInfo`）
- `CanRagdollEnterDropCheck(rag, slot)` — 检查 ragdoll 指定槽位是否处于可掉落状态
- `netRagdollSnapshot` — 服务器主动向客户端广播 ragdoll 状态
- Think hook 定时同步 bodygroup（每 0.1s）

## 用户输入

只需告诉 skill 你要做什么，大部分信息会自动推断：

```
用户只需说：
"给 xxx 模型生成眼镜掉落脚本" 或 "给这些模型加鞋子掉落"
```

### 自动推断规则

| 信息 | 自动推断方式 | 用户是否需要提供 |
|------|------------|----------------|
| 目标模型 | 扫描当前目录所有 .mdl 文件 | ❌ 自动 |
| 脚本名 | 根据物品类型生成（Eyewear/HeadGear/Footwear） | ❌ 自动 |
| 模块名 | 从目录名推断（如 `MyMod`） | ❌ 自动 |
| 骨骼名 | 从项目已有脚本查询 + 已知骨骼表 | ❌ 自动 |
| bg_name | 从目录中单独的掉落物模型文件名推断 | ⚠ 一般自动，新模型需确认 |
| bg_states | 读取实际 submodel 数与穿戴/隐藏状态，不预设编号 | ❌ agent 读取实际状态并确认语义 |
| itemType | 从 slot 名推断（Glasses/Headphone/Hat/Shoe） | ❌ 自动 |
| trigger | 从物品类型建议（眼镜→A, 耳机→B, 鞋→C） | ⚠ 建议后确认 |
| item_model | 从目录中查找对应掉落物模型 | ⚠ 一般自动 |

### bg_name 查找逻辑

1. 先在项目 `lua/autorun/server/` 下 grep 已有脚本，匹配相同模型的 `bg_name`
2. 再看目录中有没有单独的掉落物模型文件，但不要把文件名直接当成 bodygroup 名称
3. 都找不到 → 列出目录中的模型文件名，请用户确认

### 模型注册规则

只注册本任务目标模型及用户要求支持的变体，逐个验证装备语义和状态映射。NPC 不因目录存在而自动加入。手模、掉落道具不是穿戴生命周期主体；如需要客户端手模同步，使用明确的主模型映射。未知角色类型先从实际注册和用途核实，不凭目录名判断。

### bg_states 与状态映射

状态总数从成品读取；maxState 为状态总数减一。穿戴、悬挂、隐藏按实际网格和项目逻辑确定，dropState 不是固定编号。没有悬挂网格时不虚构悬挂态，也不要求用户手动提供状态信息。

### 用户需要提供的信息

用户指定目标模型与期望行为即可；项目已有模型、分组、工程和装备由 agent 自行读取。目标资源确实不在可访问位置时，请用户给出模型文件位置，不要求其先提取分组名称、状态数或独立零件。已有方案与授权继续有效。

## 三种触发模式

### 选型速查（先对表，再动手）

| | 模式 A | 模式 B | 模式 C |
|---|---|---|---|
| **触发条件** | 任意伤害 | 爆头 | 布娃娃部位伤害 |
| **部位判定** | 无 | 头部 14 单位 | 脚部 30 单位 |
| **L/R 配对** | ❌ | ❌ | ✅ |
| **中间态** | 无 | 无 | 有（悬挂，5 秒后自动掉） |
| **活体受伤时掉** | ✅ | ✅（仅爆头） | ❌ **完全不走活体** |
| **爆炸能触发** | ✅ | ❌ 被距离检测挡掉 | ❌ 同上 |
| **概率 ConVar** | 单个 `DropP` | 每物品 `_Headshot` / `_Death` | `"L,R"` 格式的 `ExpP` / `DeathP` |
| **实现复杂度** | 最低 | 中 | 最高 |

**按装备类型选：**

| 装备 | 模式 | 理由 |
|------|------|------|
| 眼镜、面罩、项链 | **A** | 单体装备，任意伤害就该掉 |
| 耳机、帽子、头盔 | **B** | 单体装备，想只在爆头时掉 |
| 鞋子、手套、护膝 | **C** | L/R 成对 + 想要"挂着晃一会儿再掉" |
| 成对手套 / 袖套（不要悬挂） | **C 简化版** | L/R 成对但不需要中间态 |

**拿不准就选 A** —— 最简单、最不容易出问题，且活体和布娃娃都覆盖。

### ⚠️ 三个模式都做不到的事（需要自行扩展）

**1. 模式 C 不支持活体受伤掉落**

C 的 4 个钩子全部只在布娃娃上工作。玩家**活着**被炸（没死）时，C 什么都不会做 —— 这是设计如此，不是配置问题。

要支持必须在 C 上补一个活体 `EntityTakeDamage` 分支，并且**必须**加 `if isRagdoll(ent) then return end` 过滤，否则同一发伤害会让布娃娃被两个钩子各处理一遍。

**2. 模式 B / C 的爆炸伤害会被部位距离检测挡掉**

爆炸的 `dmgInfo:GetDamagePosition()` 返回的是**爆炸中心**，不在头部 / 脚部附近，`dmgNearBone`（14 单位）或 30 单位判定会直接 `return` —— **概率代码根本执行不到**，这时候怎么调 ConVar 都没用。

要让爆炸也触发，需要加豁免：

```lua
if dmgInfo:IsDamageType(DMG_BLAST) then
    -- 跳过距离检测（爆炸判不出部位，通常随机选一侧）
else
    -- 原来的距离检测
end
```

**3. 三个模式都不会主动适配第三方手环**

只有目标项目已经安装手环 addon 且用户要求集成时，才读取 [可选外部集成](external-integrations.md)。

**4. 不带"掉落后的视觉 / 听觉反馈"**

比如眼镜掉了画面变糊、耳机掉了声音变小 —— 这类**客户端效果**不在本 skill 范围内。

### 配套效果：眼镜掉落景深（DOF）

如果掉落的装备是**眼镜**，可以配一个客户端 DOF 效果 —— 眼镜掉了之后玩家画面变模糊，视觉上提示"眼镜没了"。

详细步骤见 [DOF 参考](glasses-dof.md)。该参考会生成 `lua/autorun/client/0_<模块>_DOF.lua`，
并在服务端状态模块里加一行 `AddCSLuaFile`。

**它依赖本 skill 生成的状态模块**：DOF 脚本每帧读 `<前缀>_Live_<槽位>` 这个 NWInt，
状态模块在装备掉落时把它写成掉落态值，DOF 读到就开启模糊。

> ⚠️ 前提是目标项目**已有状态模块**。没有状态模块，DOF 脚本无从得知眼镜是否掉落。

### ⚠️ 模式 C 的概率是乘法叠加（最容易做成"几乎不掉"）

```
左鞋（先判定）= DeathP(L) × ExpP(L) × ExpP(L)
              = 0.15 × 0.5 × 0.5 = 3.75%    ← 先悬挂，5 秒后再 roll 一次

右鞋（后判定）= DeathP(R) × ExpP(R)
              = 0.12 × 0.5 = 6%             ← 悬挂位被左鞋占了，走直接掉落
```

**默认值体感上等于不掉。** 想让掉落明显可见，两个都拉高：

```
<前缀>_DeathP "1.0,1.0"
<前缀>_ExpP   "0.8,0.8"
```

> 第二只鞋天然少一层 roll —— 因为"悬挂位"只有一个。**左鞋的行为会改变右鞋的判定路径**：
> 左鞋先判定，若通过就占住悬挂位，右鞋只能走直接掉落；若左鞋没通过，右鞋就会成为"第一只"而去悬挂。
> 用户看到"左右掉率不一样"时，先想这条。

### 模式 A: any_damage（任意伤害掉落）

**适用**: 眼镜、面罩、项链等轻型装备
**物品参数**: 掉落概率通过 ConVar `<前缀>_DropP` 在游戏中修改（默认 0.10）
**钩子链**:
- `EntityTakeDamage` (活体) → 概率掉落，**必须** `if isRagdoll(ent) then return end` 过滤
- `EntityTakeDamage` (布娃娃) → 概率掉落
- `CreateEntityRagdoll` → `ApplyRagdollSnapshot` + restore

### 模式 B: headshot（爆头掉落）

**适用**: 耳机、帽子、头盔等头部装备
**物品参数**: `rag_head_r`（头部检测半径，默认14）。爆头概率通过 ConVar 在游戏中修改。
**钩子链**:
- `ScalePlayerDamage` / `ScaleNPCDamage` (活体) → `hitgroup == HITGROUP_HEAD` 检查
- `EntityTakeDamage` (布娃娃) → `dmgNearBone` 距离检测 + 概率
- `CreateEntityRagdoll` → `ApplyRagdollSnapshot` + restore

### 模式 C: ragdoll_proximity（布娃娃区域伤害）

**适用**: 鞋子、手套、护膝等成对物品
**物品参数**: 概率通过 ConVar 在游戏中修改（格式 `"L值,R值"`）：
- `<前缀>_ExpP`（伤害掉落概率，默认 `"0.50,0.50"`）
- `<前缀>_DeathP`（死亡掉落概率，默认 `"0.15,0.12"`）
**特殊**: 支持 L/R 配对、3 状态机（0=佩戴 → 1=悬挂 → 2=地面）、5 秒自动掉落定时器
**钩子链**:
- `EntityTakeDamage` (布娃娃) → 骨骼距离检测 → 悬挂/掉落
- `DoPlayerDeath` / `OnNPCKilled` → 保存攻击者速度
- `PostPlayerDeath` → 补充 ragdoll 绑定
- `CreateEntityRagdoll` → `ApplyRagdollSnapshot` + 状态机初始化

## 关键 API 速查

```lua
-- 注册
<MOD>.RegisterModel(modelPath)                          -- 注册目标模型
<MOD>.RegisterSlot(slot, bgName, maxState, dropState)   -- 注册槽位

-- 活体状态
<MOD>.Get(ent, slot) → number                           -- 获取当前状态
<MOD>.Set(ent, slot, state) → bool                      -- 设置状态
<MOD>.GetLife(ent) → number                             -- 获取当前生命周期ID

-- 布娃娃状态
<MOD>.ApplyRagdollSnapshot(rag, source) → bool           -- 绑定+同步+广播
<MOD>.GetRagdoll(rag, slot) → number
<MOD>.SetRagdoll(rag, slot, state) → bool                -- 自动广播快照
<MOD>.GetRagdollAll(rag) → table

-- 掉落物管理
<MOD>.RegisterDrop(owner, slot, dropEnt, lifeID) → bool
<MOD>.UnregisterDrop(dropEnt)
<MOD>.HasDrop(owner, slot, lifeID) → bool
<MOD>.FindDrop(owner, slot, lifeID) → Entity|nil
<MOD>.GetDropInfo(dropEnt) → owner, slot, lifeID

-- 新增
<MOD>.CanRagdollEnterDropCheck(rag, slot) → bool
  -- 鞋子: bg == 0 或 1 时返回 true
  -- 其他: bg == 0 时返回 true
  -- 用途: 掉落前检查 ragdoll 是否处于可掉落状态，防止重复掉落
```



