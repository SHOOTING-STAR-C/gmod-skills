返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。

## 完整模板: 模式 B (headshot)

> **严格要求**：在模式 A 基础上替换所有标注部分，包括 `applyRagdoll`（坑点 #17）和 `impulse` 签名（坑点 #18）。不可遗漏任何替换块。

在模式 A 基础上，替换以下部分：

### 1. 物品配置改为 ITEMS 表

```lua
-- 物品配置改为 ITEMS 表
local ITEMS = {
    {
        slot = "Ear", key = "hp",
        item_model = "models/path/to/ear.mdl",
        bg_name = "Circle",
        head_bone = "ValveBiped.Bip01_Head1",
        vel = 220, ang = 80,
        rag_head_r = 14,
        itemType = "Headphone"
    },
    {
        slot = "Hat", key = "lt",
        item_model = "models/path/to/hat.mdl",
        bg_name = "Hat",
        head_bone = "ValveBiped.Bip01_Head1",
        vel = 220, ang = 80,
        rag_head_r = 14,
        itemType = "Lituer"
    },
}
for _, it in ipairs(ITEMS) do EQ.RegisterSlot(it.slot, it.bg_name, 1, 1) end

-- 概率 ConVar（可在游戏中修改）
local cv_live_p = {}
local cv_rag_p  = {}
for _, it in ipairs(ITEMS) do
    cv_live_p[it.slot] = CreateConVar("<前缀>_" .. it.key .. "_Headshot", 0.4, {FCVAR_REPLICATED, FCVAR_ARCHIVE})
    cv_rag_p[it.slot]  = CreateConVar("<前缀>_" .. it.key .. "_Death",    0.3, {FCVAR_REPLICATED, FCVAR_ARCHIVE})
end
```

辅助函数改为接受 `name` 参数（与模式 A 不同）：
```lua
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
-- 骨骼不存在返回 nil —— 调用方跳过并打日志，不要回退到模型原点。
local warnedBones = {}
local function bonePos(ent, boneName)
    if not IsValid(ent) then return nil end
    local id = ent:LookupBone(boneName)
    if id then
        local p, a = ent:GetBonePosition(id)
        if p then return p, a end
    end
    if not warnedBones[boneName] then
        warnedBones[boneName] = true
        EQ.Warn("模型缺少骨骼 " .. tostring(boneName)
            .. " —— 该部位不会掉落。请用 HLMV 核对该模型的实际骨骼名。")
    end
    return nil
end
-- 模式 B 特有：从实体获取朝向（用于 impulse 方向计算）
local function entityForward(ent)
    if IsValid(ent) and ent.GetForward then
        local f = ent:GetForward()
        if isvector(f) and f:LengthSqr() > 0 then
            return f:GetNormalized()
        end
    end
    return Vector(0,1,0)
end
```

spawnItem 签名与模式 A 不同，**第一个参数是 item 表**。impulse 也改为 4 参数版本（基于实体朝向计算方向）：
```lua
local function safeSpawnPos(src, outward)
    local start = src + (outward or VectorRand():GetNormalized() * 2)
    local tr = util.TraceHull({
        start = start + Vector(0,0,8), endpos = start + Vector(0,0,-64),
        mins = Vector(-2,-2,-2), maxs = Vector(2,2,2), mask = MASK_SOLID_BRUSHONLY
    })
    return tr.Hit and (tr.HitPos + tr.HitNormal * 1.5) or start
end

-- 替换模式 A 的 impulse（4 参数版本，基于 refEnt 朝向）
local function impulse(ph, refEnt, vel, ang)
    if not IsValid(ph) then return end
    local fwd = entityForward(refEnt)
    fwd.z = 0
    if fwd:LengthSqr() < 0.0001 then fwd = Vector(0,1,0) end
    fwd:Normalize()
    local dir = -fwd + Vector(0,0,1.6)
    dir:Normalize()
    local speed = vel or 220
    if dir.z * speed < speed then
        dir.z = 1
        dir:Normalize()
    end
    ph:SetVelocity(dir * speed)
    local av = ang or 80
    ph:AddAngleVelocity(Vector(0,0,1) * av + Vector(1,0,0) * (av * 0.8))
end

local function spawnItem(it, pos, ang, vel, owner, lifeID)
    local e = ents.Create("prop_physics")
    if not IsValid(e) then return nil end
    e:SetModel(it.item_model)
    prepPhys(e)
    local lay = isangle(ang) and Angle(ang.p, ang.y, ang.r) or Angle(0,0,0)
    lay:RotateAroundAxis(lay:Right(), 25)
    e:SetAngles(lay)
    e:SetPos(safeSpawnPos(pos or vector_origin))
    e:Spawn()
    SafeRemoveEntityDelayed(e, cv_life:GetFloat())
    local ph = e:GetPhysicsObject()
    if IsValid(ph) then impulse(ph, owner, vel, it.ang) end
    if IsValid(owner) then
        e:SetNWString("<MOD>_EquipmentType", it.itemType)
        e:SetNWEntity("<MOD>_Owner", owner)
        e:SetNWString("<MOD>_ModelPath", it.item_model)
        e:SetNWString("<MOD>_BGName", it.bg_name)
        EQ.RegisterDrop(owner, it.slot, e, lifeID or EQ.GetLife(owner))
    end
    drops[e] = true
    return e
end

local function dropLive(ent, it)
    if EQ.Get(ent, it.slot) == 1 or EQ.HasDrop(ent, it.slot) then return false end
    local pos, ang = bonePos(ent, it.head_bone)
    if not pos then return false end
    local e = spawnItem(it, pos + Vector(0,0,8), ang, it.vel, ent, EQ.GetLife(ent))
    if not IsValid(e) then return false end
    EQ.Set(ent, it.slot, 1); setBG(ent, it.bg_name, 1)
    return true
end
local function dropRagdoll(rag, it)
    local owner = rag._<MOD>SourceOwner
    local lifeID = rag._<MOD>SourceLife
    if not IsValid(owner) or not lifeID then return false end
    if EQ.GetRagdoll(rag, it.slot) == 1 then return false end
    if EQ.HasDrop(owner, it.slot, lifeID) then return false end
    local pos, ang = bonePos(rag, it.head_bone)
    if not pos then return false end
    local e = spawnItem(it, pos + Vector(0,0,8), ang, it.vel, owner, lifeID)
    if not IsValid(e) then return false end
    setBG(rag, it.bg_name, 1); EQ.SetRagdoll(rag, it.slot, 1)
    return true
end
```

**必须替换模式 A 的 `applyRagdoll`**（模式 B 需要遍历 ITEMS + `_tr_` 标记）：
```lua
local function applyRagdoll(source, rag)
    if not cv_enabled:GetBool() or not isTargetModel(source) or not isRagdoll(rag) then return end
    if processed[rag] then return end
    if not EQ.ApplyRagdollSnapshot(rag, source) then return end
    processed[rag] = true
    -- 初始化 _tr_ 标记：记录每个物品当前的 ragdoll 状态
    for _, it in ipairs(ITEMS) do
        local st = EQ.GetRagdoll(rag, it.slot)
        rag["_tr_" .. it.slot] = (st == 1)
    end
    local function restore()
        if not IsValid(rag) then return end
        for _, it in ipairs(ITEMS) do
            local desired = EQ.GetRagdoll(rag, it.slot)
            if EQ.HasDrop(source, it.slot, rag._<MOD>SourceLife) then
                desired = 1
                EQ.SetRagdoll(rag, it.slot, 1)
            end
            setBG(rag, it.bg_name, desired)
        end
        if rag.SetupBones then rag:SetupBones() end
        if rag.InvalidateBoneCache then rag:InvalidateBoneCache() end
    end
    restore()
    timer.Simple(0.05, restore)
    timer.Simple(0.15, restore)
    timer.Simple(10, function() if IsValid(rag) then processed[rag] = nil end end)
end
```

活体触发钩子（爆头检测，ScalePlayerDamage 只对 Player，天然不触发布娃娃）：
```lua
hook.Add("ScalePlayerDamage", "<MOD>_PlayerHead", function(ply, hitgroup)
    if not cv_enabled:GetBool() or hitgroup ~= HITGROUP_HEAD or not isTargetModel(ply) then return end
    for _, it in ipairs(ITEMS) do
        if EQ.Get(ply, it.slot) == 0 and not EQ.HasDrop(ply, it.slot) then
            if (math.random() * 1000) <= (cv_live_p[it.slot]:GetFloat() * 1000) then dropLive(ply, it) end
        end
    end
end)
hook.Add("ScaleNPCDamage", "<MOD>_NPCHead", function(npc, hitgroup)
    if not cv_enabled:GetBool() or hitgroup ~= HITGROUP_HEAD or not isTargetModel(npc) then return end
    for _, it in ipairs(ITEMS) do
        if EQ.Get(npc, it.slot) == 0 and not EQ.HasDrop(npc, it.slot) then
            if (math.random() * 1000) <= (cv_live_p[it.slot]:GetFloat() * 1000) then dropLive(npc, it) end
        end
    end
end)
```

布娃娃触发钩子（头部距离检测 + bodygroup 实际值检查）：
```lua
local function dmgNearBone(rag, dmginfo, it)
    local bpos = select(1, bonePos(rag, it.head_bone))
    local hitPos = dmginfo and dmginfo:GetDamagePosition() or nil
    if not bpos or not hitPos or hitPos == vector_origin then return false end
    return bpos:DistToSqr(hitPos) <= (it.rag_head_r or 14) ^ 2
end

hook.Add("EntityTakeDamage", "<MOD>_RagHead", function(rag, dmginfo)
    if not cv_enabled:GetBool() or not isRagdoll(rag) or not isTargetModel(rag) then return end
    for _, it in ipairs(ITEMS) do
        local actualBG = getBG(rag, it.bg_name)
        if actualBG == 1 then EQ.SetRagdoll(rag, it.slot, 1); continue
        elseif actualBG ~= 0 then continue end
        EQ.SetRagdoll(rag, it.slot, 0)
        if not dmgNearBone(rag, dmginfo, it) then continue end
        if (math.random() * 1000) > (cv_rag_p[it.slot]:GetFloat() * 1000) then continue end
        dropRagdoll(rag, it)
    end
end)
```

拾取钩子（遍历 ITEMS 匹配 slot）：
```lua
hook.Add("PlayerButtonDown", "<MOD>_Pickup", function(ply, button)
    if button ~= KEY_F or not IsValid(ply) then return end
    local best, bestDist = nil, 80
    for ent in pairs(drops) do
        if IsValid(ent) then
            local owner, slot, lifeID = EQ.GetDropInfo(ent)
            if owner == ply and lifeID == EQ.GetLife(ply) then
                local d = ply:GetPos():Distance(ent:GetPos())
                if d <= bestDist then best = ent; bestDist = d end
            end
        end
    end
    if not IsValid(best) then return end
    local owner, slot, lifeID = EQ.GetDropInfo(best)
    if owner ~= ply or lifeID ~= EQ.GetLife(ply) then return end
    local it
    for _, v in ipairs(ITEMS) do if v.slot == slot then it = v; break end end
    if not it then return end
    EQ.Set(ply, it.slot, 0); setBG(ply, it.bg_name, 0)
    local effect = EffectData(); effect:SetOrigin(best:GetPos())
    util.Effect("item_respawn", effect)
    ply:EmitSound("items/itempickup.wav", 75, 100, 0.5)
    EQ.UnregisterDrop(best); drops[best] = nil; SafeRemoveEntity(best)
end)
```

