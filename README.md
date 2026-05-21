# DeepSeek for HarmonyOS

基于 HarmonyOS WebView 封装的 DeepSeek AI 对话客户端，支持手机、平板和 2in1 设备。

## 功能

| 功能 | 说明 |
|------|------|
| 🌐 WebView 封装 | 内嵌 `chat.deepseek.com`，完整 AI 对话体验 |
| 🔗 Deep Link | 分享链接 `https://chat.deepseek.com/share/...` 冷/热启动跳转 |
| 🌙 深色模式 | 跟随系统深色/浅色模式自动切换 |
| 📱 沉浸式窗口 | 手机透明状态栏，2in1 隐藏系统标题栏 |
| 📤 文件上传 | 系统相册 + 文档选择器 |
| 💾 文件下载 | WebView 下载 + 另存至公共下载目录 |
| 📲 系统分享 | 调用系统分享面板分享当前页面 |
| 🔄 崩溃恢复 | Web 渲染进程崩溃自动刷新 |
| ⏱ 超时处理 | 15 秒加载超时，错误页 + 重试 |
| 🏷 自定义 UA | 请求头追加 `DeepSeek-HarmonyOS/1.0` |

## 项目结构

```
DeepSeek/
├── AppScope/app.json5                         # 应用基础配置
├── entry/src/main/
│   ├── ets/
│   │   ├── entryability/EntryAbility.ets      # 入口：窗口沉浸 + Deep Link
│   │   └── pages/Index.ets                    # 主页面：WebView 容器
│   ├── module.json5                           # 模块配置（权限、Skills）
│   └── resources/
└── hvigor/
```

## Deep Link / App Linking

### 当前实现

应用已完整实现 `https://chat.deepseek.com/share/...` 分享链接的接收与导航：

| 启动场景 | 处理方式 | 状态 |
|---------|---------|------|
| 冷启动 | `onCreate` → `handleDeepLink()` → `AppStorage` → `@Watch` 导航 | ✅ |
| 温启动（后台唤醒） | `onNewWant` → `handleDeepLink()` → 同上 | ✅ |
| 热启动（前台驻留） | `onNewWant` → `handleDeepLink()` → `@Watch` 触发导航 | ✅ |

### 已知限制：浏览器中无法唤醒

**从浏览器点击 `https://chat.deepseek.com/share/...` 链接不会打开本应用**，原因如下：

1. **域名所有权问题**：`chat.deepseek.com` 是 DeepSeek 公司域名，开发者无法在该域名的服务器上托管 App Linking 所需的 `applinking.json` 验证文件。

2. **同域链接规则**：即使完成域名校验，当用户在 `chat.deepseek.com` 页面点击同域链接时，系统会维持浏览体验、继续在浏览器中打开，不会拉起应用。这是系统级设计。

3. **AGC 域名校验**：App Linking 要求：
   - ~~在域名服务器托管 `https://chat.deepseek.com/.well-known/applinking.json`~~ ❌ 无权限
   - ~~在 AGC 后台发布域名关联~~ ❌ 无法通过校验

### 可行的触发方式

| 触发方式 | 能否唤醒 App | 说明 |
|---------|------------|------|
| **浏览器点击同域链接** | ❌ | 无法绕过域名所有权 + 同域规则 |
| **其他 App 调用 `openLink()`** | ✅ | 通过 `appLinkingOnly: false` 走 Deep Linking 匹配 |
| **短信 / 备忘录中的链接** | ✅ | 系统链接识别机制 |
| **扫码（二维码）** | ✅ | 系统扫一扫入口 |
| **碰一碰分享** | ✅ | Share Kit 跨设备分享 |

### 若需浏览器唤醒（未来方案）

如需实现"浏览器点击 → 唤醒 App"，需：

1. 注册自有域名（如 `deepseek-share.example.com`）
2. 在该域名服务器托管 `applinking.json`（包含 APP ID）
3. 在 AGC 后台「增长 → App Linking → 应用链接」创建并发布域名关联
4. 修改 `module.json5` 中 skills 的 `host` 为自有域名
5. 分享链接改为自有域名格式

### 调试

```bash
# 验证域名校验状态
hdc shell hidumper -s AppDomainVerifyManager
# 输出中查看对应域名是否为 success
```

> **注意**：App Linking **禁止使用 DevEco Studio 自动签名**，必须使用手动签名才能验证域名校验。

## 构建与运行

| 要求 | 版本 |
|------|------|
| DevEco Studio | 6.0+ |
| HarmonyOS SDK | API 12+ |
| 目标设备 | phone / tablet / 2in1 |

所需权限：`ohos.permission.INTERNET`

```bash
# DevEco Studio → Run 'entry' 或 Shift+F10
```

## 版本

| 字段 | 值                            |
|------|------------------------------|
| Bundle Name | `dev.sakuraneko.DeepSeek.OH` |
| Version | 1.1.3 (1001030)              |
| SDK | HarmonyOS API 23+            |

## License

MIT
