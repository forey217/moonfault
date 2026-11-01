# MoonFault

MoonBit 原生静态故障树分析库。一个基础事件即使被多个分支引用，也只计作一个随机变量，避免把共享电源等共同原因误当成独立故障重复相乘。

支持 AND、OR、k-of-n 门、共享子图、ROBDD 概率计算、事件状态干预、Birnbaum 重要度、完整最小割集及割集概率联合上界。概率计算按声明的独立基础事件模型进行，数值使用 binary64；“精确”指不使用罕见事件截断或蒙特卡洛近似，不表示浮点数无舍入误差。

## 运行

安装 MoonBit 工具链和 Node.js 24，在仓库目录执行：

```sh
moon test --target js --deny-warn
npm run verify
node scripts/cli.mjs examples/shared-power.json
```

Windows 可执行 `powershell -File scripts/verify.ps1`。CI 另外执行 Wasm、Wasm GC 和 Linux native 测试。Node 只负责 JSON 文件读写；建模、决策图、概率和割集计算全部在 MoonBit。

## 三个使用场景

1. `shared-power.json`：双服务器共享一个电源。服务故障是 `(power OR server_a) AND (power OR server_b)`，结果为 0.02245；不能把两台服务整体故障率当成独立事件相乘。
2. `redundant-storage.json`：四盘系统中至少两盘失效，分析六个二元最小割集和总体失效概率。
3. `deployment.json`：网络或“数据库和缓存同时失效”导致部署不可用；将网络强制为正常，比较修复后的概率和重要度。

运行 `npm run examples` 会将真实输出写入 `_build/reports/`。独立真值表测试也在同一目录生成验证记录。

## 安装与接口

```sh
moon add forey217/moonfault@0.1.0
```

导入 `forey217/moonfault`。见 [独立消费者](examples/consumer/consumer.mbt)、[接口契约](docs/contract.md)、[JSON 输入输出](docs/json-api.md) 和 [验证方法](docs/verification.md)。公开 API 清单由 `moon info` 生成在 `pkg.generated.mbti`。

## 范围

这是静态、相干故障树工具，不实现动态门、修复过程仿真、故障率时间积分或任意相关随机变量模型。共享事件可显式建模；基础事件之间的独立性和输入概率由调用方负责。未知引用、环、不合法概率和资源预算不足均返回明确错误，不把部分割集当成完整结果。

MIT。算法参考和生态对比见 [contract.md](docs/contract.md)。
