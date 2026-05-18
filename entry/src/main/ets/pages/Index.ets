import { webview } from '@kit.ArkWeb';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, window } from '@kit.ArkUI';

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
  @StorageLink('deepLinkUrl') deepLinkUrl: string = '';
  controller: webview.WebviewController = new webview.WebviewController();
  delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
  private pageLoadTimer: number = -1;
  private readonly LOAD_TIMEOUT_MS: number = 15000;
  downloadCachePath: string = '';
  isDownloading: boolean = false;
  // 深色模式适配
  @StorageProp('currentColorMode') @Watch('onColorModeChange')
  currentColorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @State webBgColor: Color = Color.White;
  // 2in1/PC 设备标识：用于显示拖拽手柄
  @State isPC: boolean = false;

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
            const acceptTypes: Array<string> = event.fileSelector.getAcceptType();
            const isImageOnly: boolean = acceptTypes.length > 0 &&
              acceptTypes.every((type: string): boolean => type.startsWith('image/'));

            if (isImageOnly) {
              const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
              photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
              photoSelectOptions.maxSelectNumber = 5;
              const photoPicker = new photoAccessHelper.PhotoViewPicker();
              photoPicker.select(photoSelectOptions).then((photoResult) => {
                if (photoResult.photoUris && photoResult.photoUris.length > 0) {
                  event.result.handleFileList(photoResult.photoUris);
                }
              }).catch((err: BusinessError) => {
                hilog.error(DOMAIN, TAG, 'PhotoPicker err: %{public}s', err.message);
                event.result.handleFileList([]);
              });
            } else {
              const docOptions = new picker.DocumentSelectOptions();
              const docPicker = new picker.DocumentViewPicker();
              docPicker.select(docOptions).then((docResult) => {
                if (docResult && docResult.length > 0) {
                  event.result.handleFileList(docResult);
                }
              }).catch((err: BusinessError) => {
                hilog.error(DOMAIN, TAG, 'DocPicker err: %{public}s', err.message);
                event.result.handleFileList([]);
              });
            }
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
              const url: string = decodeURIComponent(requestUrl.substring(shareScheme.length));
              this.triggerShare(url);
              return true;
            }
            if (requestUrl.startsWith('intent://share')) {
              this.shareCurrentPage();
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
                }).catch((err: BusinessError) => {
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

        if (this.isError) {
          Column() {
            Text(this.isNetworkError ? '📡' : '⚠')
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

  onBackPress(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onBackPress failed');
    }
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
        this.isDownloading = true;
        // 下载到沙箱 web 缓存目录
        this.downloadCachePath = this.getUIContext().getHostContext()!.cacheDir + '/web/' + fileName;
        webDownloadItem.start(this.downloadCachePath);
      });

      this.delegate.onDownloadUpdated((webDownloadItem: webview.WebDownloadItem) => {
        const percent: number = webDownloadItem.getPercentComplete();
        hilog.info(DOMAIN, TAG, 'Download progress: %{public}d%%', percent);
      });

      this.delegate.onDownloadFinish((webDownloadItem: webview.WebDownloadItem) => {
        this.isDownloading = false;
        hilog.info(DOMAIN, TAG, 'Download finish: %{public}s', webDownloadItem.getGuid());
        promptAction.showToast({
          message: '下载完成',
          duration: 2000
        });
        // 可选：下载完成后打开系统保存弹窗，允许用户另存至公共目录
        this.saveToPublicDownload(webDownloadItem.getSuggestedFileName());
      });

      this.delegate.onDownloadFailed((webDownloadItem: webview.WebDownloadItem) => {
        this.isDownloading = false;
        hilog.error(DOMAIN, TAG, 'Download failed: code=%{public}d',
          webDownloadItem.getLastErrorCode());
        promptAction.showToast({
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
          promptAction.showToast({
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
}
