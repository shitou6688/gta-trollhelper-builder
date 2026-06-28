# GTA TrollHelper Builder

使用 GTA Car Tracker 作为 Victim App，编译 TrollHelper OTA 安装包。

## 原理

- **Victim App**: GTA Car Tracker (`com.icraze.gtatracker`)
- **Team ID**: `T8ALTGMVXN`
- iOS 14.0-15.4.1 (arm64) + 14.0-15.6.1 (arm64e) 设备可以免信任 OTA 安装

## 构建流程

1. 从 Runner.app 打包为 InstallerVictim.ipa
2. 用 `generate_victim_cert.sh T8ALTGMVXN` 生成 GTA 专用签名证书
3. `pwnify pwn` 注入持久化助手（arm64）+ `victim_gta.p12` 签名
4. `pwnify pwn64e` 注入持久化助手（arm64e）
5. 输出 TrollHelper_iOS15.ipa + TrollHelper_arm64e.ipa

## 目录结构

```
├── .github/workflows/build.yml   # GitHub Actions 构建流程
├── Runner/Runner.app/            # GTA Car Tracker 完整 App
├── helpers/                      # 持久化助手二进制
│   ├── PersistenceHelper_Embedded_Legacy_arm64
│   └── PersistenceHelper_Embedded_Legacy_arm64e
├── scripts/
│   ├── pwnify.py                 # Pwnify 工具
│   └── generate_victim_cert.sh   # 证书生成脚本
└── Victim/                       # (构建时自动生成)
    └── InstallerVictim.ipa
```

## 注意事项

- Runner.app 不提交到 Git（太大，在 .gitignore 中）
- 需要手动将 Runner.app 放入 Runner/ 目录
- victim_gta.p12 由 workflow 自动生成，不提交
