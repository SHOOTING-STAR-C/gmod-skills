---
name: model_extract
description: 从 Garry's Mod / Source Engine 模型中提取 bodygroup 子网格，制作独立装备或掉落道具模型。适用于眼镜、帽子、鞋子、面具等部件的拆分、静态化、碰撞制作、studiomdl 编译和游戏内验证。
---

# Source 模型 bodygroup 提取

## 适用场景

- 角色模型已经有独立 bodygroup，但需要把该部件做成可单独生成的 `prop_physics`。
- 需要在 Blender 中单独编辑眼镜、帽子、面具、鞋子等子网格。
- 需要为已有角色部件补做掉落物、独立装备或展示模型。

如果只是在原角色身上显示/隐藏部件，**不需要提取模型**，直接：

```lua
local idx = ent:FindBodygroupByName("<bodygroup名称>")
ent:SetBodygroup(idx, 1) -- 隐藏
ent:SetBodygroup(idx, 0) -- 显示
```

bodygroup 只是同一个 MDL 内部的子网格，不能直接 `Spawn` 成另一个实体；要做地上掉落物才需要独立模型。

## 环境入口

先按 [环境配置](environment.md) 加载工具路径。已有可靠源工程可跳过反编译；没有独立 prop 时沿用下述提取流程。反编译 CLI 的参数随版本不同，示例不是所有 Crowbar 发行版的统一接口，实际调用前检查所配置工具的帮助。

## 工具

1. **Crowbar**：反编译 MDL，查看 QC 和 SMD。
2. **Blender Source Tools**：在 Blender 中导入/导出 SMD/DMX。
3. **Garry's Mod 自带 studiomdl**：编译普通独立模型。
4. **StudioMDL-CE**：处理完整皮肤、复杂 flex 或触发 GMod studiomdl 材质上限的玩家模型。
5. Blender：检查顶点、骨骼权重、材质和原点。

### 共享工具目录

`bakmod` 下的所有模型工作区共用同一套开发工具，不要把工具复制进每个 addon：

```text
GMOD_TOOLS_DIR
```

该值来自技能根目录的 `.env`。不要在 reference 中照搬其他人的盘符或用户名。

其中：

- `Crowbar\Crowbar.exe`：共享的模型反编译工具。
- Blender Source Tools：安装在 Blender 内部，不需要随项目复制。
- `STUDIOMDL_EXE`：Garry's Mod 自带编译器。
- `StudioMDL-CE\x64\cestudiomdl.exe`：推荐用于大模型、完整皮肤和复杂 flex。
- `StudioMDL-CE\x86\cestudiomdl.exe`：兼容性备用；DLL 必须与 exe 同目录。

其他模型需要反编译时，直接调用共享 Crowbar；发布 addon 时排除 `tools/` 和 `work/`。

## 标准提取步骤

### 1. 确认目标模型和 bodygroup

先从项目代码、README 或 QC 中确认：

- 模型路径
- bodygroup 名称
- 状态编号
- 对应 submodel SMD
- 材质路径
- 部件绑定的骨骼

示例表格（所有具体值都必须从目标模型重新读取）：

| 项目 | 值 |
|---|---|
| 原模型 | `<角色模型路径>` |
| bodygroup | `<目标bodygroup名称>` |
| 显示状态 | `0` |
| 隐藏状态 | `1` |
| 子网格 | `<目标SMD文件名>` |
| 材质 | `<部件材质名>` |
| 骨骼 | `<部件绑定的实际骨骼名>` |

### 2. 反编译原模型

使用 Crowbar GUI，或命令行版本：

```text
CrowbarCommandLineDecomp.exe -p "path\model.mdl" -o "path\output"
```

重点查看生成的 QC：

```qc
$bodygroup "<目标bodygroup名称>"
{
    studio "<目标SMD文件名>"
    blank
}
```

同时记录：

- `$cdmaterials`
- `$texturegroup`
- `$surfaceprop`
- 原模型的 `$bbox`、`$illumposition`
- 现有静态道具的 `$staticprop` 和 `$collisionmodel` 写法

### 3. 导入 Blender 检查

在 Blender 中通过 `File -> Import -> Source Engine` 导入目标 SMD。

检查：

- 三角面数量
- 材质槽
- 顶点组/骨骼权重
- 是否只有一个部件骨骼
- 世界包围盒和中心
- 是否有多余的骨骼或网格

如果只是查看，不必修改原场景；可另建 collection 用于导出。

### 4. 判断是否真的需要独立模型

三种情况：

1. **只在角色身上切换**：直接 `SetBodygroup`，不提取。
2. **在 Blender 单独编辑**：导入 SMD 后另存工程或导出子网格。
3. **掉落到地上并拾取**：必须制作独立静态模型。

### 4.1 不适合拆分的情况

不是所有 bodygroup 都应该做成独立模型。提取前先排除以下情况：

- **单状态核心网格**：QC 中只有 `studio "xxx.smd"`、没有 `blank`，或 bodygroup 只有 1 个状态。典型的是身体主体、头部、头发；拆出后原角色会出现缺口，而且会丢失骨骼动画/变形。
- **只需要显示/隐藏**：用途仍是角色身上的换装或 `SetBodygroup` 切换，不需要生成 `prop_physics`。
- **用户明确排除的部件**：即使有 `blank` 状态，只要用户指定不拆（例如指定保留美甲或贴身装饰），就跳过。
- **贴身细节/材质型装饰**：美甲（`nails`）和丝袜（`stockings`）等依附身体轮廓、拆出后没有独立合理形态的部件，默认不拆；除非用户明确要求单独制作。
- **同一部件的变体状态**：如 `ribbon0/ribbon`、`skirt0/skirt`、`stockings/stockings1` 属于同一部件的不同状态/变体，不应当默认当成多个独立零件；除非用户明确要求把每个状态都做成模型。
- **必须持续跟随骨骼动画**：如果部件需要随角色实时弯曲、呼吸、布料模拟或 flex 变形，静态化后会失去效果，应留在原模型中，或改用 attachment/动画方案。
- **没有独立生成需求**：不落地、不拾取、不单独展示的部件，不值得额外承担编译和维护成本。

判断规则：

| 条件 | 处理 |
|---|---|
| 有独立 mesh + 有隐藏/掉落需求 | 可提取 |
| 只需要角色身上切换 | 只用 `SetBodygroup` |
| 单状态身体核心网格 | 不提取 |
| 用户明确排除 | 不提取 |
| 美甲、丝袜等贴身细节/材质型装饰 | 默认不提取 |
| 仅为同一部件的变体状态 | 默认只取默认状态，除非另有要求 |
| 必须保留实时骨骼/布料/flex 动画 | 不做静态独立 prop |

### 5. 制作静态参考 SMD

独立道具通常使用单骨骼静态结构：

```smd
version 1
nodes
0 "static_prop" -1
end
skeleton
time 0
0 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000
end
triangles
...
end
```

处理规则：

- 保留原始三角面、法线、UV 和材质名。
- 将所有顶点骨骼改为 `0`。
- 将权重字段改为 `1 0 1.000000`。
- 根据用途平移顶点：
  - 掉落道具：原点平移到部件骨骼或包围盒中心。
  - 仅编辑：可保留原坐标。
- 不要保留原角色的整套骨骼，除非确实需要动画。

Source SMD 顶点字段顺序：

```text
bone  pos.x pos.y pos.z  normal.x normal.y normal.z  u v  link_count bone_link weight
```

单骨骼静态网格通常写成：

```text
0 x y z nx ny nz u v 1 0 1.000000
```

### 6. 制作碰撞 SMD

简单装备可以使用包围盒或低模凸包：

```smd
version 1
nodes
0 "static_prop" -1
end
skeleton
time 0
0 0 0 0 0 0 0
end
triangles
phy
...
end
```

注意：

- 碰撞网格使用 `phy` 材质。
- 不需要复杂渲染法线，但顶点顺序必须组成闭合几何体。
- 眼镜等小部件可以先用包围盒，游戏内手感不好再细化。

### 7. 编写 QC

参考已有静态道具，至少包含：

```qc
$modelname "glasses/my_glasses.mdl"
$staticprop

$bodygroup "glasses"
{
    studio "glasses_ref.smd"
}

$surfaceprop "Plastic_Box"
$contents "solid"
$cdmaterials "<原模型材质目录>"

$sequence "idle" {
    "anims\idle.smd"
    fadein 0.2
    fadeout 0.2
    fps 30
}

$collisionmodel "glasses_phy.smd"
{
    $mass 5
    $inertia 1
    $concave
    $maxconvexpieces 1
}
```

关键坑点：

- `$sequence` 的左花括号要和 `$sequence "idle"` 放在同一行。
- 动画 SMD 即使是静态模型也要提供，内容可以只有一帧。
- `$cdmaterials` 要和原模型材质目录一致。
- `$staticprop`、`$collisionmodel`、`$definebone` 可参考已成功编译的鞋子 QC。

### 8. 编译

使用 Garry's Mod 自带 studiomdl：

```powershell
. .\scripts\load_gmod_env.ps1
$config = Import-GmodEnv
$studiomdl = Get-GmodEnvValue -Values $config -Name "STUDIOMDL_EXE"
$game = Get-GmodEnvValue -Values $config -Name "GARRYSMOD_DIR"
$qc = "<项目构建目录>\<模型名>.qc"

& $studiomdl -game $game $qc
```

成功后通常生成：

- `.mdl`
- `.vvd`
- `.dx80.vtx`
- `.dx90.vtx`
- `.phy`

将这些文件复制到 addon 的 `models/` 对应目录。

### 9. 验证

至少检查：

1. Crowbar 反编译输出的 QC 是否包含目标 bodygroup。
2. SMD 三角面数量是否和原部件一致。
3. 包围盒、原点是否合理。
4. `.phy` 是否存在。
5. Blender/HLMV 中材质是否正常。
6. 游戏内 `util.IsValidModel`、`ents.Create("prop_physics")` 是否能正常生成。

### 10. 接入掉落系统

若用于掉落，通常需要：

```lua
EQ.RegisterSlot("Glasses", "Glasses", 1, 1)
```

并在以下位置同步添加槽位：

- 服务端 `NET_SLOTS`
- 客户端 `SLOT_LIST`
- 客户端 `SLOT_BG`

掉落时：

```lua
ent:SetBodygroup(glassesIndex, 1)
-- 生成独立眼镜 prop
```

拾取时：

```lua
ent:SetBodygroup(glassesIndex, 0)
-- 删除独立 prop
```

## 附录 A：可复用的静态 SMD 提取脚本

下面的 Python 脚本可以把一个已反编译的部件 SMD 转成单骨骼静态参考模型，并生成简单盒状碰撞模型。

```python
from pathlib import Path

def extract_static_smd(src_path, ref_out, phy_out, offset=(0.0, 0.0, 0.0)):
    lines = Path(src_path).read_text(encoding="utf-8", errors="replace").splitlines()
    start = lines.index("triangles") + 1

    ref = [
        "version 1",
        "nodes",
        '0 "static_prop" -1',
        "end",
        "skeleton",
        "time 0",
        "0 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000",
        "end",
        "triangles",
    ]

    xs, ys, zs = [], [], []
    vertex_count = 0

    for raw in lines[start:]:
        text = raw.strip()
        if text == "end":
            break
        if not text:
            continue

        first = text[0]
        if first.isdigit() or (first == "-" and len(text) > 1 and text[1].isdigit()):
            fields = text.split()
            if len(fields) != 12:
                raise RuntimeError(f"unexpected SMD vertex fields: {text}")

            x = float(fields[1]) - offset[0]
            y = float(fields[2]) - offset[1]
            z = float(fields[3]) - offset[2]
            xs.append(x)
            ys.append(y)
            zs.append(z)

            # Source SMD:
            # bone pos normal uv link_count bone_link weight
            ref.append(" ".join([
                "0",
                f"{x:.6f}", f"{y:.6f}", f"{z:.6f}",
                fields[4], fields[5], fields[6],
                fields[7], fields[8],
                "1", "0", "1.000000",
            ]))
            vertex_count += 1
        else:
            ref.append(text)

    ref.append("end")
    Path(ref_out).write_text("\n".join(ref) + "\n", encoding="utf-8")

    if vertex_count % 3:
        raise RuntimeError("triangle vertex count is not divisible by 3")

    # Simple closed box collision mesh.
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    minz, maxz = min(zs), max(zs)

    corners = [
        (minx, miny, minz), (maxx, miny, minz),
        (maxx, maxy, minz), (minx, maxy, minz),
        (minx, miny, maxz), (maxx, miny, maxz),
        (maxx, maxy, maxz), (minx, maxy, maxz),
    ]
    faces = [
        (0, 2, 1), (0, 3, 2),
        (4, 5, 6), (4, 6, 7),
        (0, 1, 5), (0, 5, 4),
        (1, 2, 6), (1, 6, 5),
        (2, 3, 7), (2, 7, 6),
        (3, 0, 4), (3, 4, 7),
    ]

    phy = [
        "version 1",
        "nodes",
        '0 "static_prop" -1',
        "end",
        "skeleton",
        "time 0",
        "0 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000",
        "end",
        "triangles",
    ]

    for a, b, c in faces:
        phy.append("phy")
        for index in (a, b, c):
            x, y, z = corners[index]
            phy.append(
                f"0 {x:.6f} {y:.6f} {z:.6f} "
                "0.000000 0.000000 1.000000 0.000000 0.000000"
            )

    phy.append("end")
    Path(phy_out).write_text("\n".join(phy) + "\n", encoding="utf-8")

    print({
        "triangles": vertex_count // 3,
        "bbox": ((minx, miny, minz), (maxx, maxy, maxz)),
    })
```

调用示例：

```python
extract_static_smd(
    r"decompiled\Glasses.smd",
    r"build\glasses_ref.smd",
    r"build\glasses_phy.smd",
    offset=(0.0, 0.769511, 60.080860),
)
```

`offset` 的选择：

- 需要掉落 prop 以部件骨骼为原点：减去骨骼世界坐标。
- 只需要把模型居中：减去包围盒中心。
- 仅在 Blender 中编辑：可以传 `(0, 0, 0)`。

## 附录 B：Blender 检查脚本

导入 SMD 后可用下面的脚本检查数量、材质和包围盒：

```python
import bpy, mathutils

path = r"decompiled\Glasses.smd"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.smd(filepath=path, doAnim=False, createCollections=False)

mesh = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
corners = [mesh.matrix_world @ mathutils.Vector(corner) for corner in mesh.bound_box]

xs = [v.x for v in corners]
ys = [v.y for v in corners]
zs = [v.z for v in corners]

print({
    "object": mesh.name,
    "vertices": len(mesh.data.vertices),
    "polygons": len(mesh.data.polygons),
    "materials": [mat.name for mat in mesh.data.materials],
    "bbox_min": (min(xs), min(ys), min(zs)),
    "bbox_max": (max(xs), max(ys), max(zs)),
})
```

检查重点：

- 三角面数量是否和原 bodygroup 一致。
- 是否只有目标材质。
- 是否只有目标骨骼有权重。
- 包围盒是否包含整副眼镜/帽子/鞋子。
- 是否需要平移原点。

## 附录 C：完整 QC 模板

```qc
$modelname "glasses/example_glasses.mdl"

$staticprop

$bodygroup "glasses"
{
    studio "glasses_ref.smd"
}

$surfaceprop "Plastic_Box"
$contents "solid"

$illumposition 0 0 1.3

$cdmaterials "<原模型材质目录>"

$bbox <minx> <miny> <minz> <maxx> <maxy> <maxz>
$cbox 0 0 0 0 0 0

$definebone "static_prop" "" 0 0 0 0 0 0 0 0 0 0 0 0

$sequence "idle" {
    "anims\idle.smd"
    fadein 0.2
    fadeout 0.2
    fps 30
}

$collisionmodel "glasses_phy.smd"
{
    $mass 5
    $inertia 1
    $damping 0
    $rotdamping 0
    $rootbone " "
    $concave
    $maxconvexpieces 1
}
```

静态动画 SMD：

```smd
version 1
nodes
  0 "static_prop" -1
end
skeleton
  time 0
    0 0.000000 0.000000 0.000000 0.000000 0.000000 -1.570796
end
```

注意：`$sequence "idle" {` 的左花括号必须在同一行。

## 附录 D：编译与验证命令

编译：

```powershell
. .\scripts\load_gmod_env.ps1
$config = Import-GmodEnv
$studiomdl = Get-GmodEnvValue -Values $config -Name "STUDIOMDL_EXE"
$game = Get-GmodEnvValue -Values $config -Name "GARRYSMOD_DIR"
$qc = "<项目构建目录>\<模型名>.qc"

& $studiomdl -game $game $qc
```

成功标志：

- 输出 `Completed "...qc"`
- 生成 `.mdl`
- 生成 `.vvd`
- 生成 `.dx80.vtx` 和 `.dx90.vtx`
- 生成 `.phy`
- 没有 `ERROR`

验证 bodygroup 和包围盒：

1. 用 Crowbar 反编译新生成的 `.mdl`。
2. 检查 QC 是否有 `$bodygroup`、`$collisionmodel`、`$cdmaterials`。
3. 检查参考 SMD 的三角面数量、材质和骨骼。
4. 在 Blender/HLMV 中检查原点和材质。

## 附录 E：常见错误

| 错误 | 原因 | 修复 |
|---|---|---|
| `no animations found` | `$sequence` 的 `{` 换行，或动画 SMD 路径不对 | 把 `{` 放在 `$sequence` 同一行，确认动画文件存在 |
| `unknown command "}"` | bodygroup/sequence 花括号格式不被 studiomdl 接受 | 参考已成功编译的 QC，使用多行 bodygroup、同行动画花括号 |
| SMD only supports 128 bones | 导入了原角色整套骨骼 | 转成单骨骼 `static_prop` |
| 眼镜生成后偏移很远 | 顶点仍保留原角色世界坐标 | 减去头部/部件骨骼位置或包围盒中心 |
| 材质解析警告 | VMT 缺 `}`、材质路径错误或使用了另一份同名材质 | 检查 `$cdmaterials` 和 VMT 文件 |
| prop 没有物理效果 | 缺少 `.phy` 或 collision SMD 不闭合 | 添加 `$collisionmodel` 并检查碰撞面 |
| 模型能编译但游戏里不显示 | 输出没放进 addon 的 `models/`，或发布时漏拷贝 | 检查 `.mdl/.vvd/.vtx/.phy` 是否齐全 |

## 附录 F：验证记录模板

每次提取都记录目标项目的真实数据，不要把其他项目的数值直接复用：

| 项目 | 本次记录 |
|---|---|
| 原模型 | |
| bodygroup | |
| submodel | |
| 三角面 | |
| 材质 | |
| 权重骨骼 | |
| 部件原点偏移 | |
| 本地包围盒 | |
| 新模型路径 | |
| 编译器及版本 | |
| GMod 游戏内验证结果 | |
## 交付前检查清单

- [ ] 原模型 bodygroup 名称和状态编号来自实际 QC/代码
- [ ] 只在需要独立生成时才编译新模型
- [ ] 静态 SMD 的骨骼、权重和顶点字段正确
- [ ] 顶点原点已按使用场景平移
- [ ] 碰撞 SMD 存在且为闭合几何体
- [ ] QC 的 `$sequence` 花括号格式正确
- [ ] `$cdmaterials` 与原模型一致
- [ ] studiomdl 编译成功
- [ ] `.mdl/.vvd/.vtx/.phy` 已放入 addon 的 `models/`
- [ ] 已反编译或在游戏内验证模型
- [ ] 掉落 Lua 的 bodygroup、模型路径和槽位顺序已同步
- [ ] 临时反编译、测试和安装包已清理
