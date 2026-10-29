# 分批提交记录

已按下列九个批次创建英文提交；提交顺序体现依赖关系，尚未推送或发布 issue。
本轮在 main 上按顺序提交，每批以其前面的提交为基线，并在独立临时目录检查该批次的代码。后续向上游提交时可以按依赖建立独立 PR 分支。
`BetterCastSenderApp.swift`、接收端入口和中文翻译包含多项改动，必须按代码块拆分，不能直接整文件提交。

| 批次 | 建议主题 | 内容和边界 | 依赖 | 当前验证 |
|---|---|---|---|---|
| 01 | 修复旧版 Mac 接收端构建依赖 | 补充 ADBLocator 共享源码链接；与功能新增分开 | 无 | Intel 10.15 目标构建通过 |
| 02 | 接收端断线清屏 | 清除最后一帧、断线状态、TCP keepalive、停止播放资源；音频清理放到音频批次 | 01 | 本机连接测试通过；用户确认拔线后画面清除 |
| 03 | Catalina 全屏画面布局修复 | 视频层尺寸、位置、窗口/全屏切换同步，关闭位移动画 | 01 | 尺寸切换测试通过；用户确认全屏恢复正常 |
| 04 | 可选网络优先级及实际线路显示 | 雷雳/以太网/Wi-Fi 优先，系统接口识别、发现接口信息、连接和重试超时、共享辅助文件链接 | 01 | 用户确认 bridge0 连接；本机定向连接通过 |
| 05 | 自动网络恢复及优先线路切回 | 保留虚拟屏幕，仅替换连接；稳定等待、失败退避、手动取消、旧连接回调隔离、避免自动连接本机 | 04 | 多网卡测试通过；用户日志确认雷雳→Wi-Fi→雷雳 |
| 06 | 接收端全屏光标和标题栏状态 | 全屏视频区域隐藏本地光标、恢复处理、连接信息放标题栏；不要带入布局修复的其他代码 | 03、04 | Catalina 构建通过；真实全屏效果待用户确认 |
| 07 | Mac 接收端 AAC 音频播放 | 48kHz 双声道、AAC 解码播放、音频开关实时生效、断线停止音频、共享源码链接 | 01；合并到当前分支时兼容 05 | AAC 解码测试通过；iMac 实际发声待确认 |
| 08 | 可选发送端静音 | 独立静音开关、输出设备变更、原静音状态恢复、正常退出清理、中文文案 | 05、07；本批明确依赖 05 的定时检查，若单独向上游提交需另行拆出调度 | 假输出设备测试通过；实际静音串流待确认 |
| 09 | 本地构建和稳定签名工具 | contributions 下的构建/签名脚本、忽略产物、固定证书身份；不含证书或私钥 | 按需要选择功能批次 | 签名校验通过；重复授权问题是否消失待确认 |

## 拆分时需要处理的交叉改动

- 接收端连接测试在 02 引入，03 扩展布局检查，04 扩展网络显示检查。
- 网络切换测试目前抽取生产方法并使用假的显示/采集对象；提交上游前需说明范围，不能声称完整端到端覆盖。
- AAC 测试在 07 引入，08 在同一脚本中扩展静音测试。
- ConnectionNetwork.swift 由现代和旧版接收端共享；链接及使用位置必须与文件一起提交。
- 同一个中文翻译文件按功能逐项分配，避免在早期提交中带入后续未实现的选项。
- 上游可能更偏好先提交 bug issue，再提出功能 PR；先整理复现材料，发布前再确认。

## 建议上游反馈顺序

先提供 01、02、03 三项范围较小的修复，再讨论 04、05 的连接策略。
06、07、08 分别作为界面和音频需求，避免一个 PR 同时涉及网络、显示和音频。
09 是个人开发流程，可只保留在自己的 fork。

## 本地提交索引

- 01: `0e08330c` — fix(receiver): restore the legacy ADBLocator source dependency
- 02: `20ac2f0b` — fix(receiver): clear stale video after connection loss
- 03: `17bb717f` — fix(receiver): synchronize fullscreen video geometry on Catalina
- 04: `313ae401` — feat(network): add preferred interfaces and connection path reporting
- 05: `ca3d3ab5` — feat(network): recover sessions and upgrade preferred routes
- 06: `0efccc5f` — feat(receiver): hide the fullscreen cursor and show routes in the title
- 07: `c2716414` — feat(audio): play AAC streams on the Catalina receiver
- 08: `1d94ec41` — feat(audio): add optional sender output muting
- 09: 本文及本地构建工具所在提交。

验证记录：各批次的 Intel macOS 10.15 接收端通过编译；04、05、07、08 的发送端通过 release 构建；相关连接、布局、网络恢复、AAC/静音测试随对应批次执行。
