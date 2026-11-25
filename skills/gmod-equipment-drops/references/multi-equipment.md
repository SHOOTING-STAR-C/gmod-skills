返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。

## 通用多部件掉落系统：部位概率、事件预算、左右独立

当一个 playermodel 有多个可拆 bodygroup，需要按身体部位掉落时，**不要对每个部件独立掷骰**。部件越多，整体概率越失真：

```text
5 个部件，每件 0.10
至少掉一件 = 1 - 0.9^5 ≈ 41%
```

正确模型是两层：

```text
第一层：每次受击事件只掷一次总概率
第二层：总概率成功后，按部位块选择掉哪一件
```

左右鞋是独立部位块，左右脚各自掷骰。

### 部位块划分

先按实际 bodygroup 命名划分，不要照抄示例。常见划分：

```text
head   头部 / 发饰
torso  上身 / 服装
arms   手臂 / 手部
lower  下身 / 腿部
feet   鞋子 / 鞋饰
```

每次受击：

```text
事件总概率失败 → 所有部位块都不掉
事件总概率成功 → 每个候选部位块最多掉 1 件
```

部位块内按外层优先排序。枪击时先取伤害点附近的骨骼候选，再按伤害位置决定哪些部位块参与。

### 左右独立

鞋子、左右腿环、左右手臂等部件如果实际是独立 bodygroup：

```text
左脚单独掷骰
右脚单独掷骰
```

概率 ConVar 使用 `L,R` 格式。

### 共享事件预算

同一个受击可能在同帧触发多次 `EntityTakeDamage`（其他插件、布娃娃倒地、伤害拆分）。只限制单次 hook 不够，要用时间窗口合并：

```lua
EQ.AllowDropEvent(ent, chance)   -- 每个窗口只掷一次总概率
EQ.TakeDropEventSlot(ent)        -- 每个窗口累计掉落数量
EQ.ReleaseDropEventSlot(ent)     -- 生成失败时归还预算
```

ConVar 建议：

```text
<前缀>_DropEventMax
<前缀>_DropWindow
```

`DropEventMax` 是服装和鞋子的共享总预算。服装先使用完时，鞋子会出现：

```text
Shoe budget exhausted L/R
```

如果希望鞋子和服装互不抢预算，需要给鞋子单独预算，但要明确这会提高单次事件总掉落数。

### 状态机是拾取权威

创建掉落物必须：

```lua
local registered = EQ.RegisterDrop(owner, slot, entity, lifeID)
if not registered then
    SafeRemoveEntity(entity)
    return nil
end
```

不要把注册失败的对象加入本地追踪表，也不要在注册失败时隐藏 bodygroup。

`FindDrop()` 不应因为实体暂时 `IsInWorld() == false` 就删除注册项。只清理真正无效的实体：

```lua
if not IsValid(drop) then
    bucket[drop] = nil
end
```

否则刚注册的掉落实体在拾取时会被误判为 `no registered drop`。拾取必须通过状态机查询，不要用脚本本地表绕过状态机。

### 生成失败回滚

bodygroup 只能在实体生成成功后隐藏，并且下一帧复核：

```lua
if not IsValid(item)
    or not item:IsInWorld()
    or not IsValid(item:GetPhysicsObject()) then
    EQ.UnregisterDrop(item)
    SafeRemoveEntity(item)
    setWornState(srcEnt, part, prevState)
end
```

否则会出现“衣服消失了，但地上没有掉落物”。

### 拾取后下一帧再同步

拾取顺序：

```text
设置状态 / bodygroup
→ UnregisterDrop
→ 删除实体
→ 下一帧再次设置状态 / bodygroup
```

否则服务端的 `applyLiving()` 或客户端快照可能把 bodygroup 又压回掉落态，表现为“捡起来消失了，没穿上”。

### 颜色同步

掉落时读取原穿戴者：

```lua
local skin = source:GetSkin()
```

规则：

- 读取成功：掉落物使用相同 skin
- 读取失败：默认皮肤 `0`
- ragdoll：优先读取原玩家 / NPC
- 异常值：回退 `0`
- 模型支持 `$texturegroup`：拾取时恢复
- 模型不支持换色：固定 `0`

### 物理回调

不要在 damage/physics 回调中调用 `PhysicsInit`：

```text
Cannot destroy physics in a physics callback
```

正确流程：

```text
SetModel
Spawn
SetPos
检查 GetPhysicsObject
配置 MoveType / Solid / CollisionGroup
再 SetPos
```

### 唯一文件与 ConVar 命名

GMod 的 addon 文件系统会把不同 addon 的同路径文件合并。如果两个 addon 都有：

```text
lua/autorun/server/Footwear.lua
lua/autorun/server/Clothing.lua
```

只有一个会生效，表现为脚本无日志、ConVar 不存在、命令不存在。

所有运行时文件、ConVar、命令、调试文件都应使用 addon / 模型专属前缀：

```text
<前缀>_State.lua
<前缀>_Clothing.lua
<前缀>_Footwear.lua
<前缀>_prop
<前缀>_HitP
<前缀>_DropEventMax
<前缀>_Log
<前缀>_shoe_debug
```

客户端 `lua_run` 不能检查服务端文件；服务端文件常以 `if CLIENT then return end` 开头。检查服务端命令要用服务器控制台或 `rcon`。

### 调试日志

建议同时输出控制台日志和文件日志：

```text
<前缀>_Log 1
data/<前缀>_debug.txt
```

关键日志：

```text
<前缀> generated
<前缀> drop ...
<前缀> drop skipped ...
<前缀> budget exhausted
生成后失效
找不到骨骼
```

### 交付前检查

- [ ] 服装使用事件总概率，不是每件独立掷骰
- [ ] 每个部位块最多掉 1 件
- [ ] 鞋子左右独立掷骰
- [ ] 服装与鞋子共享事件预算
- [ ] 同一次受击的多次回调被时间窗口合并
- [ ] 掉落创建必须 `RegisterDrop` 成功
- [ ] `FindDrop` 不因 `IsInWorld` 暂时 false 删除注册项
- [ ] 生成失败下一帧恢复 bodygroup
- [ ] 拾取后下一帧再次同步状态 / bodygroup
- [ ] 颜色读取失败回退默认皮肤
- [ ] 多状态 bodygroup 记录并恢复之前状态
- [ ] 所有运行时文件使用唯一前缀
- [ ] 服务端 `NET_SLOTS` 与客户端 `SLOT_LIST` 一致
- [ ] 调试文件日志和测试命令可用

### 外部改模接口

模型选择器、管理员工具、皮肤菜单如果直接调用 `ent:SetBodygroup()`，会被状态机的 `applyLiving()` 在下一帧改回旧状态。

状态模块应提供统一接口：

```lua
EQ.OverrideBodygroup(ent, slot, state)
```

内部同时更新：

```lua
st.values[slot] = state
ent:SetBodygroup(idx, state)
```

如果外部工具按 bodygroup 索引修改：

```lua
EQ.OverrideBodygroupIndex(ent, index, state)
```

如果外部工具需要临时接管某个槽位：

```lua
EQ.PauseSlotSync(ent, slot)
-- 外部工具设置 bodygroup
EQ.ResumeSlotSync(ent, slot)
```

暂停期间状态机不再覆盖该槽位。恢复前应先调用 `OverrideBodygroup()` 或 `EQ.Set()` 同步内部状态，避免恢复后再次覆盖。

暂停只解决显示冲突，不改变掉落/拾取逻辑；`RegisterDrop()` 仍然是掉落物是否存在的唯一权威。

切换 playermodel 时，先调用 `EQ.ResetLife(ent)` 清空上一个模型的生命周期、事件预算和同步暂停状态，否则旧的 bodygroup 掉落状态会让新模型的部件瞬间隐藏。
