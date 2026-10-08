# 自建 RustDesk / RDPX 改动与验证

客户端目录：`E:\Project\rustdesk`。服务端目录：`E:\Project\rustdesk-server`。

## 稳定版本

- 客户端已有官方稳定版 `1.5.0` 基线：`fada664df7a294d1d1a9ca3e7cd3637069122f17`。
- 服务端已从官方拉取正式 release `1.1.16`：`73523b31cfd25d77dee862e6fc9f5e1fb5e485ef`。
- 服务端稳定版合并提交：`6d7cfd8`，位于 `codex/private-protocol`。保留 fork 的 JWT / MUST_LOGIN 功能和发布工作流。
- 功能修改仍在工作区，两端公共库内的新增文件也需要随最终提交保存。没有推送或部署。

## 最终行为

- 不再提供官方默认 ID 服务器；旧配置中的 `rustdesk.com` 及其子域也会被过滤。未配置自建服务器时，ID 连接明确失败。
- 保留自建 API 默认地址 `http://82.157.201.157:21114`、自定义 API、账号和 OIDC。`remote.brigecode.icu` 的明文 HTTP GET 会被 DNSPod 未备案拦截页劫持（302 到 webblock），因此内置 API 默认与手填配置都应使用服务器 IP；ID/中继走裸 TCP/UDP，不受该拦截影响。官网 API 请求被拒绝，HTTP 重定向也检查官网域名。
- 更新检查默认关闭。只有设置自建 `RUSTDESK_VERSION_SERVER` 才发起检查，官方域名被拒绝。未配置时不会为更新检查采集设备指纹。
- Flutter 与旧 Sciter 的官网跳转被拦截；帮助和版权文字中仍可能显示官网地址。
- 自建服务器不再默认禁用 UDP、IPv6 和 WebRTC。用户显式禁用仍生效。现有非 RustDesk 的 STUN/TURN 配置保留。
- TCP、WebSocket、UDP 控制消息和 WebRTC 数据使用 RDPX。RDPX 是自定义应用协议：报文包含 magic、版本、保留标志和 protobuf 载荷类型，载荷继续使用 protobuf；传输层已经提供报文边界，因此不再重复携带 RustDesk 的明文载荷长度。
- RDPX 封装发生在会话加密之前，解封发生在解密之后。TCP、WebSocket 和 WebRTC 的完整 RDPX 头会随载荷一起加密；原始隧道及中继透传不重复解码。UDP 注册和密钥交换第一包尚未建立会话密钥，只能依赖其已有的认证/握手约束，不能声称这些包已加密。原版 RustDesk 控制报文会被拒绝，两端需要一起使用修改版本。
- 服务端只增加互通必需的 SDP/ICE 字段和转发，复用原有连接映射。保留旧版密钥协商 v0；未移植客户端的 v1 协商实现。

## 验证

在客户端目录运行：

```powershell
python scripts/check-private-server.py --build
```

脚本编译两端，SQLx 编译使用数据库副本；运行 hbbs/hbbr 时使用临时目录、临时密钥和临时数据库。测试结束关闭进程并清理目录。测试端口为 32115–32119，使用本机网卡地址测试中继，因为 hbbr 把 loopback TCP 作为管理命令入口。

已通过：

- 服务端 `cargo build --locked --bins`。
- 客户端公共库默认构建与 `webrtc` 构建。
- 两端 RDPX 正常报文、旧报文拒绝、非法头及截断拒绝测试。
- 两端官网域名边界测试。
- WebRTC 大小消息分片与接收上限测试。
- 实际两端 UDP 注册、UDP NAT 端口探测及非法报文后继续服务。
- 实际加密 TCP 的 SDP offer/answer 与双向 ICE 转发，随后建立 WebRTC P2P 并传输 RDPX 消息和原始隧道数据。
- WebSocket 请求/响应、WebSocket 注册后的 offer 和连续 ICE 投递。
- 双向 TCP 中继、原始 TCP 隧道以及加密 TCP/WebSocket 混合中继。
- 两仓库及公共库 `git diff --check`。
- Windows x64 完整 Rust Release 构建：`cargo build --locked --offline --release --lib --bins --features flutter,hwcodec,vram -j 8`，生成后端 DLL、静态库、桌面入口及服务程序。
- Rust/Dart 桥接代码生成（`flutter_rust_bridge_codegen 1.80.1`，含 Freezed）。
- Flutter Windows Release 完整构建：`flutter build windows --release --no-pub`。
- 虚拟显示模块 `cargo build --locked --offline --release -p dylib_virtual_display -j 8`，生成的 DLL 已复制进完整运行目录。
- Flutter 全套 `flutter test --no-pub`：133 项全部通过，包含官网链接拦截测试。
- 新增 URL 启动器、HTTP 服务及官网链接测试的定向 `dart analyze`：无问题。
- Flutter 全量 `flutter analyze --no-pub`：0 个编译错误、1 条原有未使用导入警告、99 条提示；因警告/提示退出码为 1，不作为全量 lint 通过。
- Flutter 最终目录中的 `rustdesk.exe --version`：输出 `1.5.0`，退出码为 0，验证后端 DLL 加载及启动入口。
- 虚拟显示 DLL 的 Windows 动态加载及 `get_driver_install_path` 导出检查通过；未安装虚拟显示驱动。

验证范围限制：本次完整客户端构建针对 Windows x64 Flutter 桌面版，没有进行其他平台或旧 Sciter UI 的完整构建，也没有进行真实远程桌面画面、输入、跨公网 NAT 或 TURN 部署验证。

### Windows 构建环境与产物（2026-10-01）

工具链安装在 `E:\toolchains`，不修改全局 PATH：Flutter 3.24.5 / Dart 3.5.4、LLVM 15.0.6、vcpkg `9e593bb18ea69cc5095e012465dcd675a822ed0d`、Rust 1.92.0、Visual Studio 2022 17.14.33 / MSVC 14.44。Flutter 使用项目 CI 的 dropdown 补丁和定制 Windows Release 引擎。

vcpkg 按项目 manifest、overlay ports 和 `x64-windows-static` 构建，安装根为 `E:\toolchains\vcpkg\installed`。Flutter 插件使用本机 junction，避免要求修改 Windows 开发者模式。生成的桥接代码与插件目录为构建产物，不纳入源码提交。

在客户端根目录设置当前 PowerShell 会话环境：

```powershell
$env:VCPKG_ROOT = 'E:\toolchains\vcpkg'
$env:LIBCLANG_PATH = 'E:\toolchains\LLVM-15.0.6\bin'
$env:PATH = 'E:\toolchains\flutter-3.24.5\bin;E:\toolchains\LLVM-15.0.6\bin;' + $env:PATH
cargo build --locked --offline --release --lib --bins --features flutter,hwcodec,vram -j 8
cargo build --locked --offline --release -p dylib_virtual_display -j 8
Push-Location flutter
flutter build windows --release --no-pub
flutter test --no-pub
dart analyze lib/utils/url_launcher.dart lib/utils/http_service.dart test/official_links_test.dart
Pop-Location
Copy-Item target/release/deps/dylib_virtual_display.dll flutter/build/windows/x64/runner/Release/
```

完整运行目录为 `E:\Project\rustdesk\flutter\build\windows\x64\runner\Release`；运行时需保留其中 DLL 和 `data` 目录。Rust 后端产物位于 `E:\Project\rustdesk\target\release`。

构建日志保留在 `E:\toolchains`：`vcpkg-install.log`、`bridge-generate.log`、`rustdesk-release-build.log`、`virtual-display-build.log`、`flutter-windows-build.log`、`flutter-all-tests.log`、`flutter-analyze.log` 和 `flutter-changed-analyze.log`。

hbbr 的原有配对流程在两个请求完全同时到达时可能把两端都存为等待端。此次没有改动该配对流程；互通脚本按先后顺序提交两个中继请求。此限制独立于 RDPX。

## 回归影响面与最小化检查

| 现有文件 | 变化的运行路径及必要原因 |
| --- | --- |
| 两端 `libs/hbb_common/src/bytes_codec.rs`、`tcp.rs`、`websocket.rs`、`udp.rs` | RDPX 收发、加密后的解封、原始模式和 UDP 错误处理；覆盖实际控制传输入口，避免部分通道仍发送旧协议。 |
| 客户端 `libs/hbb_common/src/webrtc.rs` | WebRTC 分片前封装及重组后解封；原始模式透明。 |
| 两端 `libs/hbb_common/src/lib.rs`、`config.rs` | 导出私有协议、统一官网域名识别、禁用默认官方服务器与默认更新请求。 |
| 服务端 `libs/hbb_common/protos/rendezvous.proto` | 添加客户端已有字段号的 SDP/ICE 字段；没有移植无关 API 代理、权限或新版协商消息。 |
| 客户端 `src/client.rs` | 空/官方服务器明确失败、UDP NAT 报文封装与心跳；避免空默认列表索引和 UDP 协议不一致。 |
| 客户端 `src/rendezvous_mediator.rs` | UDP 打洞回复与心跳封装，更新已有测试的解码；否则被控端仍发送旧协议。 |
| 客户端 `src/common.rs` | 保留自建 API，拒绝官网请求与官网更新结果，取消自建服务器下强制关闭 P2P 的默认设置。 |
| 客户端 `src/hbbs_http/http_client.rs` | HTTP 重定向检查；防止自建端点返回官网跳转后发起请求。 |
| 服务端 `src/common.rs` | 更新端点为空时返回，拦截官网重定向。 |
| 服务端 `src/rendezvous_server.rs` | 手动拆分的 TCP/WS 收发接入 RDPX；SDP/ICE 转发、UDP NAT 回复、非法 UDP 丢弃及握手输入验证；保留信令连接的接收密钥。 |
| 服务端 `src/relay_server.rs` | 仅首个配对请求解封，后续原始字节透明；避免解码端到端加密数据。 |
| 客户端 `flutter/lib/utils/http_service.dart` | 拒绝官网 API；Dart HTTP 分支检查每次重定向。 |
| Flutter `common.dart`，`common/widgets/{address_book,login,toolbar}.dart`，`desktop/pages/{connection_page,desktop_home_page,desktop_setting_page,install_page}.dart`，`desktop/widgets/update_progress.dart`，`mobile/pages/{connection_page,settings_page}.dart` | 导入统一 URL 启动器，集中拦截直接与动态官网链接；保留自建 OIDC 和文件链接。 |
| 客户端 `src/ui.rs`、`src/ui/{install,msgbox}.tis` | 旧 UI 的官网启动入口阻断。 |
| 服务端 `Cargo.lock` | 修复原 fork 的锁文件与现有公共库 manifest 不匹配；保留能恢复的旧锁版本，并锁定实际通过 Windows 构建的依赖组合。 |
| 客户端 `flutter/pubspec.lock` | 补齐已声明的 Flutter 测试依赖，并锁定 Flutter 3.24.5 SDK 要求的测试与公共传递依赖版本；完整 Windows 构建和 133 项测试使用此解析结果。 |

稳定版合并带来的上游构建、文档、relay 带宽、打洞日志和在线超时变化记录在独立合并提交中。客户端原有 `build.py` 签名修改和 `.mimosa` 文件保留。真实数据库的数据页未修改，编译阶段产生的 SQLite 日志模式头变化已恢复。
