---
title: 参与 FluxDown 翻译
description: 帮助把应用、Web 界面和官网翻译成你的语言——无需写代码。
section: contributing
order: 2
sourceHash: "28ee64e1c2c7"
---

FluxDown 的多语言由社区在自托管的 [Weblate](https://translate.zerx.dev/projects/fluxdown/) 翻译站上共建。一切都在浏览器里完成——**不需要 Git、不需要写代码、不需要搭建环境**。

## 可以翻译什么

![Weblate 上的 FluxDown 项目](/docs/weblate/project.png)

| 部件 | 覆盖范围 |
| --- | --- |
| **Desktop & Mobile App** | Windows/macOS/Linux 桌面端与移动端应用内的全部字符串 |
| **Web App** | headless 服务器托管的 Web 管理界面 |
| **Website** | fluxdown.zerx.dev 官网——首页、FAQ、更新日志 |

英文是源语言，简体中文由核心团队维护，其余语言等你来开创。

## 快速开始

1. 在翻译站[注册账号](https://translate.zerx.dev/accounts/register/)（邮箱或 GitHub 登录）。
2. 打开 [FluxDown 项目](https://translate.zerx.dev/projects/fluxdown/)，选择一个部件和语言。
3. 逐条翻译——编辑器会显示英文原文、相邻字符串和术语表：

![Weblate 翻译编辑器](/docs/weblate/editor.png)

点击**保存并继续**逐条推进。对某条没把握？改点**建议**——之后其他译者可以复核。

## 占位符

花括号内容如 `{name}`、`{count}`、`{speed}` 会在运行时被实际值替换。**占位符必须原样保留**——可以按你语言的语序自由调整位置，但不要翻译或删除花括号里的内容。占位符缺失时 Weblate 会自动警告。

## 开创新语言

列表里还没有你的语言？打开任意部件，点击**开始新翻译**：

![开始新翻译](/docs/weblate/new-language.png)

Weblate 会自动创建翻译文件，并在你开始翻译后向 FluxDown 仓库发起 Pull Request。合并之后：

- **应用**：下个版本里你的语言自动出现在「设置 → 语言」——应用在运行时自动发现翻译文件。
- **Web 界面与官网**：下次部署后语言切换器中自动出现。

全程无需任何代码改动。语言选择器用 `languageNativeName` 这条字符串给自己命名，所以请最先翻译它。

## 小贴士

- **翻译一部分也有价值。**未翻译的字符串逐键回退英文——完成 30% 的语言已经可用。
- **一致性优先于直译。**多看术语表和相邻字符串，同一概念用同一译名。
- **首次贡献时需要签署 CLA**——在 Weblate 内一次性点击即可。
- 发现英文原文有笔误？请通过[反馈表单](/feedback)或 issue 报告——源字符串在仓库中管理。
