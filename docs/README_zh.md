# Me2Comic

[![build](https://github.com/DawnLiExplorer/Me2Comic/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DawnLiExplorer/Me2Comic/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://opensource.org/licenses/MIT)

[English](../README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

Me2Comic 是一款 macOS 图形界面工具，调用 GraphicsMagick 批量转换与裁剪图片，力求在减小文件体积的同时保留较高画质。最初是我用来处理漫画图片、学习 Swift 时的周末小项目，现在以 MIT 协议开源发布，欢迎试用、修改，或者随便看看～🍻

<img src="screenshot.png" alt="Me2Comic Screenshot" width="500">


## 主要功能

• 批量转换JPG/JPEG/PNG图片到JPG  
• 各项参数调节  
• 多线程  
• 自动裁切超设定阀值图片，均分为两个单页  
• 日志信息  

## 本地化

• 简体中文 | 繁體中文 | English | 日本語  

## 系统要求

macOs • 13.0+

## 安装依赖：

```shell
brew install graphicsmagick
```
## 目录结构示意图
### - 输入目录结构示意：

<pre>
/Volumes/漫画目录/待处理漫画目录/
├── CITY HUNTER Vol.xx
├── One Piece Vol.xx
└── 漫画3
</pre>

### - 完成后结构：

<pre>
/Volumes/漫画目录/搞完目录/
├── CITY HUNTER Vol.xx
│   ├── CITY.HUNTER.CE.1-1.jpg / CITY.HUNTER.CE.1-2.jpg (大于指定参数分切，右侧命名靠前)
│   └── CITY.HUNTER.CE.2...
├── One Piece Vol.xx
│   ├── One Piece Vol.1.jpg (小于指定参数不分切)
│   └── One Piece Vol.2...
└── 漫画3
</pre>

## 构建与发布:

集齐七颗龙珠 ➔ [Actions](../../../actions) ➔ `🐉 SHENRON! Grant my release wish! ✨` ➔ 喊出咒语 `Run workflow`  
<sub>*（注：等待时间取决于神龙当天心情 🐉✨）*</sub>

### <sub>※ *附注* </sub> 
<sub>※ *应用图标改编自穆夏《黄道十二宫》，版本代号致敬其艺术遗产，与官方项目无任何关联。* </sub>