返回 [掉落系统入口](../SKILL.md)。模板占位符需按实际项目替换。

## 可选外部集成

默认掉落模板不写入手环追踪表、第三方布娃娃字段或对应插件专属 NW 键。

只有目标项目已经安装相应 addon、项目中确实存在对应接口，且用户明确要求集成时，才读取 [可选外部集成](external-integrations.md)。找不到接口时保持默认模板，不要根据示例猜测文件名或字段名。

## 交付前检查清单（生成代码后必须逐条验证）

- [ ] 状态模块用 `0_` 前缀，掉落脚本用字母开头
- [ ] 所有 `<>` 占位符已替换为实际值
- [ ] `NET_SLOTS`（服务端）与 `SLOT_LIST`（客户端）逐项一致
- [ ] `RegisterSlot` 的 `maxState` / `dropState` 是字面量数字，不是变量名
- [ ] 所有概率通过 ConVar 控制，无硬编码数值
- [ ] 模式 A 的 `EntityTakeDamage` 有 `isRagdoll(ent) then return end` 过滤
- [ ] 模式 B 的 `applyRagdoll` 是替换后的版本（遍历 ITEMS + `_tr_` 标记）
- [ ] 模式 B 的 `impulse` 是 4 参数版本 `(ph, refEnt, vel, ang)`
- [ ] 模式 C 的 `bonePos` 骨骼不存在时返回 nil，不回退到 `ent:GetPos()`
- [ ] 拾取钩子中 `UnregisterDrop` 在 `SafeRemoveEntity` 之前
- [ ] 模式 C 简化版 `RegisterSlot` 用 `maxState=1, dropState=1`
- [ ] 模式 C 简化版无 `scheduleAutoDrop` / `forceDropIfHalfHang` / `_sd_hang_side`
- [ ] 所有 hook name 全局唯一，用 `<MOD>_<功能>` 格式
- [ ] 掉落物设置了 `<MOD>_EquipmentType`、`<MOD>_Owner`、`<MOD>_ModelPath`、`<MOD>_BGName`
- [ ] 如目标项目要求手环追踪，已读取实际集成接口；否则未加入第三方专用字段
- [ ] 日志受 `<MOD>_Log` ConVar 控制，默认关闭
- [ ] 掉落的是眼镜时，确认是否需要 DOF 效果；需要时读取 [DOF 参考](glasses-dof.md)

## 关键坑点

1. **布娃娃过滤**: 活体 `EntityTakeDamage` 必须有 `if isRagdoll(ent) then return end`，防止布娃娃同时触发活体处理。

2. **拾取顺序**: `EQ.UnregisterDrop(best)` 必须在 `SafeRemoveEntity(best)` 之前。SafeRemoveEntity 保持 IsValid=true 一帧。

3. **CanRagdollEnterDropCheck (v15)**: 布娃娃伤害处理前先调用此 API，防止 bg 已经是掉落态时重复生成掉落物。

4. **ApplyRagdollSnapshot**: 布娃娃创建时必须调用，它负责 BindRagdoll + 设置 bodygroup + 广播快照。内部已包含多延迟重发（0.05~2.00s）。

5. **netRagdollSnapshot**: `SetRagdoll` 内部已自动调用，无需手动广播。客户端通过 `<MOD>_RagdollSnapshot` 网络消息接收。

6. **NW 字符串**: 掉落物应设置 `<MOD>_EquipmentType`、`<MOD>_Owner`、`<MOD>_ModelPath`、`<MOD>_BGName` 供本项目客户端识别。第三方手环字段只在确认目标插件接口后另行添加。

7. **setBG 唤醒物理**: ragdoll 的 bodygroup 变更后必须 `phys:Wake()` 才能刷新渲染网格。

8. **变量作用域**: `applyRagdoll` 中用 `rag`（函数参数），不是 `ent`（未定义）。

9. **Hook 名称唯一**: 每个 hook.Add 的第三个参数（hook name）必须全局唯一，用 `<MOD>_<功能>` 格式。

10. **MODELS 表共享**: 多个脚本注册同一个模型没关系，`EQ.RegisterModel` 用 `M.MODELS[model] = true` 幂等。

11. **脚本加载依赖**：文件名前缀只辅助同目录排序，不保证跨 realm、热重载和外部脚本的依赖就绪。通过实际 include/初始化流程保证状态模块先就绪；接口缺失应明确报错，重复初始化应幂等。验证冷启动、热重载及客户端晚加入，不能认为 client 目录天然无依赖问题。

12. **第三方客户端同步必须显式启用**: 默认客户端模板同步标准 `prop_ragdoll`，不依赖 XDEFC 或其他外部布娃娃插件。只有目标项目确实使用该插件时，才按 [可选外部集成](external-integrations.md) 添加适配，并保留标准 `prop_ragdoll` 回退。

13. **槽位顺序契约（最容易出隐蔽 bug 的一处）**: 服务端 `netRagdollSnapshot` 按 `NET_SLOTS` 的位置顺序写出，客户端按 `SLOT_LIST` 的位置顺序读回，两组数字一一对应。**绝不能让服务端改用 `M.SLOTS`** —— 那是 `RegisterSlot` 的调用顺序，取决于掉落脚本的文件加载顺序，客户端无法复现。顺序一旦错位，客户端会把 A 槽位的状态套到 B 槽位的 bodygroup 上，症状是「掉落物正常生成了，但模型上消失的是另一个部位」或「掉的部位不对」。改动槽位时 `NET_SLOTS` 与 `SLOT_LIST` 必须同步改。

14. **骨骼名必须与模型完全一致**: 模板用 `ent:LookupBone(boneName)` 定位，找不到时返回 nil，调用方跳过该部位并 `ErrorNoHalt` 打出骨骼名。**不要为了"能跑"改成回退到 `ent:GetPos()`** —— 那样 L/R 会拿到同一个坐标，`DistToSqr` 恒等，`dl < dr` 恒为 false，结果是**永远只掉右侧**，而且掉落物生成在模型原点。自绑骨骼的 playermodel 经常不是 `ValveBiped.Bip01_*`，必须用 HLMV 确认。

15. **bodygroup 状态数必须来自模型本身**: `RegisterSlot(slot, bg, maxState, dropState)` 里的两个数字，以及模板里所有 `setBG(ent, bg, N)` 的 N，都必须对应模型真实的 submodel 索引。示例中的三态是「0=穿戴、1=悬挂、2=隐藏」；如果模型只有两个 submodel，设成 2 就是越界值，渲染结果未定义（常见是回落到 submodel 0 = 装备还在）。生成脚本前必须先问清每个 bodygroup 有几个值、各是什么含义。

16. **生成骨架里的 `<maxState>` / `<dropState>` 必须替换成数字**: 早期版本这里写的是裸标识符 `maxState, dropState`，它们是未定义全局 → nil → `RegisterSlot` 静默兜底成 1 → 「消失」退化成「悬挂」。任何形如 `<xxx>` 的占位符都必须替换掉才能交付。

17. **模式 B 必须替换 `applyRagdoll`**: 模式 B 说「在模式 A 基础上替换」，但除了 ITEMS / helpers / hooks 外，**`applyRagdoll` 也必须替换**。模式 A 的 `applyRagdoll` 只处理单个 SLOT，模式 B 的版本遍历整个 ITEMS 表并使用 `_tr_` per-item 标记。如果漏替换，restore() 只会恢复一个物品的状态，其余物品的 bodygroup 不会同步。

18. **模式 B 的 `impulse` 签名不同**: 模式 A 是 `(phys, baseVel)` 两参数，模式 B 是 `(ph, refEnt, vel, ang)` 四参数（基于实体朝向计算抛射方向）。模式 B 的 `spawnItem` 调用 `impulse(ph, owner, vel, it.ang)` 传 4 个参数，如果保留模式 A 的 2 参数版本，额外参数会被静默丢弃，掉落物方向计算错误。

