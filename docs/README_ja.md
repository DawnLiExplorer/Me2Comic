# Me2Comic

[![CI Status](https://github.com/DawnLiExplorer/Me2Comic/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DawnLiExplorer/Me2Comic/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://opensource.org/licenses/MIT)

[English](../README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

Me2Comicは、GraphicsMagickを使用して画像を一括変換・トリミングするmacOSのGUIツールです。画質を優先しつつ、ファイルサイズを小さくします。私は漫画好きで、主に漫画画像を処理するために使っています。また、この機会にSwiftUIを学び、より多くの経験を積んでいます。

<img src="screenshot.png" alt="Me2Comic スクリーンショット" width="500">

## 特徴

• JPG/JPEG/PNG → JPG のバッチ変換  
• 超大画像の自動分割（右側優先）  
• パラメータ制御  
• マルチスレッド処理  
• タスクログ  

## 対応言語

• 簡体字中国語 | 繁体字中国語 | English | 日本語 

## 動作環境

- macOS 13.0 以降
- GraphicsMagick のインストールが必要:

```shell
  brew install graphicsmagick
```

## ディレクトリ構造例
### - 入力ディレクトリ構造
<pre>
/Volumes/漫画フォルダ/未整理/
├── CITY HUNTER Vol.xx
├── One Piece Vol.xx
└── Comic 3
</pre>

### 処理完了後の構造
<pre>
/Volumes/漫画フォルダ/完了/
├── CITY HUNTER Vol.xx
│   ├── CITY.HUNTER.CE.1-1.jpg / CITY.HUNTER.CE.1-2.jpg（サイズ超過時分割・右側優先）
│   └── CITY.HUNTER.CE.2...
├── One Piece Vol.xx
│   ├── One Piece Vol.1.jpg（指定パラメータ未満の場合は分割なし）
│   └── One Piece Vol.2...
└── Comic 3
</pre>

### <sub>※ *備考* </sub> 
<sub>※ *アプリアイコンはミュシャ作《黄道十二宮》を基にしたAI改作、ビルド名は氏へのオマージュ。非公式利用に限ります。* </sub>