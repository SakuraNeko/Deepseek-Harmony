# DeepSeek for HarmonyOS

基于 HarmonyOS WebView 封装的 DeepSeek AI 对话客户端，支持手机、平板和 2in1（PC）设备。

## 功能特性

| 功能 | 说明 |
|------|------|
| 🌐 WebView 封装 | 内嵌 `chat.deepseek.com` 官网，完整 AI 对话体验 |
| 🔗 Deep Link | 支持 `https://chat.deepseek.com/share/...` 分享链接冷/热启动跳转 |
| 🌙 深色模式 | 自动跟随系统深色/浅色模式，无缝切换 |
| 📱 沉浸式窗口 | 手机端透明状态栏，2in1 端隐藏系统标题栏 |
| 📤 文件上传 | 支持系统相册（图片）和文档选择器（通用文件） |
| 💾 文件下载 | WebView 下载 + 另存至公共下载目录 |
| 📲 系统分享 | 调用系统分享面板分享当前页面链接 |
| 🔄 崩溃恢复 | Web 渲染进程崩溃自动刷新恢复 |
| ⏱ 超时处理 | 15 秒页面加载超时，显示错误页 + 重试按钮 |
| 🏷 自定义 UA | 请求头追加 `DeepSeek-HarmonyOS/1.0` |

## 项目结构

```
DeepSeek/
├── AppScope/
│   ├── app.json5                         # 应用基础配置（bundleName、版本等）
│   └── resources/                        # 应用级资源
├── entry/
│   ├── build-profile.json5               # 模块构建配置
│   ├── oh-package.json5                  # 模块依赖
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/
│       │   │   └── EntryAbility.ets      # 应用入口：窗口沉浸式 + Deep Link
│       │   ├── entrybackupability/
│       │   │   └── EntryBackupAbility.ets # 备份能力
│       │   └── pages/
│       │       └── Index.ets             # 主页面：WebView 容器
│       ├── module.json5                  # 模块配置（权限、DeviceTypes、Skills）
│       ├── syscap.json                   # 2in1 能力声明
│       └── resources/                    # 模块级资源
└── hvigor/                               # 构建工具配置
```

## 技术架构

```
┌─────────────────────────────────────────┐
│              EntryAbility                │
│  · WebEngine 初始化                      │
│  · 沉浸式窗口（手机透明状态栏             │
│              2in1 隐藏标题栏）            │
│  · Deep Link 解析与路由                  │
│  · 深色/浅色模式同步                     │
└──────────────┬──────────────────────────┘
               │ loadContent('pages/Index')
┌──────────────▼──────────────────────────┐
│              Index.ets                   │
│  ┌────────────────────────────────────┐ │
│  │         WebView Component          │ │
│  │  · src: chat.deepseek.com          │ │
│  │  · darkMode: Auto                  │ │
│  │  · Custom UA                        │ │
│  │  · File Selector (Photo/Doc)       │ │
│  │  · Download Delegate               │ │
│  │  · Load Intercept (Share)          │ │
│  └────────────────────────────────────┘ │
│  · Progress Bar (linear)                │
│  · Error State (reload button)          │
└─────────────────────────────────────────┘
```

## 窗口沉浸方案

### 手机 / 平板

```
setWindowLayoutFullScreen(true)
         +
  statusBarColor: transparent
         +
  statusBarContentColor: 深色→白 / 浅色→黑
         +
  windowBackgroundColor: 与 DeepSeek 官网一致
```

### 2in1 / PC

```
setWindowDecorVisible(false)    ← 隐藏系统标题栏 logo + 名称
         +
setWindowDecorHeight(40)       ← 紧凑三键区域
         +
setWindowBackgroundColor()     ← 与 DeepSeek 官网颜色一致
```

通过 `syscap.json` 声明 `SystemCapability.Window.SessionManager`，在 2in1 设备上启用标题栏自定义能力。不支持 2in1 API 的设备会自动静默降级。

## 构建配置

### 环境要求

- **DevEco Studio** 6.0+
- **HarmonyOS SDK** API 12+
- **设备类型**：phone / tablet / 2in1

### 权限

| 权限 | 用途 |
|------|------|
| `ohos.permission.INTERNET` | WebView 网络访问 |

### Deep Link 路由

| Scheme | Host | Path 规则 | 说明 |
|--------|------|-----------|------|
| `https` | `chat.deepseek.com` | `/share*` | DeepSeek 分享链接 |

在 `module.json5` 的 `skills` 中配置，支持冷启动（`onCreate`）和热启动（`onNewWant`）。

## 构建与运行

```bash
# 1. 打开 DevEco Studio，导入项目
# 2. 连接设备或启动模拟器
# 3. 点击 Run → Run 'entry' 或按 Shift+F10
```

## 版本信息

- **Bundle Name**: `dev.sakuraneko.DeepSeek.OH`
- **Version**: 1.0.0 (1000000)
- **SDK**: HarmonyOS API 12+

## License

MIT
