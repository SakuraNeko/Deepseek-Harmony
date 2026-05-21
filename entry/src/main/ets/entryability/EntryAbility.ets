import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { url } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';

const DOMAIN = 0x0001;
const TAG = 'DeepSeekEntryAbility';
let webEngineInitialized: boolean = false;
let mainWindowClass: window.Window | null = null;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Web引擎只初始化一次，避免重复初始化导致异常
    if (!webEngineInitialized) {
      try {
        webview.WebviewController.initializeWebEngine();
        webEngineInitialized = true;
        hilog.info(DOMAIN, TAG, 'WebEngine initialized');
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Failed to initialize WebEngine');
      }
    }

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode');
    }

    // 将当前系统颜色模式存入 AppStorage，供 WebView 深色模式适配
    AppStorage.setOrCreate<ConfigurationConstant.ColorMode>('currentColorMode', this.context.config.colorMode);
    hilog.info(DOMAIN, TAG, 'Initial colorMode: %{public}d', this.context.config.colorMode);

    // 将当前系统语言存入 AppStorage，供 WebView 语言适配
    try {
      const systemLanguage: string = i18n.System.getSystemLanguage();
      AppStorage.setOrCreate<string>('systemLanguage', systemLanguage);
      hilog.info(DOMAIN, TAG, 'Initial systemLanguage: %{public}s', systemLanguage);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get system language');
    }

    // 处理Deep Link跳转（冷启动）
    this.handleDeepLink(want);

    // 非DeepLink启动：清空残留URL，防止旧值干扰
    if (!want?.uri) {
      AppStorage.setOrCreate('deepLinkUrl', '');
    }

    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  // 监听系统深色/浅色模式切换，同步更新 AppStorage 与状态栏样式
  onConfigurationUpdate(newConfig: Configuration): void {
    const newColorMode: ConfigurationConstant.ColorMode | undefined = newConfig.colorMode;
    if (newColorMode === undefined) {
      return;
    }
    const currentColorMode: ConfigurationConstant.ColorMode | undefined = AppStorage.get('currentColorMode');
    if (currentColorMode !== newColorMode) {
      AppStorage.setOrCreate<ConfigurationConstant.ColorMode>('currentColorMode', newColorMode);
      hilog.info(DOMAIN, TAG, 'ColorMode changed: %{public}d -> %{public}d', currentColorMode, newColorMode);
      this.applyStatusBarStyle();
    }

    // 监听系统语言变化，同步更新 AppStorage
    const newLanguage: string | undefined = newConfig.language;
    if (newLanguage !== undefined) {
      const currentLanguage: string | undefined = AppStorage.get('systemLanguage');
      if (currentLanguage !== newLanguage) {
        AppStorage.setOrCreate<string>('systemLanguage', newLanguage);
        hilog.info(DOMAIN, TAG, 'Language changed: %{public}s -> %{public}s', currentLanguage, newLanguage);
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');

      // 设置窗口全屏沉浸：内容延伸至状态栏后方，状态栏透明
      mainWindowClass = windowStage.getMainWindowSync();
      if (mainWindowClass) {
        // 立即设置窗口背景色，避免启动闪白/闪黑（与 DeepSeek 官网颜色一致）
        const isDark: boolean =
          this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
        try {
          mainWindowClass.setWindowBackgroundColor(isDark ? '#FF1A1A1A' : '#FFFFFFFF');
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor not supported');
        }

        // 手机/平板：窗口沉浸式布局，内容延伸至状态栏后方
        // setWindowLayoutFullScreen 已废弃，使用 setImmersiveModeEnabledState 替代
        try {
          mainWindowClass.setImmersiveModeEnabledState(true);
          hilog.info(DOMAIN, TAG, 'Immersive mode enabled');
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'setImmersiveModeEnabledState not supported');
        }

        // 2in1 / PC：隐藏系统标题栏（logo + 应用名称），内容区接管整个窗口
        // 实现标题栏沉浸：标题栏区域背景色与 DeepSeek 官网顶部颜色一致
        try {
          mainWindowClass.setWindowDecorVisible(false);
          hilog.info(DOMAIN, TAG, '2in1: title bar decor hidden');
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'setWindowDecorVisible not available');
        }
        try {
          mainWindowClass.setWindowDecorHeight(40);
          hilog.info(DOMAIN, TAG, '2in1: decor height set to 40');
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'setWindowDecorHeight not available');
        }

        // 初始设置状态栏内容颜色（根据当前模式）
        this.applyStatusBarStyle();
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }

  /**
   * 设置状态栏透明 + 窗口背景 + 内容颜色跟随深色/浅色模式
   * 手机端：状态栏背景透明，透出 DeepSeek 网页顶部背景色
   * 2in1端：窗口背景色与 DeepSeek 官网一致，隐藏标题栏 logo/文字后实现沉浸
   */
  private applyStatusBarStyle(): void {
    if (!mainWindowClass) {
      return;
    }
    const isDark: boolean =
      this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;

    // 手机端：状态栏透明 + 内容文字颜色适配
    const sysBarProps: window.SystemBarProperties = {
      statusBarColor: '#00000000',
      statusBarContentColor: isDark ? '#FFFFFF' : '#000000'
    };
    try {
      mainWindowClass.setWindowSystemBarProperties(sysBarProps).then(() => {
        hilog.info(DOMAIN, TAG, 'StatusBar updated');
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}d', err.code);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'applyStatusBarStyle exception');
    }

    // 设置窗口背景色，与 DeepSeek 官网颜色一致
    // 浅色→#FFFFFFFF（白）  深色→#FF1A1A1A（暗）
    // 2in1端隐藏标题栏后，窗口背景会从标题栏区域透出，颜色需与网页顶部一致
    try {
      const winBgColor: string = isDark ? '#FF1A1A1A' : '#FFFFFFFF';
      mainWindowClass.setWindowBackgroundColor(winBgColor);
      hilog.info(DOMAIN, TAG, 'Window bg color set: %{public}s', winBgColor);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor not supported');
    }
  }

  /**
   * 热启动时接收新的Deep Link
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant');
    this.handleDeepLink(want);
  }

  /**
   * 解析并处理Deep Link URL
   * 支持的URL格式：https://chat.deepseek.com/share/...
   */
  private handleDeepLink(want: Want): void {
    const uri = want?.uri;
    if (!uri) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'Received DeepLink URI: %{public}s', uri);

    try {
      const urlObject = url.URL.parseURL(uri);
      const host = urlObject.hostname;
      const path = urlObject.pathname;

      // 处理DeepSeek分享链接
      if (host === 'chat.deepseek.com' && path.startsWith('/share')) {
        hilog.info(DOMAIN, TAG, 'DeepSeek share link detected, navigating to: %{public}s', uri);
        AppStorage.setOrCreate('deepLinkUrl', uri);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to parse DeepLink URI');
    }
  }
}
