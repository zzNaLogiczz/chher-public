# 第三方软件与素材声明

本项目的许可证仅适用于有权按该许可证授权的项目代码。第三方软件、图形、字体及其修改仍受各自许可证约束；本项目的非商业限制和单独商业授权不替代第三方许可证，也不限制第三方原本授予的权利。

## Flutter 与直接运行时依赖

下表按当前 `pubspec.lock` 及 Flutter 3.44.2 SDK 中随包提供的 `LICENSE` 文件核对。依赖通过 Flutter/Dart 工具下载，完整依赖版本以 `pubspec.lock` 为准。此表列出直接运行时依赖，不是 APK 内全部传递依赖及原生库的完整清单；分发二进制时还须保留实际构建中各组件要求的许可证和声明。

| 组件 | 核对版本 | 许可证 | 主要版权归属与许可原文 |
| --- | --- | --- | --- |
| Flutter SDK | 3.44.2 | BSD-3-Clause | The Flutter Authors；[原文](https://github.com/flutter/flutter/blob/3.44.2/LICENSE) |
| cupertino_icons | 1.0.9 | MIT | Vladimir Kharlampidi；[原文](https://pub.dev/packages/cupertino_icons/versions/1.0.9/license) |
| dio | 5.11.1 | MIT | Wen Du、The CFUG Team；[原文](https://pub.dev/packages/dio/versions/5.11.1/license) |
| html | 0.15.7 | MIT | HTML 解析器原作者、Mozilla Foundation、Google LLC 等，完整名单见[原文](https://pub.dev/packages/html/versions/0.15.7/license) |
| flutter_inappwebview | 6.1.5 | Apache-2.0 | 上游项目及贡献者；[原文](https://pub.dev/packages/flutter_inappwebview/versions/6.1.5/license) |
| solar_icons（Dart 包代码） | 0.2.0 | BSD-3-Clause | Sebastine Odeh；[原文](https://pub.dev/packages/solar_icons/versions/0.2.0/license)。原始图形另见下节。 |
| motor | 1.1.0 | MIT | Tim Lehmann for whynotmake.it；[原文](https://pub.dev/packages/motor/versions/1.1.0/license) |
| smooth_sheets | 1.2.0 | MIT | Daichi Fujita；[原文](https://pub.dev/packages/smooth_sheets/versions/1.2.0/license) |
| url_launcher | 6.3.3 | BSD-3-Clause | The Flutter Authors；[原文](https://pub.dev/packages/url_launcher/versions/6.3.3/license) |
| url_launcher_android | 6.3.25 | BSD-3-Clause | The Flutter Authors；[原文](https://pub.dev/packages/url_launcher_android/versions/6.3.25/license) |

开发工具和测试依赖也保留各自许可证；不因仅用于开发而改为本项目许可证。

## Solar Icons 图形

图形来自 **Solar Icon Set by 480 Design**，通过 `solar_icons` 的 Flutter 图标字体封装使用。原始图形按 **Creative Commons Attribution 4.0 International（CC BY 4.0）** 许可；Dart 包代码的 BSD-3-Clause 许可与图形许可是不同层次的授权。

- 原作：[Solar Icon Set / 480 Design](https://www.figma.com/community/file/1166831539721848736)，[作者仓库](https://github.com/480-Design/Solar-Icon-Set)。
- 图形许可：[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)，[完整法律文本](https://creativecommons.org/licenses/by/4.0/legalcode)。
- 图形许可说明：[Solar Icons 项目说明](https://solar-icons.dev/docs/v1/community/license)。
- 使用方式：图形由上游包封装为字体；应用在界面中设置尺寸、颜色，发布构建会裁剪未使用的字形。

分发这些图形或其衍生版本时，须保留作者归属、许可链接，并按 CC BY 4.0 标明修改；本项目不对这些图形另加禁止商业使用的限制。

## Gradle Wrapper

仓库包含 Gradle Wrapper 启动脚本及 `android/gradle/wrapper/gradle-wrapper.jar`。JAR 中的 `Implementation-Version` 和 `build-receipt.properties` 标明它来自 **Gradle 2.10**，上游提交为 `276bdcded730f53aa8c11b479986aafa58e124a6`。`gradle-wrapper.properties` 配置下载的 **Gradle 8.12** 是被启动的构建工具版本，两者不能混同。

该 JAR 未内置 `LICENSE` 或 `NOTICE`，已在仓库中补充：

- [完整 Apache License 2.0](third_party/gradle/LICENSE)。
- [Wrapper 与 CLI 组件的版权和来源声明](third_party/gradle/NOTICE)。

本仓库中的 JAR 仅包含 `org.gradle.wrapper`、`org.gradle.cli` 类及构建元数据；没有将 Gradle 完整发行版的 Groovy、SLF4J、JUnit、JCIFS 等库一起提交。下载的 Gradle 发行版自带自己的完整许可证和声明，不能用本节替代。

## 站点内容与品牌

Chiphell 的商标、名称、站点图片、用户帖子及其他远程内容归各自权利人所有，不由本项目许可证或本项目商业授权授予使用权。本项目是非官方客户端，不代表 Chiphell 或上述第三方为本项目背书。
