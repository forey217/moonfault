# MoonFault

项目最终交付目标是完整实现 Open-PSA MEF 2.0 的模型读写、语义处理及分析结果交换。当前发布版本为 0.2.0，已完成下述静态故障树能力；它是阶段成果，尚未达到完整标准一致性。完整范围、未完成项和发布验收门槛见[标准实现计划](docs/mef-roadmap.md)，参赛说明见[项目申报书](docs/submission.md)与[11 月 13 日反馈答复](docs/review-2026-11-14.md)。

MoonBit 原生静态故障树分析与 Open-PSA MEF 交换库。多个分支引用同一个事件时使用同一个随机变量，避免把共享电源等共同原因误算成独立故障。

- 定量分析：ROBDD 顶事件概率、状态干预、Birnbaum、Fussell–Vesely（风险下降定义）、RAW、RRW 和单列的 SCRAM DIF。零分母与浮点溢出有明确状态。
- 定性分析：支持 AND、OR、NOT、XOR、IFF、蕴含、NAND/NOR、投票和基数门。完整素蕴含项保留事件正常与故障两种文字，并包含不直接出现在 BDD 路径上的共识项。单调模型继续提供普通最小割集。
- 模型交换：读写 Open-PSA MEF 2.0 的静态布尔档，处理房屋事件、组件作用域、全路径引用与静态概率表达式。

安装 MoonBit 和 Node.js 24 后，在仓库运行：

```sh
moon update
npm run verify
node scripts/cli.mjs mef-analyze examples/mef/shared-power.xml
node scripts/cli.mjs mef-analyze examples/mef/consensus.xml
node scripts/cli.mjs mef-export examples/nonmonotone.json --out exactly-one.xml
node scripts/cli.mjs mef-analyze exactly-one.xml
```

验证结果和导出的 XML 写入 `_build/reports/`。Windows 可用 `powershell -File scripts/verify.ps1` 测试 JS、Wasm GC 和 Wasm。GitHub CI 另跑 Linux native 和独立 SCRAM 对照。

## 三个可复核场景

1. [共享电源](examples/mef/shared-power.xml)：顶事件概率 0.02245，最小割集为 {power} 和 {server_a, server_b}；电源 RRW 为 8.98。可比较更换电源与更换单台服务器的模型影响。
2. [条件切换](examples/mef/consensus.xml)：概率 0.34。除正负模式分支外，找到 {left, right} 共识项；模式事件的 Birnbaum 为 −0.3，RAW 小于 1。展示普通割集无法表达的负文字。
3. [组件模型交换](examples/mef/scoped-switch.xml)：两个组件分别声明同名私有事件，靠作用域区分。计算概率 0.0882；导出再读保持结果和元数据。

## 安装与范围

`moon add forey217/moonfault@0.2.0`，在 `moon.pkg` 导入 `forey217/moonfault`。见[独立消费者](examples/consumer/consumer.mbt)、[分析契约](docs/contract.md)、[MEF 范围](docs/mef-profile.md)、[JSON 与 CLI](docs/json-api.md)、[验证说明](docs/verification.md)。

当前 0.2.0 处理固定概率、独立基础事件的静态 Boolean DAG。事件树、任务时间分布、CCF 组、替换规则及跨文件 include 尚未实现，已列入最终交付计划；当前遇到这些输入仍会报错。标准以外的厂商动态门扩展另行记录，不能与标准内的事件树及时间表达式混为一谈。概率使用 binary64，“精确”指未用罕见事件截断或抽样。算法是原创 MoonBit 实现，MIT；XML 层复用 Apache-2.0 的 [Milky2018/xml](https://mooncakes.io/docs/Milky2018/xml@0.5.0)。
