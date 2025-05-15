# Me2Comic

[![CI Status](https://github.com/DawnLiExplorer/Me2Comic/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DawnLiExplorer/Me2Comic/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://opensource.org/licenses/MIT)

[English](README.md) | [中文](docs/README_zh.md) | [日本語](docs/README_ja.md)

Me2Comic is a macOS GUI tool that calls GraphicsMagick externally to batch convert and crop images, prioritizing quality while reducing file size. As a comic enthusiast, I mainly use it for processing comic images and gaining more Swift experience.

<img src="docs/screenshot.png" alt="Me2Comic Screenshot" width="500">

## Features

• Batch convert JPG/JPEG/PNG → JPG  
• Auto-split oversize images (right priority)   
• Parameter controls  
• Multi-threading  
• Task logs  

## Localization

• 简体中文 | 繁體中文 | English | 日本語 

## Requirements

- macOS 13.0+
- GraphicsMagick:

```shell
  brew install graphicsmagick
```

## Directory Structure Diagram
### Input Directory Structure

<pre>
/Volumes/Comics/ToProcess/
├── CITY HUNTER Vol.xx
├── One Piece Vol.xx
└── Comic 3
</pre>

### Structure After Completion

<pre>
Volumes/Comics/Done/
├── CITY HUNTER Vol.xx
│   ├── CITY.HUNTER.CE.1-1.jpg / CITY.HUNTER.CE.1-2.jpg (Split if oversized, right side first)
│   └── CITY.HUNTER.CE.2...
├── One Piece Vol.xx
│   ├── One Piece Vol.1.jpg (Not split if smaller than specified parameter)
│   └── One Piece Vol.2...
└── Comic 3
</pre>


### <sub>※ *Note* </sub> 
<sub>※ *App icon adapted from Mucha's Zodiac, build names honor his legacy. No official affiliation.* </sub>

