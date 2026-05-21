# DeepSeek for HarmonyOS

基于 HarmonyOS WebView 封装的 DeepSeek AI 客户端，支持手机、平板和 2in1。

## 功能

| 功能 | 说明 |
|------|------|
| 🌐 WebView | 内嵌 chat.deepseek.com，完整对话体验 |
| 🌍 系统语言 | 跟随系统语言注入 WebView，支持动态切换 |
| 🔗 Deep Link | 冷/温/热启动接收分享链接并导航 |
| 🌙 深色模式 | 跟随系统自动切换 |
| 📤 文件上传 | 拍照 / 相册 / 文档选择器 |
| 💾 文件下载 | WebView 下载转存至公共下载目录 |
| 📲 系统分享 | 拦截分享链接，唤起系统分享面板 |
| 🔄 稳定性 | 渲染崩溃自动刷新 + 15s 超时错误页 |

## 项目结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets   # 窗口沉浸 + Deep Link + 系统语言初始化
├── pages/Index.ets                 # WebView 主页面
└── common/AllowedFileExtensions.ets
```

## Deep Link

支持从其他 App / 短信 / 扫码打开 `https://chat.deepseek.com/share/...` 分享链接。

> **浏览器中点击同域链接不会唤醒应用**，原因：`chat.deepseek.com` 非自有域名，无法托管 AGC 域名校验文件。

## 构建

| 要求 | 版本 |
|------|------|
| DevEco Studio | 6.0+ |
| HarmonyOS SDK | API 23+ |
| 权限 | ohos.permission.INTERNET, ohos.permission.GET_NETWORK_INFO |

## 版本

`dev.sakuraneko.DeepSeek.OH` — v1.1.3 (1001030)

## License

MIT
