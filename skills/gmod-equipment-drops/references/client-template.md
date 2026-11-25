返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。

## 生成模板: 客户端同步 (0_<MOD>_Client.lua)

```lua
if not CLIENT then return end

local MOD_NAME = "<MOD>"

-- 状态模块开头就是 `if CLIENT then return end`，客户端拿不到 _G["<MOD>"]。
-- 因此客户端必须自己硬编码一份模型表 / 槽位表，且与掉落脚本的注册保持一致。
local TARGET = {
    ["models/path.mdl"]     = true,
    ["models/npc_path.mdl"] = true,
}

-- 必须与状态模块的 NET_SLOTS 逐项一致（不是 M.SLOTS！）。
-- 两侧都是常量表，改一边必须同步改另一边。
local SLOT_LIST = { "Shoe_L", "Shoe_R" }
local SLOT_BG = {
    Shoe_L = "<左鞋bodygroup名>",
    Shoe_R = "<右鞋bodygroup名>",
}

local function isTargetModel(ent)
    return IsValid(ent) and ent.GetModel and TARGET[string.lower(ent:GetModel() or "")] == true
end

local function forceBG(ent, bgName, state)
    if not IsValid(ent) or not bgName then return false end
    local idx = ent:FindBodygroupByName(bgName)
    if not idx or idx < 0 then return false end
    state = tonumber(state) or 0
    if ent:GetBodygroup(idx) == state then return false end
    ent:SetBodygroup(idx, state)
    return true
end

local function rebuild(ent)
    if not IsValid(ent) then return end
    if ent.InvalidateBoneCache then ent:InvalidateBoneCache() end
    if ent.SetupBones then ent:SetupBones() end
end

local function isNetworkRag(ent)
    return IsValid(ent) and ent:GetClass() == "prop_ragdoll" and isTargetModel(ent)
end

local directRagState = setmetatable({}, {__mode = "k"})
local pendingDirect = {}

local function syncNetworkRag(rag)
    if not isNetworkRag(rag) then return end
    if rag:GetNWInt(MOD_NAME .. "_RagLife", 0) <= 0 then return end
    local direct = directRagState[rag]
    local changed = false
    for _, slot in ipairs(SLOT_LIST) do
        local state = direct and direct.values[slot] or rag:GetNWInt(MOD_NAME .. "_Rag_" .. slot, 0)
        if forceBG(rag, SLOT_BG[slot], state) then changed = true end
    end
    if changed then rebuild(rag) end
end

net.Receive(MOD_NAME .. "_RagdollSnapshot", function()
    local rag = net.ReadEntity()
    local life = net.ReadInt(32)
    local values = {}
    for _, slot in ipairs(SLOT_LIST) do values[slot] = net.ReadInt(3) end
    if IsValid(rag) then
        directRagState[rag] = {life = life, values = values}
        syncNetworkRag(rag)
    else
        pendingDirect[rag:EntIndex()] = {life = life, values = values}
    end
end)

local function syncAll()
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do syncNetworkRag(rag) end
end

hook.Add("NotifyShouldTransmit", MOD_NAME .. "_NetworkRagTransmit", function(ent, shouldTransmit)
    if shouldTransmit and isNetworkRag(ent) then
        timer.Simple(0, function() if IsValid(ent) then syncNetworkRag(ent) end end)
        timer.Simple(0.05, function() if IsValid(ent) then syncNetworkRag(ent) end end)
        timer.Simple(0.15, function() if IsValid(ent) then syncNetworkRag(ent) end end)
    end
end)

hook.Add("OnEntityCreated", MOD_NAME .. "_NetworkRagCreated", function(ent)
    if not isNetworkRag(ent) then return end
    local pending = pendingDirect[ent:EntIndex()]
    if pending then
        directRagState[ent] = pending
        pendingDirect[ent:EntIndex()] = nil
    end
    timer.Simple(0, function() if IsValid(ent) then syncNetworkRag(ent) end end)
    timer.Simple(0.05, function() if IsValid(ent) then syncNetworkRag(ent) end end)
    timer.Simple(0.15, function() if IsValid(ent) then syncNetworkRag(ent) end end)
end)

hook.Add("EntityRemoved", MOD_NAME .. "_ClientRagCleanup", function(ent)
    directRagState[ent] = nil
    pendingDirect[ent:EntIndex()] = nil
end)

local nextThink = 0
hook.Add("Think", MOD_NAME .. "_ClientHardSync", function()
    local now = CurTime()
    if now < nextThink then return end
    nextThink = now + 0.05
    syncAll()
end)

hook.Add("PreDrawOpaqueRenderables", MOD_NAME .. "_ClientRagdollRenderSync", function()
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        if isNetworkRag(rag) then syncNetworkRag(rag) end
    end
end)

print("[" .. MOD_NAME .. " Client] loaded")  -- 客户端无 EQ 模块，直接 print
```

