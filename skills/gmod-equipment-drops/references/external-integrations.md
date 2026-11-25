---
name: external-integrations
description: 为已经安装特定 GMod 手环或布娃娃插件的目标项目提供可选适配；普通掉落和拾取系统不依赖本参考。
---

# 可选外部集成

只有确认目标项目已经安装对应第三方 addon，并读取了它的实际代码后，才使用本参考。默认掉落/拾取模板不写入任何第三方 NW 键、追踪表或客户端布娃娃适配。

## EkuTrack 手环追踪

适用前提：

- 目标项目确实安装了 `An Intelligent Bracelet` 或兼容的 `EkuTrack` 实现。
- 已在项目中发现追踪表、注册函数或客户端检测逻辑。
- 用户明确要求掉落物出现在手环标记中。

先确认实际接口。不要仅根据旧示例猜测文件名、表名或字段：

```text
搜索关键词：
EKU_TRACK_MODELS
EkuTrack
wrist band
materials/vgui/wrist
```

确认接口后，按目标项目格式登记掉落物模型路径。下面是**结构示例**，不是可直接复制的项目配置：

```lua
local TRACK_MODELS = {
    ["models/<你的addon>/<drop_model>.mdl"] = {
        color = Color(0, 200, 255),
        icon = "supply",
        category = "<实际类别>",
    },
}
```

检查：

- 模型路径使用目标项目实际存在的小写路径。
- 颜色、图标和类别符合目标手环 addon 的真实字段。
- 掉落系统不因手环不存在而报错。
- 没有把本项目专用模型路径写进通用掉落模板。

## XDEFC 布娃娃客户端同步

默认客户端模板同步标准 `prop_ragdoll` 实体，并使用状态模块广播的布娃娃快照。这已经覆盖服务端布娃娃的常规场景。

只有目标项目明确使用 `XDEFC`，且客户端布娃娃由 `ply.xdefc_rag` 单独创建时，才增加额外适配。先搜索：

```text
XDEFC
xdefc_rag
CreateClientsideRagdoll
```

适配原则：

- 以服务端状态模块为准，不新建第二套掉落状态。
- 找到真实 XDEFC 布娃娃后，复用同一套 `SLOT_LIST`、bodygroup 名称和快照值。
- 在布娃娃创建后的多个延迟点重试，避免客户端模型尚未准备好。
- 找不到 `ply.xdefc_rag` 时直接跳过，不生成错误日志风暴。
- 保留标准 `prop_ragdoll` 同步路径作为回退。

如果目标项目没有 XDEFC，请删除这类适配，不要保留依赖不存在的插件字段的代码。
