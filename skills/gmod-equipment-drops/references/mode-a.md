返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。

## 完整模板: 模式 A (any_damage)

> **实现要求**：保留本模式适用的状态、概率、同步和回滚不变量，按实际模型适配；多装备任务同时读取 multi-equipment.md，避免重复注册处理器。验收检查适用项，不要求逐行照抄旧模板。

```lua
if CLIENT then return end

local EQ = <MOD>
if not EQ then ErrorNoHalt("[<MOD>] EquipmentState missing\n") return end

local cv_enabled  = CreateConVar("<前缀>_Enabled", 1, {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local cv_life     = CreateConVar("<前缀>_CunZaiShiJian", 3600, {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local cv_drop_p   = CreateConVar("<前缀>_DropP", 0.10, {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local VEL, ANG    = 180, 60

local MODELS = { "models/path.mdl", "models/npc_path.mdl" }
for _, m in ipairs(MODELS) do EQ.RegisterModel(m) end

local SLOT       = "<装备槽名>"
local BG_NAME    = "<游戏内输出中的bodygroup名称>"
local ITEM_MODEL = "<独立掉落物模型路径>"
local BONE_NAME  = "<目标模型实际骨骼名>"
local TYPE_LABEL = "<装备类别>"

EQ.RegisterSlot(SLOT, BG_NAME, 1, 1)

local processed = setmetatable({}, { __mode = "k" })
local drops     = setmetatable({}, { __mode = "k" })

local function isTargetModel(ent)
    return IsValid(ent) and ent.GetModel and EQ.MODELS[(ent:GetModel() or ""):lower()] == true
end
local function isRagdoll(ent)
    return IsValid(ent) and ent:GetClass() == "prop_ragdoll"
end
local function findBG(ent)
    if not IsValid(ent) then return -1 end
    return ent:FindBodygroupByName(BG_NAME) or -1
end
local function getBG(ent)
    local idx = findBG(ent)
    return idx >= 0 and ent:GetBodygroup(idx) or -1
end
local function setBG(ent, value)
    if not IsValid(ent) then return end
    local idx = findBG(ent)
    if idx >= 0 then
        ent:SetBodygroup(idx, value)
        if ent.SetupBones then ent:SetupBones() end
        if ent.InvalidateBoneCache then ent:InvalidateBoneCache() end
        if isRagdoll(ent) then
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then phys:Wake() end
        end
    end
end
-- 骨骼不存在返回 nil —— 调用方跳过并打日志，不要回退到模型原点。
local warnedBones = {}
local function bonePos(ent)
    if not IsValid(ent) then return nil end
    local bid = ent:LookupBone(BONE_NAME)
    if bid then
        local p, a = ent:GetBonePosition(bid)
        if p then return p, a end
    end
    if not warnedBones[BONE_NAME] then
        warnedBones[BONE_NAME] = true
        EQ.Warn("模型缺少骨骼 " .. BONE_NAME
            .. " —— 该部位不会掉落。请用 HLMV 核对该模型的实际骨骼名。")
    end
    return nil
end
local function safeSpawnPos(src)
    local tr = util.TraceHull({
        start = src + Vector(0,0,8), endpos = src + Vector(0,0,-64),
        mins = Vector(-2,-2,-2), maxs = Vector(2,2,2), mask = MASK_SOLID_BRUSHONLY
    })
    return tr.Hit and (tr.HitPos + tr.HitNormal * 1.5) or src
end
local function prepPhys(e)
    e:SetMoveType(MOVETYPE_VPHYSICS)
    e:PhysicsInit(SOLID_VPHYSICS)
    e:SetSolid(SOLID_VPHYSICS)
    e:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    local ph = e:GetPhysicsObject()
    if IsValid(ph) then
        ph:Wake(); ph:SetBuoyancyRatio(0); ph:EnableDrag(true)
        ph:SetMass(math.max(ph:GetMass(), 2))
    end
end
local function impulse(phys, baseVel)
    if not IsValid(phys) then return end
    local dir = (isvector(baseVel) and baseVel:LengthSqr() > 1)
        and baseVel:GetNormalized() or VectorRand():GetNormalized()
    phys:SetVelocity(dir * VEL)
    phys:AddAngleVelocity(VectorRand() * ANG)
end
local function spawnItem(pos, baseVel, owner, lifeID)
    local e = ents.Create("prop_physics")
    if not IsValid(e) then return nil end
    e:SetModel(ITEM_MODEL)
    e:SetPos(safeSpawnPos(pos or vector_origin))
    prepPhys(e)
    e:Spawn()
    SafeRemoveEntityDelayed(e, cv_life:GetFloat())
    local ph = e:GetPhysicsObject()
    if IsValid(ph) then impulse(ph, baseVel or vector_origin) end
    if IsValid(owner) then
        e:SetNWString("<MOD>_EquipmentType", TYPE_LABEL)
        e:SetNWEntity("<MOD>_Owner", owner)
        e:SetNWString("<MOD>_ModelPath", ITEM_MODEL)
        e:SetNWString("<MOD>_BGName", BG_NAME)
        EQ.RegisterDrop(owner, SLOT, e, lifeID or EQ.GetLife(owner))
    end
    drops[e] = true
    return e
end
local function dropFromEntity(ent, baseVel, owner, lifeID)
    if not IsValid(ent) or not IsValid(owner) then return false end
    if EQ.HasDrop(owner, SLOT, lifeID or EQ.GetLife(owner)) then return false end
    local pos = select(1, bonePos(ent))
    if not pos then return false end
    local fwd = ent.GetForward and ent:GetForward() or Vector(0,1,0)
    local item = spawnItem(pos + fwd * 4, baseVel or vector_origin, owner, lifeID or EQ.GetLife(owner))
    if not IsValid(item) then return false end
    setBG(ent, 1)
    return true
end
local function applyRagdoll(source, rag)
    if not cv_enabled:GetBool() or not isTargetModel(source) or not isRagdoll(rag) then return end
    if processed[rag] then return end
    if not EQ.ApplyRagdollSnapshot(rag, source) then return end
    processed[rag] = true
    local lifeID = rag._<MOD>SourceLife
    if EQ.HasDrop(source, SLOT, lifeID) then
        setBG(rag, 1); EQ.SetRagdoll(rag, SLOT, 1)
    end
    local function restore()
        if not IsValid(rag) then return end
        local desired = EQ.GetRagdoll(rag, SLOT)
        if EQ.HasDrop(source, SLOT, lifeID) then
            desired = 1; EQ.SetRagdoll(rag, SLOT, 1)
        end
        setBG(rag, desired)
        if rag.SetupBones then rag:SetupBones() end
        if rag.InvalidateBoneCache then rag:InvalidateBoneCache() end
    end
    restore()
    timer.Simple(0.05, restore)
    timer.Simple(0.15, restore)
    timer.Simple(10, function() if IsValid(rag) then processed[rag] = nil end end)
end

-- 出生重置
hook.Add("PlayerSpawn", "<MOD>_Spawn", function(ply)
    if not cv_enabled:GetBool() or not isTargetModel(ply) then return end
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        EQ.Set(ply, SLOT, 0); setBG(ply, 0)
    end)
end)
hook.Add("OnEntityCreated", "<MOD>_NPCSpawn", function(ent)
    if not cv_enabled:GetBool() or not IsValid(ent) or not ent:IsNPC() then return end
    timer.Simple(0, function()
        if not IsValid(ent) or not isTargetModel(ent) then return end
        EQ.Set(ent, SLOT, 0); setBG(ent, 0)
    end)
end)

-- 布娃娃创建
hook.Add("CreateEntityRagdoll", "<MOD>_Ragdoll", function(source, rag)
    if not cv_enabled:GetBool() or not isTargetModel(source) or not isRagdoll(rag) then return end
    timer.Simple(0, function()
        if IsValid(source) and IsValid(rag) then applyRagdoll(source, rag) end
    end)
end)

-- 活体伤害 → 掉落（必须过滤布娃娃！）
hook.Add("EntityTakeDamage", "<MOD>_LiveDamage", function(ent)
    if not cv_enabled:GetBool() or not isTargetModel(ent) then return end
    if isRagdoll(ent) then return end
    if ent:IsPlayer() and not ent:Alive() then return end
    if ent:IsNPC() and ent:Health() <= 0 then return end
    if EQ.Get(ent, SLOT) == 1 or EQ.HasDrop(ent, SLOT) then return end
    if (math.random() * 1000) < (cv_drop_p:GetFloat() * 1000) then
        local vel = ent.GetVelocity and ent:GetVelocity() or vector_origin
        if dropFromEntity(ent, vel, ent, EQ.GetLife(ent)) then
            EQ.Set(ent, SLOT, 1)
        end
    end
end)

-- 布娃娃伤害 → 掉落（v15: 用 CanRagdollEnterDropCheck 防重复）
hook.Add("EntityTakeDamage", "<MOD>_RagDamage", function(rag, dmgInfo)
    if not cv_enabled:GetBool() or not isRagdoll(rag) or not isTargetModel(rag) then return end
    local source = rag._<MOD>SourceOwner
    local lifeID = rag._<MOD>SourceLife
    if not IsValid(source) or not lifeID then return end
    if EQ.CanRagdollEnterDropCheck and not EQ.CanRagdollEnterDropCheck(rag, SLOT) then return end
    local actualBG = getBG(rag)
    if actualBG == 1 then EQ.SetRagdoll(rag, SLOT, 1); return end
    if actualBG ~= 0 then return end
    if EQ.HasDrop(source, SLOT, lifeID) then return end
    if (math.random() * 1000) < (cv_drop_p:GetFloat() * 1000) then
        local atk = dmgInfo:GetAttacker()
        local vel = (IsValid(atk) and atk.GetVelocity and atk:GetVelocity()) or vector_origin
        if dropFromEntity(rag, vel, source, lifeID) then
            setBG(rag, 1); EQ.SetRagdoll(rag, SLOT, 1)
        end
    end
end)

-- 拾取（UnregisterDrop 必须在 SafeRemoveEntity 之前！）
hook.Add("PlayerButtonDown", "<MOD>_Pickup", function(ply, button)
    if button ~= KEY_F or not IsValid(ply) then return end
    local best, bestDist = nil, 80
    for ent in pairs(drops) do
        if IsValid(ent) then
            local owner, slot, lifeID = EQ.GetDropInfo(ent)
            if owner == ply and slot == SLOT and lifeID == EQ.GetLife(ply) then
                local d = ply:GetPos():Distance(ent:GetPos())
                if d <= bestDist then best = ent; bestDist = d end
            end
        end
    end
    if not IsValid(best) then return end
    local owner, slot, lifeID = EQ.GetDropInfo(best)
    if owner ~= ply or slot ~= SLOT or lifeID ~= EQ.GetLife(ply) then return end
    EQ.Set(ply, SLOT, 0); setBG(ply, 0)
    local effect = EffectData(); effect:SetOrigin(best:GetPos())
    util.Effect("item_respawn", effect)
    ply:EmitSound("items/itempickup.wav", 75, 100, 0.5)
    EQ.UnregisterDrop(best)
    drops[best] = nil
    SafeRemoveEntity(best)
end)

EQ.Log("loaded")
```

