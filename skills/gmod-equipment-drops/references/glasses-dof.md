# GMod 眼镜掉落景深生成器 (v1)

## 用途

生成「眼镜掉落 → 画面景深模糊」的客户端脚本。装备掉落时施加 DOF 模糊，提示玩家眼镜没了。

## 第一步：读取目标项目的实际值

**不要照抄下表里的示例值** —— 那些是写这份文档时那个 addon 的值，换个项目就完全不同。

先扫描**目标项目**（用户当前工作目录）的代码，把这张表填出来。**每一项都必须有实际出处**：

| 项目 | 示例值（仅供参考） | 从目标项目的哪里读 |
|------|------------------|------------------|
| 槽位名 | `Glasses` | 掉落脚本里 `RegisterSlot(SLOT, ...)` 的 `SLOT` |
| 状态模块前缀 | `<模块前缀>` | 状态模块里 `ent:SetNWInt("<前缀>_Live_" .. slot, ...)` |
| NWInt 键 | `<前缀>_Live_<槽位>` | 由上面两项拼出来 |
| 掉落态值 | `1` | `RegisterSlot(..., maxState, dropState)` 的 `dropState` |
| bodygroup | `<游戏内bodygroup名称>` | `RegisterSlot(slot, BG_NAME, ...)` 的 `BG_NAME` |
| 目标模型 | `models/vrc/xxx.mdl`<br>`models/vrc/xxx_npc.mdl` | 掉落脚本的 `MODELS` 表 |
| ConVar 名 | `<前缀>_<槽位缩写>_DOF_Enabled` | 本 skill 新定义 |
| 脚本路径 | `lua/autorun/client/0_<模块>_DOF.lua` | 本 skill 新定义 |
| 服务端注册 | 状态模块里的 `AddCSLuaFile(...)` | 要往这个文件里加一行 |

> ⚠️ **换项目时不要臆造这些值**，每一项都要从目标项目代码里读出来。
> 槽位名读错（比如实际是 `GL` 却写成 `Glasses`）会让 NWInt 键对不上，
> 脚本**静默失效且不报错** —— 表现是"装上了但完全没效果"。

## 执行流程

```
步骤 1 → 确认目标（默认即为上表的眼镜配置）
步骤 2 → 若脚本已存在，读取现有文件，只做必要修改
步骤 3 → 写入 lua/autorun/client/0_<模块>_DOF.lua
步骤 4 → 确认服务端状态模块已 AddCSLuaFile 该文件
```

本 skill 只生成眼镜 DOF 一个用例，不生成其他装备、不生成其他视觉效果。

## 生成模板

```lua
-- <模块> Depth of Field Effect
-- Client-side DOF blur when glasses are dropped
--
-- ⚠️ 所有 <...> 占位符必须替换成【目标项目】的实际值（见上面「第一步」的表格）。
--    不要照抄任何示例 addon 的值 —— 特别是 SLOT 和 NWInt 键，填错会静默失效。

if not CLIENT then return end

local SLOT = "<槽位名>"          -- 例如 "Glasses" 或 "GL"

-- DOF Settings
local cv_enabled = CreateConVar("<前缀>_<槽位缩写>_DOF_Enabled", 1, {FCVAR_ARCHIVE}, "Enable DOF effect when glasses drop")

-- State
local dofActive = false

local TARGET = {
    ["<玩家模型路径，全小写>"] = true,
    ["<NPC模型路径，全小写>"]  = true,
}

local function isTargetModel(ent)
    return IsValid(ent) and ent.GetModel and TARGET[string.lower(ent:GetModel() or "")] == true
end

-- Use NWInt from EquipmentState for efficient state sync
local function getGlassesState(ply)
    if not IsValid(ply) then return 0 end
    return ply:GetNWInt("<前缀>_Live_" .. SLOT, 0)
end

local function shouldDOF()
    if not cv_enabled:GetBool() then return false end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false end
    if not isTargetModel(ply) then return false end

    return getGlassesState(ply) == 1
end

-- Apply DOF effect
hook.Add("RenderScreenspaceEffects", "<模块>_DOF_Render", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local shouldApply = shouldDOF()

    if shouldApply and not dofActive then
        DOF_Start()
        dofActive = true
    elseif not shouldApply and dofActive then
        timer.Simple(0, function() DOF_Kill() end)
        dofActive = false
    end
end)

-- Reset on spawn
hook.Add("PlayerSpawn", "<模块>_DOF_Spawn", function(ply)
    if ply == LocalPlayer() and dofActive then
        timer.Simple(0, function() DOF_Kill() end)
        dofActive = false
    end
end)

print("[<模块> DOF] Loaded")
```

## 关键坑点

1. **`DOF_Kill()` 必须延迟一帧**: 不能在 `RenderScreenspaceEffects` 回调里直接调用，必须包在 `timer.Simple(0, function() DOF_Kill() end)` 中。现有代码就是这么写的。

2. **客户端专用**: 文件必须以 `if not CLIENT then return end` 开头，且只放在 `lua/autorun/client/`。注意这与项目 AGENTS.md 里「所有脚本以 `if CLIENT then return end` 开头」的约定相反 —— 那条约定针对服务端脚本，本文件是特例。

3. **必须 AddCSLuaFile 注册**: 服务端状态模块里要有 `AddCSLuaFile("autorun/client/0_<模块>_DOF.lua")`。漏了客户端会静默不加载，无任何报错。

4. **模型表用 `string.lower` 匹配**: 模型注册时的路径可能含大写（如 `Xxx_Yyy.mdl`），TARGET 表统一用小写键，靠 `string.lower()` 对齐。改模型路径时两处都要注意大小写。

5. **`ply:Alive()` 检查**: 死亡时 NWInt 可能仍是掉落态，必须排除死亡玩家，否则死亡视角画面会模糊。

6. **`PlayerSpawn` 重置**: 重生时必须 `DOF_Kill()`，否则上一局的模糊会残留到新一局。

7. **Hook 名唯一**: `<模块>_DOF_Render` / `<模块>_DOF_Spawn`，同一 hook name 重复注册会覆盖。

8. **不要加 `dofActive` 之外的缓存**: 状态每帧读 NWInt，NWInt 读取开销可忽略。加缓存反而容易和真实状态不同步。

## 交付前检查清单

- [ ] 文件路径为 `lua/autorun/client/0_<模块>_DOF.lua`
- [ ] 以 `if not CLIENT then return end` 开头
- [ ] 槽位名、NWInt 键、状态模块前缀与**目标项目实际代码一致**（不是照抄示例）
- [ ] 目标模型列表与掉落脚本的 `MODELS` 表一致
- [ ] `DOF_Kill()` 包在 `timer.Simple(0, ...)` 中
- [ ] `shouldDOF()` 含 `ply:Alive()` 与 `isTargetModel(ply)` 检查
- [ ] `PlayerSpawn` 钩子重置 `dofActive`
- [ ] 服务端状态模块里加了对应的 `AddCSLuaFile` 行

