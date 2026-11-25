返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。

## 完整模板: 模式 C (ragdoll_proximity)

> **实现要求**：保留适用的配对、状态机和概率语义，并按实际分组适配。读取成品确认状态含义；只有真实存在悬挂态且任务需要时才采用悬挂分支。多装备实现同时遵守 multi-equipment.md，不要求逐行照抄旧模板。

适用于鞋子等 L/R 成对物品，支持 3 状态机（0=佩戴 → 1=悬挂 → 2=地面）。

```lua
if CLIENT then return end

local EQ = <MOD>
if not EQ then ErrorNoHalt("[<MOD>] EquipmentState missing\n") return end

local cv_enabled  = CreateConVar("<前缀>_Enabled", 1, {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local cv_life     = CreateConVar("<前缀>_CunZaiShiJian", 3600, {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local cv_exp_p    = CreateConVar("<前缀>_ExpP", "0.50,0.50", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local cv_death_p  = CreateConVar("<前缀>_DeathP", "0.15,0.12", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local VEL, ANGVEL = 180, 60

-- 从 ConVar 解析 L,R 概率（格式 "0.20,0.25"）
local function parseLR(cv, defL, defR)
    local s = cv:GetString()
    local a, b = s:match("([^,]+),([^,]+)")
    return { L = tonumber(a) or defL, R = tonumber(b) or defR }
end

local MODELS = { "models/path.mdl", "models/npc_path.mdl" }
for _, m in ipairs(MODELS) do EQ.RegisterModel(m) end

local SHOE_MODELS = { L = "models/path/to/left.mdl", R = "models/path/to/right.mdl" }
local BONE_NAMES  = { L = "ValveBiped.Bip01_L_Foot", R = "ValveBiped.Bip01_R_Foot" }
local BG_NAMES    = { L = "<左鞋bodygroup名>", R = "<右鞋bodygroup名>" }
local SLOTS       = { L = "Shoe_L", R = "Shoe_R" }

EQ.RegisterSlot("Shoe_L", "<左鞋bodygroup名>", 2, 2)  -- maxState=2, dropState=2
EQ.RegisterSlot("Shoe_R", "<右鞋bodygroup名>", 2, 2)

local processed = setmetatable({}, { __mode = "k" })
local drops     = setmetatable({}, { __mode = "k" })

local function isTargetModel(ent)
    return IsValid(ent) and ent.GetModel and EQ.MODELS[(ent:GetModel() or ""):lower()] == true
end
local function isRagdoll(ent)
    return IsValid(ent) and ent:GetClass() == "prop_ragdoll"
end
local function findBG(ent, name)
    if not IsValid(ent) then return -1 end
    return ent:FindBodygroupByName(name) or -1
end
local function getBG(ent, name)
    local idx = findBG(ent, name)
    return idx >= 0 and ent:GetBodygroup(idx) or -1
end
local function setBG(ent, name, value)
    if not IsValid(ent) then return end
    local idx = findBG(ent, name)
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
-- 骨骼不存在时返回 nil，由调用方跳过。
-- 绝不回退到 ent:GetPos()：L/R 会拿到同一个坐标，
-- DistToSqr 恒等 → `dl < dr` 恒 false → 永远只掉右侧，且掉落物生成在模型原点。
local warnedBones = {}
local function bonePos(ent, boneName)
    if not IsValid(ent) then return nil end
    local bid = ent:LookupBone(boneName)
    if bid then
        local p, a = ent:GetBonePosition(bid)
        if p then return p, a end
    end
    if not warnedBones[boneName] then
        warnedBones[boneName] = true
        EQ.Warn("模型缺少骨骼 " .. tostring(boneName)
            .. " —— 该部位不会掉落。请用 HLMV 核对该模型的实际骨骼名。")
    end
    return nil
end
local function safeSpawnPos(src, outward)
    local start = src + (outward or VectorRand():GetNormalized() * 2)
    local tr = util.TraceHull({
        start = start + Vector(0,0,8), endpos = start + Vector(0,0,-64),
        mins = Vector(-2,-2,-2), maxs = Vector(2,2,2), mask = MASK_SOLID_BRUSHONLY
    })
    return tr.Hit and (tr.HitPos + tr.HitNormal * 1.5) or start
end
local function prepPhys(e)
    e:SetMoveType(MOVETYPE_VPHYSICS)
    e:PhysicsInit(SOLID_VPHYSICS)
    e:SetSolid(SOLID_VPHYSICS)
    e:SetHealth(0)
    e:SetMaxHealth(0)
    e:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    local ph = e:GetPhysicsObject()
    if IsValid(ph) then
        ph:Wake(); ph:SetBuoyancyRatio(0); ph:EnableDrag(true)
        ph:SetMass(math.max(ph:GetMass(), 2))
    end
end
local function applyPose(e, refEnt)
    if not IsValid(e) then return end
    local base = IsValid(refEnt) and refEnt:GetAngles() or Angle(0,0,0)
    local ang = Angle(base.p, base.y, base.r)
    local pose = ({ "L_SIDE", "R_SIDE", "BACK", "FACE" })[math.random(1,4)]
    if pose == "L_SIDE" then ang:RotateAroundAxis(ang:Forward(), -90)
    elseif pose == "R_SIDE" then ang:RotateAroundAxis(ang:Forward(), 90)
    elseif pose == "BACK" then ang:RotateAroundAxis(ang:Right(), 90)
    else ang:RotateAroundAxis(ang:Right(), -90) end
    ang:RotateAroundAxis(ang:Up(), math.Rand(-15,15))
    e:SetAngles(ang)
end
local function impulse(phys, baseVel, refEnt)
    if not IsValid(phys) then return end
    local back = IsValid(refEnt) and refEnt.GetAngles and -refEnt:GetAngles():Forward() or Vector(0,0,0)
    back.z = 0
    local srcDir = isvector(baseVel) and baseVel:LengthSqr() > 1 and baseVel:GetNormalized() or vector_origin
    srcDir.z = 0
    if back:LengthSqr() > 0 then back:Normalize() end
    if srcDir:LengthSqr() > 0 then srcDir:Normalize() end
    local dir = back * 0.7 + srcDir * 0.3
    if dir:LengthSqr() < 0.01 then
        dir = VectorRand(); dir.z = 0
        if dir:LengthSqr() < 0.01 then dir = Vector(1,0,0) end
        dir:Normalize()
    end
    phys:SetVelocity(dir * (VEL * 0.8) + Vector(0,0,1) * (VEL * 0.35))
    phys:AddAngleVelocity(VectorRand() * (ANGVEL * 0.4))
end

local function spawnShoe(side, pos, baseVel, refEnt, noImpulse, owner, lifeID)
    local e = ents.Create("prop_physics")
    if not IsValid(e) then return nil end
    e:SetModel(SHOE_MODELS[side])
    prepPhys(e)
    e:SetPos(safeSpawnPos(pos or vector_origin))
    e:Spawn()
    applyPose(e, refEnt)
    SafeRemoveEntityDelayed(e, cv_life:GetFloat())
    local phys = e:GetPhysicsObject()
    if IsValid(phys) and not noImpulse then impulse(phys, baseVel, refEnt) end
    if IsValid(owner) then
        e:SetNWString("<MOD>_EquipmentType", "shoe")
        e:SetNWEntity("<MOD>_Owner", owner)
        e:SetNWString("<MOD>_ShoeSide", side)
        e:SetNWString("<MOD>_BGName", BG_NAMES[side])
        e:SetNWInt("<MOD>_State", 2)
        e:SetNWString("<MOD>_ModelPath", SHOE_MODELS[side])
        local curBG = getBG(refEnt, BG_NAMES[side])
        e:SetNWInt("<MOD>_ShoeType", curBG == 2 and 0 or math.max(curBG, 0))
        EQ.RegisterDrop(owner, SLOTS[side], e, lifeID or EQ.GetLife(owner))
    end
    drops[e] = true
    return e
end

local function currentRagState(rag, side) return EQ.GetRagdoll(rag, SLOTS[side]) end
local function setRagState(rag, side, state) EQ.SetRagdoll(rag, SLOTS[side], state) end

local function skipByGroundDrop(rag, side)
    local owner = rag._<MOD>SourceOwner
    local lifeID = rag._<MOD>SourceLife
    if not IsValid(owner) or not lifeID then return false end
    if EQ.HasDrop(owner, SLOTS[side], lifeID) then
        setBG(rag, BG_NAMES[side], 2)
        setRagState(rag, side, 2)
        rag["_sd" .. side] = true
        return true
    end
    return false
end

local function scheduleAutoDrop(rag, side, baseVel, lifeID)
    if not IsValid(rag) then return end
    local flag = "_sd" .. side
    timer.Simple(5, function()
        if not IsValid(rag) or rag[flag] then return end
        if currentRagState(rag, side) ~= 1 then return end
        local owner = rag._<MOD>SourceOwner
        local ragLife = rag._<MOD>SourceLife
        if not IsValid(owner) or ragLife ~= lifeID then return end
        if EQ.HasDrop(owner, SLOTS[side], ragLife) then return end
        if (math.random() * 1000) > (parseLR(cv_exp_p, 0.50, 0.50)[side] * 1000) then return end
        local pos = bonePos(rag, BONE_NAMES[side])
        if not pos then return end
        setBG(rag, BG_NAMES[side], 2)
        local drop = spawnShoe(side, pos, baseVel or vector_origin, rag, true, owner, ragLife)
        if IsValid(drop) then
            setRagState(rag, side, 2); rag[flag] = true
        else
            setBG(rag, BG_NAMES[side], 1)
        end
    end)
end

local function forceDropIfHalfHang(rag, side, baseVel)
    if skipByGroundDrop(rag, side) or rag["_sd" .. side] then return false end
    if currentRagState(rag, side) ~= 1 then return false end
    local owner = rag._<MOD>SourceOwner
    local lifeID = rag._<MOD>SourceLife
    if not IsValid(owner) or not lifeID or EQ.HasDrop(owner, SLOTS[side], lifeID) then return false end
    local pos = bonePos(rag, BONE_NAMES[side])
    if not pos then return false end
    setBG(rag, BG_NAMES[side], 2)
    local drop = spawnShoe(side, pos, baseVel, rag, false, owner, lifeID)
    if IsValid(drop) then
        setRagState(rag, side, 2); rag["_sd" .. side] = true
        return true
    end
    setBG(rag, BG_NAMES[side], 1)
    return false
end

    local function tryFootHangOrDrop(rag, side, baseVel)
        if skipByGroundDrop(rag, side) or rag["_sd" .. side] then return end
        if currentRagState(rag, side) == 2 then setBG(rag, BG_NAMES[side], 2); return end
        local roll = math.random()
        local expP = parseLR(cv_exp_p, 0.50, 0.50)[side]
        if roll < expP then
            -- 伤害触发：有悬挂位就悬挂，否则直接掉落
            if rag._sd_hang_side and rag._sd_hang_side ~= side then
                local pos = bonePos(rag, BONE_NAMES[side])
                if not pos then return end
                setBG(rag, BG_NAMES[side], 2)
                local drop = spawnShoe(side, pos, baseVel, rag, false, rag._<MOD>SourceOwner, rag._<MOD>SourceLife)
                if IsValid(drop) then
                    setRagState(rag, side, 2); rag["_sd" .. side] = true
                else
                    setBG(rag, BG_NAMES[side], 0)
                end
            else
                setBG(rag, BG_NAMES[side], 1)
                setRagState(rag, side, 1)
                rag._sd_hang_side = side
                scheduleAutoDrop(rag, side, baseVel, rag._<MOD>SourceLife)
            end
        end
    end

local function applyRagdoll(source, rag)
    if not cv_enabled:GetBool() then return end
    if not IsValid(source) or not IsValid(rag) or not isRagdoll(rag) then return end
    if processed[rag] then return end
    if not EQ.ApplyRagdollSnapshot(rag, source) then return end
    processed[rag] = true
    rag._sdL = false
    rag._sdR = false
    rag._sd_hang_side = nil
    for _, side in ipairs({"L","R"}) do
        local st = EQ.GetRagdoll(rag, SLOTS[side])
        if st == 1 then rag._sd_hang_side = rag._sd_hang_side or side
        elseif st == 2 then rag["_sd" .. side] = true end
    end
    local baseVel = source._sd_attVel or (source.GetVelocity and source:GetVelocity()) or vector_origin
    for _, side in ipairs({"L","R"}) do
        local st = EQ.GetRagdoll(rag, SLOTS[side])
        if EQ.HasDrop(source, SLOTS[side], rag._<MOD>SourceLife) then
            setBG(rag, BG_NAMES[side], 2)
            setRagState(rag, side, 2)
            rag["_sd" .. side] = true
        elseif st == 2 then
            setBG(rag, BG_NAMES[side], 2)
        elseif st == 1 then
            scheduleAutoDrop(rag, side, baseVel, rag._<MOD>SourceLife)
        else
            -- 死亡时用 DeathP 概率决定是否掉落
            local deathP = parseLR(cv_death_p, 0.15, 0.12)[side]
            if (math.random() * 1000) < (deathP * 1000) then
                tryFootHangOrDrop(rag, side, baseVel)
            end
        end
    end
end

-- 出生重置
hook.Add("PlayerSpawn", "<MOD>_Spawn", function(ply)
    if not cv_enabled:GetBool() or not isTargetModel(ply) then return end
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        for _, side in ipairs({"L","R"}) do setBG(ply, BG_NAMES[side], EQ.Get(ply, SLOTS[side])) end
    end)
end)
hook.Add("OnEntityCreated", "<MOD>_NPCSpawn", function(ent)
    if not cv_enabled:GetBool() or not IsValid(ent) or not ent:IsNPC() then return end
    timer.Simple(0, function()
        if not IsValid(ent) or not isTargetModel(ent) then return end
        for _, side in ipairs({"L","R"}) do setBG(ent, BG_NAMES[side], EQ.Get(ent, SLOTS[side])) end
    end)
end)

-- 保存攻击者速度（供掉落物抛射方向使用）
hook.Add("DoPlayerDeath", "<MOD>_SaveVelocity", function(ent, attacker)
    if not cv_enabled:GetBool() or not isTargetModel(ent) then return end
    ent._sd_attVel = (IsValid(attacker) and attacker.GetVelocity and attacker:GetVelocity())
        or (ent.GetVelocity and ent:GetVelocity()) or vector_origin
end)
hook.Add("OnNPCKilled", "<MOD>_SaveNPCVelocity", function(ent, attacker)
    if not cv_enabled:GetBool() or not isTargetModel(ent) then return end
    ent._sd_attVel = (IsValid(attacker) and attacker.GetVelocity and attacker:GetVelocity())
        or (ent.GetVelocity and ent:GetVelocity()) or vector_origin
end)

-- 布娃娃创建
hook.Add("CreateEntityRagdoll", "<MOD>_Ragdoll", function(source, rag)
    if not cv_enabled:GetBool() or not isTargetModel(source) or not isRagdoll(rag) then return end
    timer.Simple(0, function()
        if IsValid(source) and IsValid(rag) then applyRagdoll(source, rag) end
    end)
end)
hook.Add("PostPlayerDeath", "<MOD>_PostDeath", function(ply)
    if not cv_enabled:GetBool() or not isTargetModel(ply) then return end
    timer.Simple(0.05, function()
        local rag = IsValid(ply) and ply:GetRagdollEntity() or nil
        if IsValid(rag) then applyRagdoll(ply, rag) end
    end)
end)

-- 布娃娃伤害（骨骼距离检测 + 状态机）
hook.Add("EntityTakeDamage", "<MOD>_RagDamage", function(rag, dmgInfo)
    if not cv_enabled:GetBool() or not isRagdoll(rag) or not isTargetModel(rag) then return end
    local source = rag._<MOD>SourceOwner
    local lifeID = rag._<MOD>SourceLife
    if not IsValid(source) or not lifeID then return end
    local damagePos = dmgInfo:GetDamagePosition()
    local lPos = select(1, bonePos(rag, BONE_NAMES.L))
    local rPos = select(1, bonePos(rag, BONE_NAMES.R))
    -- 没有骨骼就没有部位可判定。直接放弃，绝不能用模型原点顶替：
    -- 那样两边的 DistToSqr 恒等，会永远判成同一侧。
    if not lPos or not rPos then return end
    local thresholdSq = 30 ^ 2
    local dl = damagePos:DistToSqr(lPos)
    local dr = damagePos:DistToSqr(rPos)
    if dl > thresholdSq and dr > thresholdSq then return end
    local side
    if dl <= thresholdSq and dr <= thresholdSq then side = dl < dr and "L" or "R"
    elseif dl <= thresholdSq then side = "L"
    else side = "R" end
    local attacker = dmgInfo:GetAttacker()
    local baseVel = IsValid(attacker) and attacker.GetVelocity and attacker:GetVelocity() or vector_origin
    if skipByGroundDrop(rag, side) then return end
    local actualBG = getBG(rag, BG_NAMES[side])
    if actualBG == 2 then
        setRagState(rag, side, 2); rag["_sd" .. side] = true; return
    elseif actualBG == 1 then setRagState(rag, side, 1)
    elseif actualBG == 0 then setRagState(rag, side, 0)
    else return end
    if currentRagState(rag, side) == 1 then
        forceDropIfHalfHang(rag, side, baseVel)
    else
        tryFootHangOrDrop(rag, side, baseVel)
    end
end)

-- 延迟初始化已存在的布娃娃
hook.Add("OnEntityCreated", "<MOD>_InitRagdoll", function(ent)
    if not cv_enabled:GetBool() or not IsValid(ent) or not isRagdoll(ent) then return end
    timer.Simple(0, function()
        if not IsValid(ent) or not isTargetModel(ent) then return end
        if processed[ent] then return end
        local owner = ent._<MOD>SourceOwner
        local lifeID = ent._<MOD>SourceLife
        if not IsValid(owner) or not lifeID then return end
        for _, side in ipairs({"L","R"}) do
            local bg = getBG(ent, BG_NAMES[side])
            if bg == 2 then
                setRagState(ent, side, 2); ent["_sd" .. side] = true
            elseif bg == 1 and EQ.GetRagdoll(ent, SLOTS[side]) == 0 then
                setRagState(ent, side, 1)
                ent._sd_hang_side = ent._sd_hang_side or side
                scheduleAutoDrop(ent, side, vector_origin, lifeID)
            end
        end
    end)
end)

-- 拾取（KEY_F, 范围 150）
hook.Add("PlayerButtonDown", "<MOD>_Pickup", function(ply, button)
    if button ~= KEY_F or not IsValid(ply) then return end
    local best, bestDist = nil, 150
    for ent in pairs(drops) do
        if IsValid(ent) then
            local owner, slot, lifeID = EQ.GetDropInfo(ent)
            if owner == ply and lifeID == EQ.GetLife(ply) then
                local dist = ply:GetPos():Distance(ent:GetPos())
                if dist <= bestDist then best = ent; bestDist = dist end
            end
        end
    end
    if not IsValid(best) then return end
    local owner, slot, lifeID = EQ.GetDropInfo(best)
    if owner ~= ply or lifeID ~= EQ.GetLife(ply) then return end
    local side = slot == SLOTS.L and "L" or slot == SLOTS.R and "R" or nil
    if not side then return end
    EQ.Set(ply, slot, 0); setBG(ply, BG_NAMES[side], 0)
    local effect = EffectData(); effect:SetOrigin(best:GetPos())
    util.Effect("item_respawn", effect)
    ply:EmitSound("items/itempickup.wav", 75, 100, 0.5)
    EQ.UnregisterDrop(best); drops[best] = nil; SafeRemoveEntity(best)
end)

EQ.Log("SOD loaded")
```

### 模式 C 简化版（无悬挂态，2 态：穿戴/掉落）

> **严格要求**：只替换完整版中标注的函数/逻辑，不可额外简化其他部分。`RegisterSlot` 必须改为 `maxState=1, dropState=1`。

适用于只有「穿戴」和「掉落」两个状态的 L/R 成对物品（如护膝、袖套等）。
与完整版的区别：去掉所有悬挂相关逻辑，`RegisterSlot` 用 `maxState=1, dropState=1`。

**替换完整版中的以下部分：**

RegisterSlot 改为 2 态：
```lua
EQ.RegisterSlot("Shoe_L", "<左鞋bodygroup名>", 1, 1)  -- maxState=1, dropState=1（无悬挂）
EQ.RegisterSlot("Shoe_R", "<右鞋bodygroup名>", 1, 1)
```

删除以下函数（完整版才有）：
- `scheduleAutoDrop`
- `forceDropIfHalfHang`
- `_sd_hang_side` 相关逻辑

替换 `skipByGroundDrop`（dropState 改为 1）：
```lua
local function skipByGroundDrop(rag, side)
    local owner = rag._<MOD>SourceOwner
    local lifeID = rag._<MOD>SourceLife
    if not IsValid(owner) or not lifeID then return false end
    if EQ.HasDrop(owner, SLOTS[side], lifeID) then
        setBG(rag, BG_NAMES[side], 1)
        setRagState(rag, side, 1)
        rag["_sd" .. side] = true
        return true
    end
    return false
end
```

替换 `tryFootHangOrDrop`（去掉悬挂分支，只保留掉落）：
```lua
local function tryFootOrDrop(rag, side, baseVel)
    if skipByGroundDrop(rag, side) or rag["_sd" .. side] then return end
    if currentRagState(rag, side) == 1 then setBG(rag, BG_NAMES[side], 1); return end
    local dropP = parseLR(cv_exp_p, 0.50, 0.50)[side]
    if (math.random() * 1000) > (dropP * 1000) then return end
    local pos = bonePos(rag, BONE_NAMES[side])
    if not pos then return end
    setBG(rag, BG_NAMES[side], 1)
    local drop = spawnShoe(side, pos, baseVel, rag, false, rag._<MOD>SourceOwner, rag._<MOD>SourceLife)
    if IsValid(drop) then
        setRagState(rag, side, 1); rag["_sd" .. side] = true
    else
        setBG(rag, BG_NAMES[side], 0)
    end
end
```

替换 `applyRagdoll`（简化版，无悬挂初始化）：
```lua
local function applyRagdoll(source, rag)
    if not cv_enabled:GetBool() then return end
    if not IsValid(source) or not IsValid(rag) or not isRagdoll(rag) then return end
    if processed[rag] then return end
    if not EQ.ApplyRagdollSnapshot(rag, source) then return end
    processed[rag] = true
    rag._sdL = false
    rag._sdR = false
    local baseVel = source._sd_attVel or (source.GetVelocity and source:GetVelocity()) or vector_origin
    for _, side in ipairs({"L","R"}) do
        if EQ.HasDrop(source, SLOTS[side], rag._<MOD>SourceLife) then
            setBG(rag, BG_NAMES[side], 1)
            setRagState(rag, side, 1)
            rag["_sd" .. side] = true
        else
            tryFootOrDrop(rag, side, baseVel)
        end
    end
end
```

替换 `_RagDamage` 钩子中的状态判断（简化版，无悬挂态）：
```lua
    local actualBG = getBG(rag, BG_NAMES[side])
    if actualBG == 1 then
        setRagState(rag, side, 1); rag["_sd" .. side] = true; return
    elseif actualBG == 0 then setRagState(rag, side, 0)
    else return end
    tryFootOrDrop(rag, side, baseVel)
```

替换 `OnEntityCreated` 延迟初始化（简化版）：
```lua
hook.Add("OnEntityCreated", "<MOD>_InitRagdoll", function(ent)
    if not cv_enabled:GetBool() or not IsValid(ent) or not isRagdoll(ent) then return end
    timer.Simple(0, function()
        if not IsValid(ent) or not isTargetModel(ent) then return end
        if processed[ent] then return end
        local owner = ent._<MOD>SourceOwner
        local lifeID = ent._<MOD>SourceLife
        if not IsValid(owner) or not lifeID then return end
        for _, side in ipairs({"L","R"}) do
            local bg = getBG(ent, BG_NAMES[side])
            if bg == 1 then
                setRagState(ent, side, 1); ent["_sd" .. side] = true
            end
        end
    end)
end)
```

ConVar 简化（去掉悬挂和自动掉落概率）：
```lua
local cv_exp_p = CreateConVar("<前缀>_ExpP", "0.50,0.50", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
local cv_death_p = CreateConVar("<前缀>_DeathP", "0.50,0.50", {FCVAR_REPLICATED, FCVAR_ARCHIVE})
```

spawnShoe 中的 NWInt state 也改为 1：
```lua
e:SetNWInt("<MOD>_State", 1)
```

