# Me2Comic

[![build](https://github.com/DawnLiExplorer/Me2Comic/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DawnLiExplorer/Me2Comic/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://opensource.org/licenses/MIT)

[English](../README.md) | [中文](README_zh.md) | [日本語](README_ja.md)

Me2Comic は macOS 向けの GUI ツールで、GraphicsMagick を外部コマンドとして呼び出し、画像の一括変換とトリミングを行います。画質を保ちつつファイルサイズを抑えることを重視しています。もともとは Swift の学習と漫画画像の整理を目的とした週末のサイドプロジェクトでしたが、MIT ライセンスのもとでオープンソースとして公開しました。気軽に試したり、カスタマイズして使っていただければ嬉しいです。🍻

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

## ビルド＆リリース:

七つのドラゴンボールを揃えよ ➔ [Actions](../../../actions) ➔ `🐉 SHENRON! 我が願いを叶えよ! ✨` ➔ 神龍召喚 `Run workflow`  
<sub>*(注: 待機時間は神龍の気分次第 🌪️✨)*</sub>

### <sub>※ *備考* </sub> 
<sub>※ *アプリアイコンはミュシャ作《黄道十二宮》を基にしたAI改作、ビルド名は氏へのオマージュ。非公式利用に限ります。* </sub>