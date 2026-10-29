# 我们的 BetterCast 改动

这里集中保存本地扩展的说明、验证记录、辅助脚本和后续上游反馈材料。
仓库根目录 README.md 保持上游原样。功能实现仍放在原项目相应源码位置，避免复制另一套实现。

- [分批提交计划](submission-plan.md)：每批范围、依赖与验证状态。
- [实现说明](implementation-notes.md)：功能行为、限制及构建说明。
- `scripts/`：本地打包、签名选择及验证脚本。
- `tests/`：接收端连接和布局测试源码。

当前状态：此前混合提交已撤回，改动已按九个依赖批次重新提交到本地 main，尚未推送或向上游发布。
上游基线为 `768de0c`。这些材料不代表原作者已接受改动。

## 从仓库根目录执行

```bash
contributions/scripts/build_local_network_apps.sh
contributions/scripts/test_receiver_connection.sh
python3 contributions/scripts/test_network_roaming.py
python3 contributions/scripts/test_receiver_audio.py
```

构建产物仍位于已忽略的 `local-build/`。该目录中的签名选择记录、应用和备份不提交。
脚本不会自动替换 `/Applications` 中的应用。测试不会向 iMac 发送真实桌面或更改系统音量。
网络切换测试需要本机至少两种不同优先级的可发现网络接口。

## 上游反馈原则

按单个问题提供复现步骤、实际/预期行为、最小修复和验证结果。
日志应去除姓名、设备名、网络地址和账号等个人信息。仅有本机自动测试的功能不得写成已通过真实 iMac 验证。
本地证书打包流程单独处理，不要求上游接受我们的个人开发环境配置。
