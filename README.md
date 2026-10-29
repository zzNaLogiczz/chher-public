<p align="center">
  <img src="assets/brand/chher-logo.png" width="88" alt="Chher" />
</p>

<h1 align="center">Chher</h1>

<p align="center"><strong>更专注地逛 Chiphell。</strong></p>

<p align="center">一个用 Flutter 构建的非官方 Android 客户端，把帖子、评测和讨论带进原生界面。</p>

<p align="center">
  <a href="pubspec.yaml"><img src="https://img.shields.io/badge/version-1.0.3-646464?labelColor=60646c" alt="Version 1.0.3" /></a>
  <a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-3.44.2-0d74ce?logo=flutter&amp;labelColor=60646c" alt="Flutter 3.44.2" /></a>
  <a href="https://dart.dev/"><img src="https://img.shields.io/badge/Dart-3.12.2-0d74ce?logo=dart&amp;labelColor=60646c" alt="Dart 3.12.2" /></a>
  <a href="https://developer.android.com/about/versions/nougat"><img src="https://img.shields.io/badge/Android-7.0%2B-218358?logo=android&amp;logoColor=ffffff&amp;labelColor=60646c" alt="Android 7.0+" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-PolyForm_NC_1.0.0-8145b5?labelColor=60646c" alt="License: PolyForm Noncommercial 1.0.0" /></a>
</p>

<p align="center">
  <a href="#阅读与讨论">功能</a> ｜
  <a href="#快速开始">快速开始</a> ｜
  <a href="https://github.com/zzNaLogiczz/chher-public/issues">反馈问题</a> ｜
  <a href="#使用许可">使用许可</a>
</p>

## 阅读与讨论

看评测、翻长帖、追回复，也能把自己的体验分享出去。Chher 围绕这些日常动作组织界面，让内容和正在进行的讨论保持在视线里。

### 长帖，连着看

正文连续阅读，图片点开查看，站内链接直接跳转，B 站视频在应用内播放。门户评测和论坛帖子都能用熟悉的方式浏览。

### 回复，顺着聊

评论可以按引用关系归组，也可以切回原楼层，或只看楼主。楼内回复就地展开，引用支持跳转，长讨论更容易跟上。

### 从阅读到参与

回复、发帖、文章评论、私信都在应用内完成。图片附件支持压缩上传，编辑内容保留为草稿；遇到验证码时，可转到原站网页继续处理。

| 入口 | 能做什么 |
| --- | --- |
| **精选** | 浏览门户精选、评测、快讯，以及社区最新与热门讨论 |
| **版块** | 按分区找内容，筛选版块、折叠置顶帖、搜索帖子 |
| **消息** | 查看提醒，阅读和回复私信 |
| **我的** | 访问个人主页、我的帖子、收藏、积分和勋章 |
| **原页面** | 随时打开对应的原站页面，继续使用网页功能 |
| **应用更新** | 查看更新说明、续传安装包，校验后交给系统安装 |

## 快速开始

当前支持 **Android 7.0 及以上**。开发环境使用 Flutter **3.44.2**、Dart **3.12.2**、JDK **17** 和 Android SDK。

```sh
git clone https://github.com/zzNaLogiczz/chher-public.git
cd chher-public
flutter pub get
flutter run
```

连接多个设备时，先运行 `flutter devices`，再用 `flutter run -d <设备ID>` 指定目标设备。普通开发使用调试签名即可。

<details>
<summary><strong>构建正式 APK</strong></summary>

先准备自己的 Android 签名密钥，再复制配置示例：

```sh
cp android/key.properties.example android/key.properties
```

在 `android/key.properties` 中填写 keystore 路径、别名和密码，然后构建：

```sh
tool/build_release.sh 1.0.3             # ARM64 与 ARMv7
tool/build_release.sh 1.0.3 --universal # 另生成通用包
```

安装包位于 `build/release/1.0.3/`。版本号 `1.0.3` 对应 versionCode `10003`；脚本按架构分别构建，避免 `--split-per-abi` 带来的版本号偏移。

自行签名的包不能覆盖维护者签名的版本。分发衍生版本时，请使用自己的应用标识、签名及更新服务，并遵守项目许可。

</details>

## 为开发者

Chher 直接获取源站 HTML，再解析为数据模型和 Flutter 界面。网络层支持 HTTP 与 WebView，Android 原生通道负责图片处理、输入法兼容、刷新率和安装等能力。

```text
lib/
  network/       网络请求、Cookie 与会话
  parser/        HTML 解析
  data/          数据仓库与业务编排
  attachments/   图片处理与上传状态
  pages/         页面
  widgets/       业务组件
  ui/、design/   通用交互与视觉规范
  update/        更新检查、下载与验签
```

修改后可在本地运行：

```sh
flutter analyze
flutter test
```

解析器测试使用人工构造的 HTML，无需登录论坛。样本维护方式见 [test_data/README.md](test_data/README.md)。

欢迎通过 [Issue](https://github.com/zzNaLogiczz/chher-public/issues) 提交问题和建议，或通过 Pull Request 改进代码。反馈问题时，请附上复现步骤、应用与 Android 版本；日志和截图请先去除个人信息。提交贡献前，请确认你有权提供相关代码和素材。

## 关于这个客户端

Chher 是个人维护的非官方项目，与 Chiphell 官方没有隶属或背书关系。站点内容直接由客户端访问，登录使用原站网页，发帖与上传仍遵循原站的账号权限和规则。源站页面结构变化可能影响解析兼容性。

登录状态保存在设备本地。应用更新由独立服务提供；检查更新时会发送应用版本、CPU 架构和本地生成的安装标识，用于版本匹配与更新统计。

## 使用许可

**源码公开，非商业使用；商业用途另行授权。**

本项目自有代码采用 [PolyForm Noncommercial License 1.0.0](LICENSE)。你可以在许可范围内使用、研究、修改和分发代码。分发时应保留许可证或其链接，以及 [NOTICE](NOTICE) 中要求保留的声明。

超出许可证许可范围的商业用途，例如以盈利为目的销售衍生应用、广告变现或提供收费服务，须先取得相关权利人的书面授权。商业合作请联系 [zznalogic@gmail.com](mailto:zznalogic@gmail.com)。

PolyForm Noncommercial 属于源码可用许可，**不是 OSI 定义的开源许可证**。教育、慈善、公共研究等组织的明确许可，以及其他权利和义务，均以 `LICENSE` 原文为准。

第三方组件与图形保留各自的许可，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。Chiphell 的商标、站点内容和用户作品不在本项目授权范围内。第三方贡献的版权仍属于其权利人，额外商业授权须覆盖相应权利。
