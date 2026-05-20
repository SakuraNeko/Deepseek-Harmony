import { webview } from '@kit.ArkWeb';
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { url } from '@kit.ArkTS';
import { camera, cameraPicker } from '@kit.CameraKit';
import { ALLOWED_UPLOAD_EXTENSIONS } from '../common/AllowedFileExtensions';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekIndex';
const DEEPSEEK_URL = 'https://chat.deepseek.com/';

@Entry
@Component
struct Index {
  @State loadingProgress: number = 0;
  @State isLoading: boolean = true;
  @State isError: boolean = false;
  @State isNetworkError: boolean = false;
  @StorageLink('deepLinkUrl') @Watch('onDeepLinkChange') deepLinkUrl: string = '';
  controller: webview.WebviewController = new webview.WebviewController();
  delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private pageLoadTimer: number = -1;
  private readonly LOAD_TIMEOUT_MS: number = 15000;
  downloadCachePath: string = '';
  // 深色模式适配
  @StorageProp('currentColorMode') @Watch('onColorModeChange')
  currentColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @State webBgColor: Color = Color.White;
  // 2in1/PC 设备标识：用于显示拖拽手柄
  @State isPC: boolean = false;
  // 返回按钮：2in1 设备上访问非 DeepSeek 域名且有回退历史时显示
  @State showBackButton: boolean = false;
  // 上传方式选择模态框
  @State showUploadModal: boolean = false;
  private pendingFileListHandler: ((fileList: Array<string>) => void) | null = null;

  aboutToAppear(): void {
    // 检测是否为 2in1/PC 设备
    this.isPC = deviceInfo.deviceType === '2in1';
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      hilog.info(DOMAIN, TAG, 'Will load DeepLink URL: %{public}s', this.deepLinkUrl);
    }
    // 初始化背景色
    this.onColorModeChange();
  }

  // 系统深色模式切换时，同步 WebView 容器背景色，避免切换时白底闪烁
  onColorModeChange(): void {
    if (this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      this.webBgColor = Color.Black;
    } else {
      this.webBgColor = Color.White;
    }
  }

  // 拖拽指示点颜色（跟随深色/浅色模式）
  get dragIndicatorColor(): string {
    return this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      ? 'rgba(255, 255, 255, 0.45)' : 'rgba(0, 0, 0, 0.35)';
  }

  // 拖拽指示器背景色
  get dragIndicatorBgColor(): string {
    return this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.06)';
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Top }) {
        Web({ src: DEEPSEEK_URL, controller: this.controller })
          .domStorageAccess(true)
          .javaScriptAccess(true)
          .fileAccess(true)
          .mixedMode(1)
          .imageAccess(true)
          .zoomAccess(true)
          .darkMode(2)  // WebDarkMode.Auto: 跟随系统深色模式，传递 prefers-color-scheme 给网页
          .backgroundColor(this.webBgColor)
          .geolocationAccess(true)
          .width('100%')
          .height('100%')
          .onControllerAttached(() => {
            try {
              const customUA: string = this.controller.getUserAgent() + ' DeepSeek-HarmonyOS/1.0';
              this.controller.setCustomUserAgent(customUA);
            } catch (err) {
              hilog.error(DOMAIN, TAG, 'Failed to set user agent');
            }
            this.setupDownloadDelegate();
          })
          .onPageBegin((event) => {
            this.isLoading = true;
            this.isError = false;
            this.isNetworkError = false;
            this.startLoadTimeout();
          })
          .onProgressChange((event) => {
            if (event) {
              this.loadingProgress = event.newProgress;
            }
          })
          .onPageEnd(() => {
            this.isLoading = false;
            this.clearLoadTimeout();
            // 每次页面加载完成后注入剪贴板拦截脚本
            this.injectShareInterceptor();
            this.updateBackButtonState();
          })
          .onErrorReceive((event) => {
            if (event && event.error && event.error.getErrorCode() !== 0) {
              hilog.warn(DOMAIN, TAG, 'WebView net err: code=%{public}d, info=%{public}s',
                event.error.getErrorCode(), event.error.getErrorInfo());
              // 仅主框架的导航错误才触发错误页（过滤子资源错误）
              if (event.request && event.request.isMainFrame() && !this.checkNetworkAvailable()) {
                this.isNetworkError = true;
                this.isError = true;
                this.isLoading = false;
                this.clearLoadTimeout();
              }
            }
          })
          .onHttpErrorReceive((event) => {
            if (event && event.response) {
              const statusCode: number = event.response.getResponseCode();
              // 仅主框架的 HTTP 错误才触发错误页（过滤子资源如 API、图片等返回的 404/500）
              const isMainFrame: boolean = event.request ? event.request.isMainFrame() : false;
              if (statusCode >= 400 && isMainFrame) {
                hilog.error(DOMAIN, TAG, 'HTTP error: %{public}d', statusCode);
                // 先检测网络状态，再决定错误类型
                this.isNetworkError = !this.checkNetworkAvailable();
                this.isError = true;
                this.isLoading = false;
                this.clearLoadTimeout();
              } else {
                hilog.warn(DOMAIN, TAG, 'HTTP non-error status: %{public}d, mainFrame=%{public}s',
                  statusCode, String(isMainFrame));
              }
            }
          })
          .onRenderExited((event) => {
            if (event && event.renderExitReason === 2) {
              hilog.error(DOMAIN, TAG, 'Render crashed, reloading...');
              try {
                this.controller.refresh();
              } catch (err) {
                hilog.error(DOMAIN, TAG, 'Failed to refresh after crash');
              }
            }
          })
          .onShowFileSelector((event) => {
            if (!event) {
              return false;
            }
            // 仅在 chat.deepseek.com 域名下弹出上传模态框
            try {
              const pageUrl: string = this.controller.getUrl();
              const isChatDeepSeek: boolean = url.URL.parseURL(pageUrl).hostname === 'chat.deepseek.com';
              if (!isChatDeepSeek) {
                event.result.handleFileList([]);
                return true;
              }
            } catch (err) {
              event.result.handleFileList([]);
              return true;
            }
            // 存储 FileSelectorResult，弹出上传方式选择模态框供用户选择
            this.pendingFileListHandler = (fileList: Array<string>) => {
              event.result.handleFileList(fileList);
            };
            this.showUploadModal = true;
            return true;
          })
          .onLoadIntercept((event) => {
            if (!event) {
              return false;
            }
            const requestUrl: string = event.data.getRequestUrl();
            // share://?url=... 由 JS 注入触发，直接唤起系统分享
            const shareScheme: string = 'share://?url=';
            if (requestUrl.startsWith(shareScheme)) {
              const shareUrl: string = decodeURIComponent(requestUrl.substring(shareScheme.length));
              this.triggerShare(shareUrl);
              return true;
            }
            if (requestUrl.startsWith('intent://share')) {
              this.shareCurrentPage();
              return true;
            }
            // 非 DeepSeek 域名的页面跳转：仅拦截主框架导航，放行子请求（下载/资源等）
            if (!this.isDeepSeekDomain(requestUrl) && event.data.isMainFrame()
              && !this.isDownloadUrl(requestUrl)) {
              this.openInSystemBrowser(requestUrl);
              return true;
            }
            return false;
          })

        // 2in1/PC 拖拽手柄：隐藏标题栏后，用户可通过拖拽此区域移动窗口
        if (this.isPC) {
          Row() {
            Row().width(3).height(3).borderRadius(1.5).backgroundColor(this.dragIndicatorColor)
            Row().width(3).height(3).borderRadius(1.5).backgroundColor(this.dragIndicatorColor)
              .margin({ left: 3, right: 3 })
            Row().width(3).height(3).borderRadius(1.5).backgroundColor(this.dragIndicatorColor)
          }
          .width('100%')
          .height(24)
          .justifyContent(FlexAlign.Center)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              try {
                const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                window.getLastWindow(ctx).then((win: window.Window) => {
                  win.startMoving().catch((err: BusinessError) => {
                    hilog.warn(DOMAIN, TAG, 'startMoving failed: %{public}d', err.code);
                  });
                }).catch(() => {
                  hilog.warn(DOMAIN, TAG, 'getLastWindow failed');
                });
              } catch (err) {
                hilog.warn(DOMAIN, TAG, 'startMoving exception');
              }
            }
          })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(10)
        }

        if (this.isLoading) {
          Progress({ value: this.loadingProgress, type: ProgressType.Linear })
            .width('100%')
            .height(3)
            .color('#4A90D9')
            .backgroundColor('#00FFFFFF')
        }

        // 2in1 返回按钮：非 DeepSeek 域名且有回退历史时，左上角显示方形返回按钮
        if (this.showBackButton) {
          Button() {
            Text('←')
              .fontSize(20)
              .fontColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                ? '#FFFFFF' : '#333333')
          }
          .width(36)
          .height(36)
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
            ? 'rgba(40, 40, 40, 0.9)' : 'rgba(255, 255, 255, 0.9)')
          .position({ x: 36, y: 36 })
          .shadow({
            radius: 8,
            color: this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
              ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.1)',
            offsetX: 0,
            offsetY: 2
          })
          .onClick(() => {
            try {
              this.controller.backward();
              this.updateBackButtonState();
            } catch (err) {
              hilog.error(DOMAIN, TAG, 'backward failed');
            }
          })
          .zIndex(12)
        }

        if (this.isError) {
          Column() {
            Text(this.isNetworkError ? '󰚑' : '󰊠')
              .fontSize(48)
              .fontColor('#999999')
              .margin({ top: 80, bottom: 16 })
            Text(this.isNetworkError ? '网络未连接' : '页面加载失败')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .margin({ bottom: 8 })
            Text(this.isNetworkError ? '请检查设备的网络连接设置' : '请检查网络连接后重试')
              .fontSize(14)
              .fontColor('#999999')
              .margin({ bottom: 24 })
            Button('重新加载')
              .type(ButtonType.Normal)
              .fontSize(16).width(160).height(40).borderRadius(20)
              .backgroundColor('#4A90D9').fontColor(Color.White)
              .onClick(() => {
                this.isError = false;
                this.isNetworkError = false;
                this.refreshPage();
              })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.webBgColor)
        }

        // 上传方式选择模态框
        if (this.showUploadModal) {
          Column() {
            Column() {
              Text('选择上传方式')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                  ? '#FFFFFF' : '#333333')
                .margin({ bottom: 20 })

              // 横向排列：拍照 / 相册 / 文件
              Row() {
                // 拍照
                Column() {
                  Text('󰑛')
                    .fontSize(28)
                    .margin({ bottom: 8 })
                  Text('拍照')
                    .fontSize(13)
                }
                .width('30%')
                .aspectRatio(1)
                .borderRadius(14)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                  ? '#3A3A3A' : '#F5F5F5')
                .onClick(() => this.handleTakePhoto())

                // 相册
                Column() {
                  Text('󰓥')
                    .fontSize(28)
                    .margin({ bottom: 8 })
                  Text('相册')
                    .fontSize(13)
                }
                .width('30%')
                .aspectRatio(1)
                .borderRadius(14)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                  ? '#3A3A3A' : '#F5F5F5')
                .onClick(() => this.handlePickFromAlbum())

                // 文件
                Column() {
                  Text('󰃅')
                    .fontSize(28)
                    .margin({ bottom: 8 })
                  Text('文件')
                    .fontSize(13)
                }
                .width('30%')
                .aspectRatio(1)
                .borderRadius(14)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                  ? '#3A3A3A' : '#F5F5F5')
                .onClick(() => this.handlePickFile())
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceEvenly)
              .margin({ bottom: 16 })

              Text('ⓘ 仅识别图片中的文字')
                .fontSize(13)
                .fontColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
                  ? '#888888' : '#999999')
            }
            .width('85%')
            .constraintSize({ maxWidth: 360 })
            .padding(24)
            .borderRadius(16)
            .backgroundColor(this.currentColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
              ? '#2A2A2A' : '#FFFFFF')
            .shadow({ radius: 24, color: 'rgba(0,0,0,0.3)', offsetY: 8 })
            .onClick(() => {})
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(0,0,0,0.5)')
          .onClick(() => this.dismissUploadModal())
          .zIndex(100)
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.webBgColor)
  }

  onPageShow(): void {
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      this.navigateToUrl(this.deepLinkUrl);
      AppStorage.set<string>('deepLinkUrl', '');
    }
  }

  // 响应热启动时 onNewWant 设置的 deepLinkUrl 变化（onPageShow 仅在冷/温启动触发）
  onDeepLinkChange(): void {
    if (this.deepLinkUrl && this.deepLinkUrl !== '') {
      hilog.info(DOMAIN, TAG, 'DeepLink change detected: %{public}s', this.deepLinkUrl);
      this.navigateToUrl(this.deepLinkUrl);
      AppStorage.set<string>('deepLinkUrl', '');
    }
  }

  onBackPress(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        this.updateBackButtonState();
        return true;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onBackPress failed');
    }
    this.showBackButton = false;
    return false;
  }

  private startLoadTimeout(): void {
    this.clearLoadTimeout();
    this.pageLoadTimer = setTimeout(() => {
      hilog.error(DOMAIN, TAG, 'Page load timeout after %{public}d ms', this.LOAD_TIMEOUT_MS);
      this.isLoading = false;
      // 超时时检测网络：无网络则为网络错误，有网络则为加载失败
      this.isNetworkError = !this.checkNetworkAvailable();
      this.isError = true;
    }, this.LOAD_TIMEOUT_MS);
  }

  private clearLoadTimeout(): void {
    if (this.pageLoadTimer !== -1) {
      clearTimeout(this.pageLoadTimer);
      this.pageLoadTimer = -1;
    }
  }

  // 检测当前网络是否可用（基于系统网络管理 API）
  private checkNetworkAvailable(): boolean {
    try {
      // 1. 检查是否有默认激活的数据网络
      if (!connection.hasDefaultNetSync()) {
        hilog.info(DOMAIN, TAG, 'No default network');
        return false;
      }
      // 2. 获取默认网络句柄
      const netHandle = connection.getDefaultNetSync();
      if (!netHandle || netHandle.netId === 0) {
        hilog.info(DOMAIN, TAG, 'Default netId is 0');
        return false;
      }
      // 3. 验证网络是否通过互联网可达性验证
      const netCapabilities = connection.getNetCapabilitiesSync(netHandle);
      const caps: Array<connection.NetCap> = netCapabilities.networkCap || [];
      const isValidated = caps.includes(connection.NetCap.NET_CAPABILITY_VALIDATED);
      hilog.info(DOMAIN, TAG, 'Network available: %{public}s', String(isValidated));
      return isValidated;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'checkNetworkAvailable failed');
      // 异常时保守认定为无网络
      return false;
    }
  }

  // 注入 JS 覆写 navigator.clipboard.writeText：拦截 DeepSeek 分享链接转为系统分享
  private injectShareInterceptor(): void {
    try {
      this.controller.runJavaScript(`
        (function() {
          if (window.__deepseekShareHooked) return;
          window.__deepseekShareHooked = true;
          var PREFIX = 'https://chat.deepseek.com/share/';
          if (navigator.clipboard && navigator.clipboard.writeText) {
            var _orig = navigator.clipboard.writeText.bind(navigator.clipboard);
            navigator.clipboard.writeText = function(text) {
              if (typeof text === 'string' && text.indexOf(PREFIX) === 0) {
                window.location.href = 'share://?url=' + encodeURIComponent(text);
                return Promise.resolve();
              }
              return _orig(text);
            };
          }
        })();
      `);
    } catch (err) {
      // JS injection may fail on restricted pages, ignore silently
    }
  }

  // 统一分享入口：唤起系统分享面板
  private triggerShare(url: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.HYPERLINK,
        content: url,
        title: 'DeepSeek',
        description: '来自DeepSeek的分享内容'
      });
      shareData.addRecord({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: 'DeepSeek分享:\n' + url
      });
      const shareController = new systemShare.ShareController(shareData);
      shareController.on('dismiss', () => {
        hilog.info(DOMAIN, TAG, 'Share dismissed');
      });
      shareController.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Share failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Share error');
    }
  }

  private shareCurrentPage(): void {
    try {
      let currentUrl: string = DEEPSEEK_URL;
      try {
        const webUrl: string = this.controller.getUrl();
        if (webUrl && webUrl !== '') {
          currentUrl = webUrl;
        }
      } catch (e) {
        // fallback to default URL
      }
      this.triggerShare(currentUrl);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Share error');
    }
  }

  // 判断 URL 是否属于 DeepSeek 域名（chat.deepseek.com 及其子域名）
  private isDeepSeekDomain(requestUrl: string): boolean {
    try {
      const parsed = url.URL.parseURL(requestUrl);
      const hostname: string = parsed.hostname;
      return hostname === 'chat.deepseek.com' || hostname.endsWith('.deepseek.com');
    } catch (e) {
      // URL 解析失败时保守处理，允许在 WebView 内加载
      return true;
    }
  }

  // 判断 URL 是否为下载链接（根据常见文件扩展名）
  private isDownloadUrl(requestUrl: string): boolean {
    const downloadExtensions = [
      '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz',
      '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp',
      '.mp3', '.mp4', '.avi', '.mov', '.mkv', '.flv', '.wmv',
      '.exe', '.msi', '.apk', '.dmg', '.deb', '.rpm',
      '.csv', '.json', '.xml', '.sql', '.db',
      '.iso', '.img', '.bin',
      '.txt', '.md', '.log'
    ];
    try {
      const parsed = url.URL.parseURL(requestUrl);
      const pathname: string = (parsed.pathname || '').toLowerCase();
      return downloadExtensions.some(ext => pathname.endsWith(ext));
    } catch (_e) {
      return false;
    }
  }

  // 更新 2in1 返回按钮显示状态：仅 PC 设备 + 有回退历史 + 当前页非 chat.deepseek.com 时显示
  private updateBackButtonState(): void {
    if (!this.isPC) {
      this.showBackButton = false;
      return;
    }
    try {
      const hasHistory: boolean = this.controller.accessBackward();
      if (!hasHistory) {
        this.showBackButton = false;
        return;
      }
      const pageUrl: string = this.controller.getUrl();
      if (pageUrl === '') {
        this.showBackButton = false;
        return;
      }
      const isChatDeepSeek: boolean = url.URL.parseURL(pageUrl).hostname === 'chat.deepseek.com';
      this.showBackButton = !isChatDeepSeek;
    } catch (err) {
      this.showBackButton = false;
    }
  }

  // 调用系统浏览器打开外部链接
  private openInSystemBrowser(openUrl: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: openUrl
      };
      context.startAbility(want).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Failed to open system browser: %{public}s', err.message);
        this.getUIContext().getPromptAction().showToast({ message: '无法打开外部链接', duration: 2000 });
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'openInSystemBrowser error');
    }
  }

  private navigateToUrl(url: string): void {
    try {
      this.controller.loadUrl(url);
      this.isError = false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'navigateToUrl failed');
    }
  }

  private refreshPage(): void {
    try {
      this.controller.refresh();
      this.isError = false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'refreshPage failed');
    }
  }

  private setupDownloadDelegate(): void {
    try {
      this.delegate.onBeforeDownload((webDownloadItem: webview.WebDownloadItem) => {
        const fileName: string = webDownloadItem.getSuggestedFileName();
        hilog.info(DOMAIN, TAG, 'Download start: %{public}s', fileName);
        // 下载到沙箱 web 缓存目录
        this.downloadCachePath = this.getUIContext().getHostContext()!.cacheDir + '/web/' + fileName;
        webDownloadItem.start(this.downloadCachePath);
      });

      this.delegate.onDownloadUpdated((webDownloadItem: webview.WebDownloadItem) => {
        const percent: number = webDownloadItem.getPercentComplete();
        hilog.info(DOMAIN, TAG, 'Download progress: %{public}d%%', percent);
      });

      this.delegate.onDownloadFinish((webDownloadItem: webview.WebDownloadItem) => {
        hilog.info(DOMAIN, TAG, 'Download finish: %{public}s', webDownloadItem.getGuid());
        this.getUIContext().getPromptAction().showToast({
          message: '下载完成',
          duration: 2000
        });
        // 可选：下载完成后打开系统保存弹窗，允许用户另存至公共目录
        this.saveToPublicDownload(webDownloadItem.getSuggestedFileName());
      });

      this.delegate.onDownloadFailed((webDownloadItem: webview.WebDownloadItem) => {
        hilog.error(DOMAIN, TAG, 'Download failed: code=%{public}d',
          webDownloadItem.getLastErrorCode());
        this.getUIContext().getPromptAction().showToast({
          message: '下载失败',
          duration: 2000
        });
      });

      this.controller.setDownloadDelegate(this.delegate);
      hilog.info(DOMAIN, TAG, 'Download delegate registered');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to setup download delegate');
    }
  }

  private saveToPublicDownload(fileName: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      documentSaveOptions.newFileNames = [fileName];

      const documentViewPicker = new picker.DocumentViewPicker(context);
      documentViewPicker.save(documentSaveOptions).then((result: Array<string>) => {
        if (result.length === 0 || !result[0]) {
          return;
        }
        const uri: string = result[0];
        // DOWNLOAD 模式返回的是文件夹路径，需拼接文件名
        const pubDir: string = new fileUri.FileUri(uri).path;
        const pubFilePath: string = pubDir + '/' + fileName;
        const srcPath: string = this.downloadCachePath;
        hilog.info(DOMAIN, TAG, 'Copy from sandbox to public: %{public}s -> %{public}s',
          srcPath, pubFilePath);

        let srcFile: fs.File | null = null;
        let dstFile: fs.File | null = null;
        try {
          srcFile = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
          dstFile = fs.openSync(pubFilePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
          fs.copyFileSync(srcFile.fd, dstFile.fd);
          this.getUIContext().getPromptAction().showToast({
            message: '已保存到下载目录',
            duration: 2000
          });
        } catch (e) {
          const err = e as BusinessError;
          hilog.error(DOMAIN, TAG, 'File copy failed: code=%{public}d, msg=%{public}s',
            err.code, err.message);
        } finally {
          if (srcFile) {
            fs.closeSync(srcFile);
          }
          if (dstFile) {
            fs.closeSync(dstFile);
          }
        }
      }).catch((err: BusinessError) => {
        hilog.info(DOMAIN, TAG, 'User cancelled save dialog');
      });
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'Save dialog not supported on this device');
    }
  }

  // 关闭上传模态框，若用户未选择则回传空列表
  private dismissUploadModal(): void {
    this.showUploadModal = false;
    if (this.pendingFileListHandler) {
      this.pendingFileListHandler([]);
      this.pendingFileListHandler = null;
    }
  }

  // 拍照：使用 CameraPicker 调用系统相机
  private async handleTakePhoto(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pathDir: string = context.filesDir;
      const fileName: string = `${new Date().getTime()}.jpg`;
      const filePath: string = pathDir + '/' + fileName;
      fs.createRandomAccessFileSync(filePath, fs.OpenMode.CREATE);
      const saveUri: string = fileUri.getUriFromPath(filePath);
      const pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: saveUri
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(
        context, [cameraPicker.PickerMediaType.PHOTO], pickerProfile);
      if (result.resultCode === 0 && result.resultUri) {
        if (this.pendingFileListHandler) {
          this.pendingFileListHandler([result.resultUri]);
        }
        this.showUploadModal = false;
        this.pendingFileListHandler = null;
      }
      // 用户取消拍照时不关闭模态框，不通知 web 端
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'CameraPicker cancelled or failed');
    }
  }

  // 相册：使用 PhotoViewPicker 安全选择图片
  private handlePickFromAlbum(): void {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 5;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(photoSelectOptions).then((photoResult) => {
        if (photoResult.photoUris && photoResult.photoUris.length > 0
          && this.pendingFileListHandler) {
          this.pendingFileListHandler(photoResult.photoUris);
          this.showUploadModal = false;
          this.pendingFileListHandler = null;
        }
        // 空结果（含取消）时保留模态框，不通知 web 端
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'PhotoPicker err: %{public}s', err.message);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'PhotoPicker failed');
    }
  }

  // 文件：使用 DocumentViewPicker 选择通用文件
  private handlePickFile(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const docOptions = new picker.DocumentSelectOptions();
      docOptions.fileSuffixFilters = ALLOWED_UPLOAD_EXTENSIONS;
      const docPicker = new picker.DocumentViewPicker(context);
      docPicker.select(docOptions).then((docResult) => {
        if (docResult && docResult.length > 0 && this.pendingFileListHandler) {
          this.pendingFileListHandler(docResult);
          this.showUploadModal = false;
          this.pendingFileListHandler = null;
        }
        // 空结果（含取消）时保留模态框，不通知 web 端
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'DocPicker err: %{public}s', err.message);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'DocPicker failed');
    }
  }
}
