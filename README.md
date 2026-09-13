# 数字果蝇 v1.5

数字果蝇是一只运行在 macOS 桌面上的自主果蝇。`1.5.0 (19)` 在完整 MaleCNS v1.0 连接图参与具身闭环和 v1.2 功能性自我认知的基础上，累计完成反事实与元认知（v1.3）、长期目标与语义自我（v1.4）、自己/他者区分（v1.5）。这些能力会改变实际动作竞争，并有盲测、持久化和消融证据；它们仍是工程功能，不是主观意识声明。

## v1.3–v1.5 的核心结果

- 每个周期在行动前评估 9 个候选未来，比较位移、能量成本、威胁暴露、信息增益、效用和置信度，再将选中计划反馈给动作 WTA。
- 自身原因和外界原因作为两个竞争假设；“隐藏阵风”不会把外力标签交给模型，只通过预测残差推断，并累计准确率、Brier Score 和校准误差。
- 因果歧义或感觉证据不足时产生主动求证驱动，通过低成本探索获取信息，而不是强行给出确定答案。
- 长期目标覆盖维持能量、安全、探索、身体恢复、消除不确定和观察他者；目标具有持续性，但可被更紧急需求打断。
- 自传式经历定期整合为身体控制、感觉信任、环境波动和社会关联知识；五项偏好会随个体经历缓慢改变。
- 他者模型从出现、独立运动、响应关联和威胁线索推断他者能动性，区分自身、他者、环境和共同作用。
- 快照升级为 schema 9；v1.3、v1.4、v1.5 的状态都绑定 `individualID` 并可跨重启恢复，不会被另一个体继承。
- App 是快照的唯一写者；Widget 只读，解码失败也不会移动或覆盖个体状态。
- 神经实验室扩展为六页，新增“认知进阶”工作区和隐藏阵风、目标冲突、响应型/独立他者实验。

## v1.2 功能性自我的累计能力

- `ENG-SELF-PREDICT` 整合视觉运动、本体感觉、能量/疲劳/污染和联想记忆四组分布式通道；比较预测位移、能量变化与下一状态实测值。
- 每个周期输出身体一致性、行动能力、能动性、预测误差、感觉可靠度、置信度与不确定度，并将后三项反馈给动作竞争。
- 因果归属分为“自身行动”“外界事件”“外因触发 / 自身响应”和“暂不确定”；解释文字直接由同一组数值生成。
- 最多 24 条经历绑定 `individualID` 存入 schema 6 快照，保留动作、预期/结果差异、归属和当时置信度，可跨重启恢复。
- 新增外力位移、感觉遮蔽和反转转向在线干预；模型能在反转控制的连续误差中校准转向增益。
- 神经实验室保留“自我模型”页；状态面板也显示当前归属及其证据。

- 运行时加载 `165,122` 个已追踪神经元和 `25,563,197` 条观测连接，保留 `124,025,046` 个突触权重；图固定 SHA-256 为 `35c7973b35f4b0508d2542ebca1e7db48becab3c1b6a3c76e8cc1b78663478a3`。
- 每个神经元都有膜电位、活动和突触前可塑性状态。事件驱动传播只访问本周期实际放电神经元的出边，不必每 10 ms 扫描全部 2,556 万条边。
- 视觉、嗅觉、味觉、触觉、本体感觉、饥饿和强化信号进入由注释推导的真实神经元集合；感觉、中央复合体、下行和运动群读出会调制桌面行为。
- 多巴胺、血清素和章鱼胺具有持续状态；强化可改变实际 MaleCNS 出边源上的有界有效增益。
- 全 CNS 动态状态按果蝇个体与图 SHA 绑定并跨重启保存；App 恢复时会隔离不兼容或损坏的写者状态，不会当作有效记忆继续使用。
- 10 Hz 全 CNS 推进、快照和记忆持久化在专用串行 worker 上执行；主线程只发布完成快照，简要状态面板以 4 Hz 重绘，滚动不再等待神经计算。
- 状态面板展示全 CNS 活跃数、放电数、传播事件、实时倍率、群体读出、调制物、可塑性源数、事件预算和数据来源边界。
- 独立、可缩放的神经实验室包含“实时脑窗”、“自我模型”、“认知进阶”、“神经元浏览器”、“实验控制台”和“对照结果”六个可操作页面。
- 浏览器可按 body ID、已收录的回路类型、派生角色、预测递质和侧别筛选，并显示入出边与当前动力学状态。
- 实验控制台用相同初始条件创建隔离的对照组和干预组，支持 body ID 静默/刺激、9 路感觉协议、DNg13 预设、时间序列对照与 JSON 导出；实验不改写正在生活的桌面果蝇。
- 保留原有的 12 路动作神经竞争、下降运动输出、有限食物、两路气味联想、跨重启个体状态和桌面形象；中号 Widget 使用主指标/竖向分栏布局，小号沿用同一套暖黑网格与灰白单色仪表语言。

## 如何观察

启动后，专属的神经果蝇 Dock 图标、桌面果蝇和菜单栏入口会同时出现。首次启动或再次点击 Dock 图标都会显示神经实验室。“打开实时状态”保留原有概览；“打开神经实验室”进入六页实验工作区。“自我模型”页保留外力、感觉遮蔽和反转转向；“认知进阶”页提供隐藏阵风、目标冲突和两类他者实验。小号和中号 Widget 是独立监视面板，点击整块组件会打开原有实时状态。也可用 `cyberfly://lab` 深链直接打开实验室。

果蝇不能由界面直接指定动作。前进、转向、振翅、进食、梳理和休息门控来自 `ENG-SELF-PREDICT ↔ ENG-COUNTERFACTUAL ↔ ENG-SEMANTIC-SELF ↔ ENG-OTHER-MODEL → ENG-ACTION-WTA → ENG-DESCENDING` 的有状态输出；全 CNS 群体读出、自我模型不确定度、反事实选择、长期目标和社会推断共同调制这层。身体层只更新能量、疲劳、污染、位置、碰撞和食物消耗。

## 模型边界

这是“完整连接图参与运行”的数字果蝇，不是生物学上的完整复现：

- `observed`：MaleCNS 中的神经元身份、连接和突触数。
- `predicted`：数据集提供的神经递质预测。
- `derived/fitted`：根据观测注释做的角色分类，以及与桌面行为校准的读出增益。
- `literature/assumed`：膜动力学、递质作用符号、阈值、感觉编码、可塑性和身体映射。

MaleCNS 没有提供每个神经元的膜参数、受体表达、完整感觉变换、肌肉模型、自我/他者模型或实时神经记录，因此 v1.5 使用 49 个明确标为工程构造的感觉、认知、动作与下降读出单元。`ENG-SELF-*`、`ENG-COUNTERFACTUAL` 和 `ENG-OTHER-MODEL` 不冒充 MaleCNS 已观测神经元，功能性通过干预与消融检验，也不能推出主观体验。模型卡和逐项边界见 [Docs/MODEL_CARD.md](Docs/MODEL_CARD.md)。

## 数据与重建

官方源文件保存在不入 Git 的 `Data/raw/`，来源、字节数和 SHA-256 记录在 `Data/manifests/male-cns-v1.0.json`。生成的 7 个二进制图文件也不入 Git；`manifest.json`、编译器和所有校验逻辑入库。

```bash
UV_CACHE_DIR=/private/tmp/cyberfly-uv-cache uv venv .venv-data --python python3
UV_CACHE_DIR=/private/tmp/cyberfly-uv-cache uv pip install --python .venv-data/bin/python -r Scripts/requirements-data.txt
.venv-data/bin/python Scripts/build_malecns_circuit.py
.venv-data/bin/python Scripts/build_malecns_learning_circuit.py
.venv-data/bin/python Scripts/build_malecns_full_graph.py
```

全图编译器先按 `body_pre/body_post` 精确聚合权重，再生成按节点索引排序的 CSR 与 CSC。只有两个端点都属于 `Traced` 注释集的连接会进入运行图。

## 验证、构建与安装

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cyberfly-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cyberfly-swiftpm-cache \
swift test --disable-sandbox -c release

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cyberfly-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cyberfly-swiftpm-cache \
swift run --disable-sandbox -c release CyberFlySelfTest

./Scripts/build-release.sh
./Scripts/install-local.sh
```

`CyberFlySelfTest` 会核对固定图 SHA、7 个文件 SHA、CSR/CSC 结构、节点/边/突触计数、实时性能门槛、DNg13 静默因果门槛、学习、食物、动作层、功能性自我、盲测外因、长期目标/语义整合和他者模型。当前证据见 [Docs/VALIDATION.md](Docs/VALIDATION.md)，架构见 [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md)。
