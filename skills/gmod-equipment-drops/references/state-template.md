返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。

## 生成模板: 状态模块 (0_<MOD>_State.lua)

```lua
if CLIENT then return end

-- 注意：必须带引号 —— <MOD> 要替换成字符串 key（如 _G["MyMod"]）。
-- 写成裸标识符 _G[MyMod] 时 MyMod 是未定义全局（nil），会报
-- "table index is nil" 并中断整个状态模块。
_G["<MOD>"] = _G["<MOD>"] or {}
local M = _G["<MOD>"]

M.VERSION = 15
M.MODELS = M.MODELS or {}
M.SLOTDEF = M.SLOTDEF or {}
M.SLOTS = M.SLOTS or {}

AddCSLuaFile("autorun/client/0_<MOD>_Client.lua")

-- 日志开关：游戏中用 <MOD>_Log 0 关闭，1 打开
local cv_log = CreateConVar("<MOD>_Log", 0, {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "打印调试日志")

function M.Log(msg)
    if cv_log:GetBool() then print("[<MOD>] " .. msg) end
end

function M.Warn(msg)
    if cv_log:GetBool() then ErrorNoHalt("[<MOD>] " .. msg .. "\n") end
end

local entityState = setmetatable({}, { __mode = "k" })
local ragState = setmetatable({}, { __mode = "k" })
local lifeSerial = 0

local function isTarget(ent)
    if not IsValid(ent) or not ent.GetModel then return false end
    local mdl = ent:GetModel()
    return mdl and M.MODELS[string.lower(mdl)] == true or false
end

local function newValues()
    local t = {}
    for slot in pairs(M.SLOTDEF) do t[slot] = 0 end
    return t
end

local function clampState(slot, state)
    local def = M.SLOTDEF[slot]
    if not def then return 0 end
    state = math.floor(tonumber(state) or 0)
    return math.Clamp(state, 0, def.max_state or 1)
end

util.AddNetworkString("<MOD>_RagdollSnapshot")

-- 线格式：槽位按 NET_SLOTS 的位置顺序写出，客户端按位置读回。
-- 这张表必须与客户端 0_<MOD>_Client.lua 里的 SLOT_LIST 逐项一致。
-- 绝不要改成 M.SLOTS —— 那是 RegisterSlot 的调用顺序，取决于掉落脚本的
-- 文件加载顺序，客户端无法复现。顺序一旦错位，客户端会把某个槽位的状态
-- 套到另一个槽位的 bodygroup 上，表现为「掉落物生成了，但模型上消失的是
-- 另一个部位」或「掉的部位不对」。
local NET_SLOTS = { "Shoe_L", "Shoe_R" }

local function netRagdollSnapshot(rag, st)
    if not IsValid(rag) or not st then return end
    net.Start("<MOD>_RagdollSnapshot")
        net.WriteEntity(rag)
        net.WriteInt(st.life or 0, 32)
        for _, slot in ipairs(NET_SLOTS) do
            net.WriteInt(clampState(slot, st.values[slot] or 0), 3)
        end
    net.Broadcast()
end

local function ensureEntity(ent)
    if not IsValid(ent) then return nil end
    local st = entityState[ent]
    if st then return st end
    lifeSerial = lifeSerial + 1
    st = { life = lifeSerial, values = newValues(), death = nil, drops = {} }
    entityState[ent] = st
    return st
end

function M.RegisterModel(model)
    if isstring(model) and model ~= "" then
        M.MODELS[string.lower(model)] = true
    end
end

function M.RegisterSlot(slot, bodygroup, maxState, dropState)
    if not isstring(slot) or slot == "" then return end
    if not M.SLOTDEF[slot] then
        table.insert(M.SLOTS, slot)
        M.SLOTDEF[slot] = {
            bg = bodygroup,
            max_state = tonumber(maxState) or 1,
            drop_state = tonumber(dropState) or 1
        }
    else
        local def = M.SLOTDEF[slot]
        def.bg = bodygroup or def.bg
        def.max_state = tonumber(maxState) or def.max_state
        def.drop_state = tonumber(dropState) or def.drop_state
    end
end

function M.GetLife(ent)
    local st = ensureEntity(ent)
    return st and st.life or 0
end

function M.ResetLife(ent)
    local st = ensureEntity(ent)
    if not st then return 0 end
    lifeSerial = lifeSerial + 1
    st.life = lifeSerial
    st.values = newValues()
    st.death = nil
    ent:SetNWInt("<MOD>_DeathLife", 0)
    for slot in pairs(M.SLOTDEF) do
        ent:SetNWInt("<MOD>_Live_" .. slot, 0)
        ent:SetNWInt("<MOD>_Death_" .. slot, 0)
    end
    return st.life
end

function M.Get(ent, slot)
    local st = ensureEntity(ent)
    if not st or not M.SLOTDEF[slot] then return 0 end
    return clampState(slot, st.values[slot] or 0)
end

function M.Set(ent, slot, state)
    local st = ensureEntity(ent)
    if not st or not M.SLOTDEF[slot] then return false end
    state = clampState(slot, state)
    st.values[slot] = state
    ent:SetNWInt("<MOD>_Live_" .. slot, state)
    return true
end

function M.GetAll(ent)
    local st = ensureEntity(ent)
    local out = newValues()
    if not st then return out end
    for slot in pairs(out) do
        out[slot] = clampState(slot, st.values[slot] or 0)
    end
    return out
end

local function readBG(ent, def)
    if not IsValid(ent) or not def.bg or not ent.FindBodygroupByName then return nil end
    local idx = ent:FindBodygroupByName(def.bg)
    if not idx or idx < 0 then return nil end
    local value = ent:GetBodygroup(idx)
    if not isnumber(value) or value < 0 then return nil end
    return value
end

function M.CaptureDeath(ent)
    local st = ensureEntity(ent)
    if not st then return nil end
    if st.death and st.death.life == st.life then return st.death end
    local values = {}
    for slot, def in pairs(M.SLOTDEF) do
        local bg = readBG(ent, def)
        if M.HasDrop(ent, slot, st.life) then bg = def.drop_state end
        values[slot] = clampState(slot, bg ~= nil and bg or st.values[slot] or 0)
    end
    st.death = { life = st.life, time = CurTime(), values = values }
    for slot, value in pairs(values) do
        st.values[slot] = value
        ent:SetNWInt("<MOD>_Death_" .. slot, value)
    end
    ent:SetNWInt("<MOD>_DeathLife", st.life)
    return st.death
end

function M.GetDeath(ent)
    local st = ensureEntity(ent)
    if not st or not st.death or st.death.life ~= st.life then return nil end
    return st.death
end

function M.BindRagdoll(rag, source)
    if not IsValid(rag) or not IsValid(source) then return false end
    local existing = ragState[rag]
    if existing then return existing.source == source end
    local death = M.GetDeath(source)
    if not death then return false end
    local values = {}
    for slot, value in pairs(death.values) do values[slot] = value end
    ragState[rag] = { source = source, life = death.life, values = values, drops = {} }
    rag._<MOD>SourceOwner = source
    rag._<MOD>SourceLife = death.life
    rag:SetNWInt("<MOD>_RagLife", death.life)
    for slot, value in pairs(values) do
        rag:SetNWInt("<MOD>_Rag_" .. slot, tonumber(value) or 0)
    end
    netRagdollSnapshot(rag, ragState[rag])
    return true
end

function M.GetRagdollLife(rag)
    local st = ragState[rag]
    return st and st.life or nil
end

function M.GetRagdoll(rag, slot)
    local st = ragState[rag]
    if not st or not M.SLOTDEF[slot] then return 0 end
    return clampState(slot, st.values[slot] or 0)
end

function M.SetRagdoll(rag, slot, state)
    local st = ragState[rag]
    if not st or not M.SLOTDEF[slot] then return false end
    state = clampState(slot, state)
    st.values[slot] = state
    rag:SetNWInt("<MOD>_Rag_" .. slot, state)
    rag:SetNWInt("<MOD>_RagLife", st.life)
    netRagdollSnapshot(rag, st)
    return true
end

function M.GetRagdollAll(rag)
    local st = ragState[rag]
    local out = newValues()
    if not st then return out end
    for slot in pairs(out) do
        out[slot] = clampState(slot, st.values[slot] or 0)
    end
    return out
end

function M.RegisterDrop(owner, slot, drop, lifeID)
    local st = ensureEntity(owner)
    if not st or not IsValid(drop) or not M.SLOTDEF[slot] then return false end
    lifeID = tonumber(lifeID) or st.life
    st.drops[lifeID] = st.drops[lifeID] or {}
    for oldDrop in pairs(st.drops[lifeID]) do
        if IsValid(oldDrop) and oldDrop._<MOD>Slot == slot then return false end
    end
    drop._<MOD>Owner = owner
    drop._<MOD>Slot = slot
    drop._<MOD>Life = lifeID
    drop:SetNWEntity("<MOD>_DropOwner", owner)
    drop:SetNWString("<MOD>_DropSlot", slot)
    drop:SetNWInt("<MOD>_DropLife", lifeID)
    st.drops[lifeID][drop] = true
    if lifeID == st.life then
        st.values[slot] = M.SLOTDEF[slot].drop_state
        owner:SetNWInt("<MOD>_Live_" .. slot, M.SLOTDEF[slot].drop_state)
    end
    return true
end

function M.UnregisterDrop(drop)
    if not drop then return end
    local owner = drop._<MOD>Owner
    local lifeID = drop._<MOD>Life
    if IsValid(owner) and entityState[owner] and lifeID then
        local bucket = entityState[owner].drops[lifeID]
        if bucket then
            bucket[drop] = nil
            if next(bucket) == nil then entityState[owner].drops[lifeID] = nil end
        end
    end
    drop._<MOD>Owner = nil
    drop._<MOD>Slot = nil
    drop._<MOD>Life = nil
end

function M.GetDropInfo(drop)
    if not IsValid(drop) then return nil end
    return drop._<MOD>Owner, drop._<MOD>Slot, drop._<MOD>Life
end

function M.FindDrop(owner, slot, lifeID)
    local st = ensureEntity(owner)
    if not st then return nil end
    lifeID = tonumber(lifeID) or st.life
    local bucket = st.drops[lifeID]
    if not bucket then return nil end
    for drop in pairs(bucket) do
        if not IsValid(drop) or not drop:IsInWorld() then
            bucket[drop] = nil
        elseif drop._<MOD>Slot == slot and drop._<MOD>Life == lifeID then
            return drop
        end
    end
    return nil
end

function M.HasDrop(owner, slot, lifeID)
    return IsValid(M.FindDrop(owner, slot, lifeID))
end

function M.CanRagdollEnterDropCheck(rag, slot)
    if not IsValid(rag) or rag:GetClass() ~= "prop_ragdoll" then return false end
    local def = M.SLOTDEF[slot]
    if not def then return false end
    local idx = rag:FindBodygroupByName(def.bg)
    if not idx or idx < 0 then return false end
    local bg = rag:GetBodygroup(idx)
    if slot:find("Shoe") then return bg == 0 or bg == 1 end
    return bg == 0
end

local function setBG(ent, bodygroup, state)
    if not IsValid(ent) or not bodygroup then return end
    local idx = ent:FindBodygroupByName(bodygroup)
    if not idx or idx < 0 then return end
    ent:SetBodygroup(idx, tonumber(state) or 0)
    if ent.SetupBones then ent:SetupBones() end
    if ent.InvalidateBoneCache then ent:InvalidateBoneCache() end
    if ent:GetClass() == "prop_ragdoll" then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end
end

function M.ApplyRagdollSnapshot(rag, source)
    if not M.BindRagdoll(rag, source) then return false end
    local st = ragState[rag]
    for slot, def in pairs(M.SLOTDEF) do
        local value = clampState(slot, st.values[slot] or 0)
        rag:SetNWInt("<MOD>_Rag_" .. slot, value)
        setBG(rag, def.bg, value)
    end
    rag:SetNWInt("<MOD>_RagLife", st.life)
    netRagdollSnapshot(rag, st)
    for _, delay in ipairs({0.05, 0.15, 0.30, 0.60, 1.00, 2.00}) do
        timer.Simple(delay, function()
            if IsValid(rag) and ragState[rag] == st then netRagdollSnapshot(rag, st) end
        end)
    end
    if rag.SetupBones then rag:SetupBones() end
    if rag.InvalidateBoneCache then rag:InvalidateBoneCache() end
    local phys = rag:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
    return true
end

local function applyLiving(ent)
    if not IsValid(ent) or not isTarget(ent) then return end
    if ent:IsPlayer() and not ent:Alive() then return end
    if ent:IsNPC() and ent:Health() <= 0 then return end
    local st = ensureEntity(ent)
    if not st then return end
    for slot, def in pairs(M.SLOTDEF) do
        local desired = st.values[slot] or 0
        if M.HasDrop(ent, slot, st.life) then
            desired = def.drop_state
            st.values[slot] = desired
        end
        setBG(ent, def.bg, desired)
    end
end

hook.Add("PlayerSpawn", "<MOD>_NewLife", function(ply)
    if not isTarget(ply) then return end
    M.ResetLife(ply)
end)

hook.Add("OnEntityCreated", "<MOD>_NewNPCLife", function(ent)
    if not IsValid(ent) or not ent:IsNPC() then return end
    timer.Simple(0, function()
        if IsValid(ent) and isTarget(ent) then M.ResetLife(ent) end
    end)
end)

hook.Add("DoPlayerDeath", "<MOD>_CaptureDeath", function(ply)
    if isTarget(ply) then M.CaptureDeath(ply) end
end)

hook.Add("OnNPCKilled", "<MOD>_CaptureNPCDeath", function(npc)
    if isTarget(npc) then M.CaptureDeath(npc) end
end)

hook.Add("EntityRemoved", "<MOD>_DropCleanup", function(ent)
    M.UnregisterDrop(ent)
    ragState[ent] = nil
end)

local nextSync = 0
hook.Add("Think", "<MOD>_Reconcile", function()
    local now = CurTime()
    if now < nextSync then return end
    nextSync = now + 0.10
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and isTarget(ply) and ply:Alive() then applyLiving(ply) end
    end
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and isTarget(npc) and npc:Health() > 0 then applyLiving(npc) end
    end
    for _, r in ipairs(ents.FindByClass("prop_ragdoll")) do
        local rs = ragState[r]
        if rs and IsValid(r) then
            local owner, life = rs.source, rs.life
            for slot, def in pairs(M.SLOTDEF) do
                local desired = clampState(slot, rs.values[slot] or 0)
                if IsValid(owner) and M.HasDrop(owner, slot, life) then
                    desired = def.drop_state
                    rs.values[slot] = desired
                end
                if r:GetNWInt("<MOD>_Rag_" .. slot, -999) ~= desired then
                    r:SetNWInt("<MOD>_Rag_" .. slot, desired)
                end
                setBG(r, def.bg, desired)
            end
            r:SetNWInt("<MOD>_RagLife", life)
        end
    end
end)

M.Log("State v" .. M.VERSION .. " loaded")
```

