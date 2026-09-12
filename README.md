# 数字果蝇

真实连接组约束的 macOS 自主桌面果蝇。

当前应用版本为 `0.4.4`，已建立贯穿感觉、动作竞争和下降运动的神经控制闭环：

- 自主活动、饥饿、短时愉悦、长期满足、好奇、警觉和梳理需求模型。
- 停留、行走、探索、寻食、气味回避、进食、飞行、头部/翅膀梳理、休息、受惊和休眠各有独立动作神经元群；每个模拟步都由有状态的 WTA 神经竞争重新计算胜出动作，没有行为计时器。
- 前进速度、转向角速度、振翅、进食、梳理和休息门控全部来自下降运动神经元输出；生理/物理层只据此更新能量、疲劳、位置和碰撞。
- 桌面形象采用可缩放矢量绘制：绿色头胸、金黄色超大复眼、深灰绒腹、浅灰双层小翅和粗黑手绘轮廓；神经振翅、梳理、休息与朝向仍实时作用于造型。
- 透明桌面果蝇宿主与菜单栏实时状态。
- 有限份量的桌面水果：进食会逐步吃完，放置 8 分钟后开始腐败，12 分钟后自动消失。
- 两种可辨认的气味线索：`琥珀果香` 和 `莓红果香`。
- 跨重启个体状态、动作神经活动与下降运动输出恢复，以及由食物接触神经反射恢复的低能量休眠。
- 跨重启的气味联想记忆：进食会增强对当前气味的趋近，在闻到某种气味时受到威胁会增强回避。
- 供 WidgetKit 使用的原子状态快照和小/中尺寸桌面小组件。
- 官方 MaleCNS v1.0 数据校验、可重复回路提取和真实性标记边界。
- 27 个真实神经元、322 条真实连接组成的 `LoVP92 → VES200m → DNg13` 视觉回路。
- 以真实突触权重传播的轻量 LIF 电活动；左右 DNg13 放电差参与桌面转向。
- 1,426 个真实神经元身份和 17,744 条观测连接约束的 `DM1/DM2 → KC → MBON01/11 ↔ PAM01/PPL101` 嗅觉学习子图。
- 1,240 个真实 KC 的稀疏气味编码与持久化 `KC → MBON` 有效权重；反向强化可改写旧联想。

当前引擎标记为 `male-cns-neural-embodied-v0.4`。神经元身份、回路内连接和突触数来自 MaleCNS；
气味到 DM1/DM2 的映射、5% KC 稀疏化、学习率和遗忘/反转速度为文献启发的工程参数。
新增 `ENG-SENSORY → ENG-ACTION-WTA → ENG-DESCENDING` 控制器中的感觉、动作与运动群全部明确标为
`fitted/assumed`：它们实现“所有活动由神经计算”的软件边界，但不是 MaleCNS 已观测神经元，也不是完整全脑仿真。

## 如何观察全动作神经控制

1. 从菜单栏打开“实时状态”。面板会显示当前胜出的 `ENG-ACT-*` 动作神经元、动作竞争差和活跃控制神经元数。
2. 放置水果、移动鼠标、轻触或增加灰尘。动作只随神经竞争结果改变，理由文本会指向本次胜出的动作神经元。
3. 快照同时保存前进速度、转向角速度、振翅、进食、梳理、休息门控和 12 个动作群的活动值，重启后继续其有状态动力学。
4. 自动测试会逐一证明 12 种行为都存在可胜出的动作群，并证明沉默控制器后运动、振翅和进食全部停止。

## 如何观察学习

1. 从菜单栏打开“实时状态”，放置任意一种果香水果。
2. 果蝇饥饿时会寻食并进食；进食期间 PAM01 奖励信号与活跃 KC 同时出现，该气味的记忆条会向“趋近”移动。
3. 放置另一种水果，当果蝇靠近并闻到它时用“轻触”施加威胁；PPL101 惩罚信号会让对该气味的记忆向“回避”移动。
4. 再次放置同种气味时，已学习的价性会参与寻食/回避的动作竞争。记忆保存在 `learning-memory.json`，不会因退出应用丢失。

## MaleCNS 数据

`Data/raw/` 保存三份不入 Git 的官方 Feather 文件，总计约 1.0 GiB。
`Data/generated/male-cns-visual-steering-v1.json` 是可审计的小回路，包含逐神经元
`bodyId`、递质预测、逐边权重和三份源文件的 SHA-256。

重新生成：

```bash
UV_CACHE_DIR=/private/tmp/cyberfly-uv-cache uv venv .venv-data --python python3
UV_CACHE_DIR=/private/tmp/cyberfly-uv-cache uv pip install --python .venv-data/bin/python -r Scripts/requirements-data.txt
.venv-data/bin/python Scripts/build_malecns_circuit.py
.venv-data/bin/python Scripts/build_malecns_learning_circuit.py
```

生成的 `male-cns-olfactory-learning-v1.json` 保留每个节点、每条回路内连接、突触数、递质预测和三份源文件 SHA-256；运行时 Swift 表由同一脚本生成。

## 验证

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/cyberfly-clang-module-cache swift test --disable-sandbox
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/cyberfly-clang-module-cache swift run --disable-sandbox CyberFlySelfTest
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-release.sh
```

本地安装会写入 `/Users/dadudu/Applications`，需要单独执行：

```bash
./Scripts/install-local.sh
```
