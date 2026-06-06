# Machi（iOS）

Machi 是一款**城市本地生活 / 社交** iOS 客户端：信息流、发布（图文 / 视频）、评论、点赞、转发、收藏、关注、私信、通知、城市频道与话题。它与 Web 端共用同一套账号、数据与 API —— 统一后端是一个 Python 单文件服务（见姊妹仓库 [`machi-web`](https://github.com/yaokai4/machi-web)）。

App 采用**离线优先**设计：本地用 SwiftData 持久化、可离线浏览与起草，联网且登录后再与后端双向同步。

---

## 技术栈

| 维度 | 选型 |
| --- | --- |
| 语言 | Swift 5 |
| UI | SwiftUI（纯声明式，`NavigationStack` 路由） |
| 本地持久化 | SwiftData（版本化 Schema V5 + 迁移计划 + 多级恢复；CloudKit 关闭） |
| 第三方依赖 | **无**（仅 Apple 系统框架：SwiftUI / SwiftData / Foundation / os.Logger / Security(Keychain) / Network） |
| 最低系统 | iOS 26.0（测试 target 26.5） |
| 构建工具 | Xcode 26+（iOS 26 SDK） |
| 网络 | `URLSession` + 自研轻量 HTTP 客户端（`KaiXAPIClient`），JSON over HTTPS，Bearer Token |
| 凭据存储 | iOS Keychain（`KeychainTokenStore`） |
| 架构 | MVVM + Repository + Service 分层，离线优先 |

**工程信息**：Bundle ID `com.yaokai.kaizi` · Product `Machi` · Version `1.0 (1)` · Targets：`Machi`（App）、`MachiTests`（单元测试）、`MachiUITests`（UI 测试）。

> 注：源码内部的模块/类名历史上以 `KaiX*` / `kaizi` 命名（如 `kaiziApp`、`com.yaokai.kaizi`、`KaiXSchemaV5`），产品对外名为 **Machi**。两者等价，未统一重命名是为了不破坏已有的 SwiftData 存储与签名标识。

---

## 架构总览

```
┌───────────────────────────────────────────────┐
│                    SwiftUI Views                │  Views/  Components/
│      （按功能分组：Home / Search / ...）         │
└───────────────────────┬─────────────────────────┘
                        │  @StateObject / @EnvironmentObject
┌───────────────────────▼─────────────────────────┐
│                 ViewModels / Stores              │  ViewModels/
│   AppState · PostStore · SessionStore · ...      │
└───────────────────────┬─────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────┐
│                   Repositories                   │  Repositories/
│        （对 SwiftData 实体的读写抽象）            │
└───────────┬───────────────────────┬─────────────┘
            │                       │
┌───────────▼─────────┐   ┌─────────▼───────────────┐
│  Database (SwiftData)│   │   Services（横切能力）   │
│  @Model 实体 + 容器  │   │  网络 / 认证 / 同步 / 媒体 │
│  Database/           │   │  Services/               │
└──────────────────────┘   └─────────┬───────────────┘
                                     │  HTTPS / JSON / Bearer
                          ┌──────────▼───────────────┐
                          │  统一后端 server.py       │
                          │  （machi-web 仓库）       │
                          └───────────────────────────┘
```

- **启动流程**：`kaiziApp`（`@main`）注入 `KaiXDatabaseContainer.shared`（SwiftData `ModelContainer`）→ `ContentView` 是一个状态机：`loading → empty(登录) → loaded(主界面)`，出错走 `error` 重试态。
- **登录后引导**：`AppState.bootstrap` 先就绪本地 SwiftData，再在有 Token 时由 `RemoteSyncService` 拉取后端最新状态，使 iOS 与 Web **真正共享同一份数据**；离线 / 未登录时为 no-op。
- **主界面**：`MainTabView` 5 个 Tab（首页 / 发现 / 通知 / 私信 / 我的），每个 Tab 独立 `NavigationStack`，发布走全屏 `fullScreenCover`，导航栈由 `AppRouter`（`KXRouter.swift`）统一管理。
- **健壮性**：`ConnectivityMonitor` 离线提示；`DatabaseContainer` 在打开本地库失败时按「轻量迁移 → 备份后重建 → 恢复库 → 内存临时库」逐级降级，绝不崩溃丢数据。

---

## 项目结构

> 仓库采用标准 iOS 工程布局，`git clone` 后用 Xcode 打开 `Machi.xcodeproj` 即可直接编译。

仓库根目录：

```
.
├── Machi.xcodeproj/            Xcode 工程（Xcode 16+ file-system-synchronized groups）
├── Machi/                      App target 源码（详见下方）
├── kaiziTests/                 单元测试（MachiTests target，含 KaiXAPIClientTests）
├── kaiziUITests/               UI 测试（MachiUITests target）
├── README.md
└── LICENSE
```

App 源码（`Machi/`）：

```
Machi/
├── kaiziApp.swift              @main 入口；注入 SwiftData ModelContainer
├── ContentView.swift           根状态机（loading/error/empty/loaded）+ 全局 Store 注入
│
├── App/                        应用外壳
│   ├── MainTabView.swift        5 Tab + 每 Tab 独立 NavigationStack + 全屏发布器
│   └── AppChromeState.swift     顶/底栏显隐与滚动联动
│
├── Models/                     领域模型与枚举（值类型）
│   ├── DomainModels.swift / DomainEnums.swift      核心模型与枚举
│   ├── CityChannel.swift                            城市频道
│   ├── ContentType+Registry.swift / PostAttributeKeys.swift   内容类型注册
│   ├── ContentLanguage.swift                        内容语言
│   ├── ScreenState.swift / ErrorState.swift / CommentLoadState.swift   UI 状态
│   └── MediaDraft.swift                             媒体草稿
│
├── Views/                      SwiftUI 页面，按功能分组
│   ├── Home/          首页信息流（推荐 / 关注 / 热度）
│   ├── Search/        发现 / 搜索 / 话题 / 推荐关注
│   ├── Notifications/ 通知中心
│   ├── Messages/      私信会话与消息
│   ├── PostDetail/    帖子详情 + 评论 / 回复
│   ├── Compose/       发布器（图文 / 视频 / 标签 / 草稿）
│   ├── City/ Region/  城市频道与地区选择
│   ├── Profile/       个人主页与资料编辑
│   ├── Settings/      设置（语言 / 外观 / 通知 / 隐私 / 黑名单 / 设备 / 数据导出 / 删除账号）
│   └── Shared/        跨页复用视图
│
├── ViewModels/                 视图模型 + 可观察 Store
│   ├── AppState.swift           启动引导、当前用户、全局状态机
│   ├── AppStores.swift          Session/User/Post/Comment/Notification/Message/Search/Compose Store 集合
│   ├── PostStore.swift          帖子内存状态（乐观更新）
│   ├── *ViewModel.swift         各功能页 VM（Home/Profile/Search/Compose/Messages/...）
│   └── ToastManager.swift       全局 Toast
│
├── Services/                   横切服务（无 UI）
│   ├── KaiXBackend.swift        后端基址解析（默认 + UserDefaults + Info.plist 覆盖）+ Token 入口
│   ├── KaiXAPIClient.swift / KaiXAPIDTO.swift   HTTP 客户端与 DTO
│   ├── AuthService.swift / KeychainTokenStore.swift / PasswordHasher.swift   认证与凭据
│   ├── RemoteSyncService.swift  本地 SwiftData ↔ 后端同步
│   ├── ConnectivityMonitor.swift 网络状态监测
│   ├── UploadService.swift / ImageCacheService.swift / VideoThumbnailService.swift   媒体上传与缓存
│   ├── FeedQueryBuilder.swift / HeatScoreService.swift   信息流查询与热度算法
│   ├── RegionDirectory.swift / RegionStore.swift   地区 / 城市目录
│   └── LanguageManager.swift / LocalizationService.swift / NotificationPreferenceService.swift
│
├── Repositories/               仓储层（封装 SwiftData 读写，向上提供领域接口）
│   ├── PostRepository / CommentRepository / MessageRepository
│   ├── NotificationRepository / TopicRepository / UserRepository
│   └── RepositoryError.swift
│
├── Database/                   SwiftData 持久层
│   ├── KaiXSchema.swift         版本化 Schema（当前 V5）+ 迁移计划
│   ├── DatabaseContainer.swift  ModelContainer 创建 + 多级失败恢复
│   ├── *Entity.swift            @Model 实体：User / Post / Comment / Message(s) / Notification / Topic / Media / Support
│   ├── DatabaseSeeder.swift / RichDemoSeeder.swift   首次运行注入演示数据
│   ├── DataIntegrityRepairer.swift   数据完整性修复
│   └── DatabaseRecoveryNotice.swift  恢复提示（仅 DEBUG 呈现）
│
├── Utilities/                  工具与基础设施
│   ├── KXRouter.swift           AppRouter：按 Tab 维护导航栈
│   ├── AppAppearance.swift / AppLanguage.swift   外观（浅/深）与语言（system/zh/en/ja）
│   ├── Constants.swift / Extensions.swift
│   └── DateFormatterUtils.swift / NumberFormatterUtils.swift
│
├── Components/                 复用 UI + 设计系统
│   ├── DesignSystem.swift       设计 token（圆角 / 间距 / 字号 / 头像 / 配色，与 Web 端对齐）
│   ├── PostCardView / AvatarView / MediaGridView / MediaPreviewView / CachedMediaImageView
│   ├── BottomTabBarView / StickyNavigationBar / FlowLayout / RegionPickerButton
│   └── SettingsComponents / ErrorBanner / LoadingErrorViews / EmptyStateView+Channel
│
├── Data/
│   └── AWSReadyDataLayer.swift  面向云端的数据层抽象（演进方向预留）
│
├── Assets.xcassets/            图片 / 颜色 / App 图标
└── PrivacyInfo.xcprivacy        Apple 隐私清单（App Store 必需）
```

---

## 数据层

- **本地**：SwiftData，模型集合定义在 `KaiXSchemaV5.models`，存储位于 App 沙盒的 `Application Support/KaiXStores/`。
- **迁移与恢复**：`DatabaseContainer` 按以下顺序逐级降级，保证 App 永不因本地库损坏而崩溃：
  1. 正常打开主库（带迁移计划 `KaiXMigrationPlan`）
  2. 失败 → 轻量迁移重试
  3. 仍失败 → 备份旧库后重建主库
  4. 再失败 → 切换到独立恢复库
  5. 最终兜底 → 内存临时库（当次会话可用，提示用户）
- **CloudKit**：当前关闭（`.none`）。`Data/AWSReadyDataLayer.swift` 为后续接入云端 / 对象存储预留抽象。
- **同步**：登录后 `RemoteSyncService` 与后端对齐；本地仅作离线缓存与草稿暂存，**后端是唯一真相源**。

---

## 与后端的关系

iOS 与 Web 共用同一个统一后端（`machi-web` 仓库中的 `server.py`），同一套账号、数据库与 REST/SSE API。

后端基址在 `Services/KaiXBackend.swift` 解析，优先级如下，方便切换开发 / 预发 / 生产而无需改代码：

1. `UserDefaults` 键 `kaix.api.base`（可在 App 内设置页写入）
2. `Info.plist` 键 `KAIX_API_BASE`
3. 默认值 `https://machicity.com`（生产环境；模拟器可通过前两项覆盖到本地开发服务）

认证用 Bearer Token，存于 **iOS Keychain**（`KeychainTokenStore`，含从旧版 `UserDefaults` 的一次性迁移）。Web 端用 `localStorage` 存同名 Token，概念对称、仅存储后端不同。

---

## 构建与运行

**环境要求**：macOS + **Xcode 26 或更高**（需 iOS 26 SDK）。仓库即标准 iOS 工程，clone 后可直接编译。

```bash
git clone https://github.com/yaokai4/Machi.git
cd Machi
open Machi.xcodeproj
```

1. 在 Xcode 中选中 `Machi` target（同名 Scheme）。
2. 打开 **Signing & Capabilities**，把 Team 改成你自己的开发者账号（仓库里的 `DEVELOPMENT_TEAM = P22K8NF89K` 仅对原作者有效）。
3. 选择 iOS 26 模拟器或真机，`Cmd + R` 运行。
4. 启动统一后端（见 `machi-web` 仓库的 `python3 server.py`），或在 App 内设置页 / `Info.plist` 把 `KAIX_API_BASE` 指向你的后端地址。
5. 首次运行会注入演示数据（`RichDemoSeeder`），可直接浏览；登录态用于与后端同步。

**测试**：`Cmd + U` 运行 `MachiTests`（单元测试，含 `KaiXAPIClient` 用例）与 `MachiUITests`（UI 测试）。

---

## 国际化与主题

- **语言**：`AppLanguage` 支持 跟随系统 / 简体中文 / English / 日本語，由 `LocalizationService` + `L(_:_:)` 取词；用户选择存 `@AppStorage("appLanguageCode")`。
- **外观**：`AppAppearance` 支持 跟随系统 / 浅色 / 深色，存 `@AppStorage("appAppearance")`。
- **设计系统**：`Components/DesignSystem.swift` 定义圆角 / 间距 / 字号 / 头像尺寸 / 主题色等 token，与 Web 端 `globals.css` 一一对齐，保证双端观感一致。

---

## 安全

- App 源码中**不含任何密钥**：后端密码、邮箱服务密钥、验证码等全部由服务端管理，客户端只持有登录后由后端签发的 Bearer Token。
- Token 存于 **iOS Keychain**，不落在 `UserDefaults` 明文。
- 密码在传输前由 `PasswordHasher` 处理；服务端再以 PBKDF2 + pepper 存储哈希（详见 `machi-web`）。
- 隐私合规：`PrivacyInfo.xcprivacy` 声明数据使用，符合 App Store 隐私清单要求。

---

## 发布（TestFlight / App Store）

1. `Product → Archive` 生成归档（Release 配置）。
2. 在 Organizer 中校验签名与 `PrivacyInfo.xcprivacy`，上传到 App Store Connect。
3. 发布前确认生产环境的 `KAIX_API_BASE` 指向正式后端域名（HTTPS）。
4. 通过 TestFlight 内测后再提交审核上架。

---

## 相关仓库

- **Web / 后端**：[`yaokai4/machi-web`](https://github.com/yaokai4/machi-web) —— Python 单文件后端（`server.py`，SQLite + 80+ REST 端点 + SSE）+ Next.js 15 Web 客户端。iOS 与 Web 共享同一套账号、数据库与 API。

## License

见仓库内 [`LICENSE`](./LICENSE)。
