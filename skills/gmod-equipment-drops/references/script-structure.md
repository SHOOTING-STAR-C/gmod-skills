返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。

## 生成脚本结构

所有模式共享以下结构，差异在钩子部分：

```lua
if CLIENT then return end

local EQ = <MOD>
if not EQ then ErrorNoHalt("[<MOD>] EquipmentState missing\n") return end

-- ============================================================
-- ConVar
-- ============================================================
local cv_enabled = CreateConVar("<前缀>_Enabled", 1, {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local cv_life    = CreateConVar("<前缀>_CunZaiShiJian", 3600, {FCVAR_REPLICATED, FCVAR_ARCHIVE})

-- ============================================================
-- 常量（根据模式调整）
-- ============================================================
local VEL, ANG = 180, 60

-- ============================================================
-- 模型与槽位注册
-- ============================================================
local MODELS = { "models/path.mdl" }
for _, m in ipairs(MODELS) do EQ.RegisterModel(m) end

local SLOT       = "<装备槽名>"
local BG_NAME    = "<游戏内输出中的bodygroup名称>"
local ITEM_MODEL = "<独立掉落物模型路径>"
local BONE_NAME  = "<目标模型实际骨骼名>"
local TYPE_LABEL = "<装备类别>"

-- 必须替换成字面量数字，不要保留 maxState/dropState 这两个名字：
-- 它们是未定义全局，取值 nil，会被 RegisterSlot 静默兜底成 1，
-- 于是「消失」退化成「悬挂」值，出现掉落物已生成但模型上装备还在的现象。
EQ.RegisterSlot(SLOT, BG_NAME, <maxState>, <dropState>)
-- maxState:  该槽位最大状态值（0=佩戴, 1=消失, 2=消失+悬挂中间态）
-- dropState: 掉落时设置的 bodygroup 值（必须是模型上真实存在的 submodel 索引）

-- ============================================================
-- 本地状态表（弱引用，自动清理）
-- ============================================================
local processed = setmetatable({}, { __mode = "k" })
local drops     = setmetatable({}, { __mode = "k" })

-- ============================================================
-- 辅助函数（所有模式通用）
-- ============================================================
-- isTargetModel, isRagdoll, findBG, getBG, setBG
-- bonePos, safeSpawnPos, prepPhys, impulse, spawnItem
-- 见各模式完整模板

-- ============================================================
-- 钩子: 出生重置 / 布娃娃创建 / 拾取（所有模式通用）
-- ============================================================
-- 拾取: UnregisterDrop 必须在 SafeRemoveEntity 之前！
```

