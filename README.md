# wechat-realtime-reader

本机 **只读、只收** 的微信 4.x 消息读取运行套件,并附带一份可复用的 agent skill。克隆到你的 Mac 后,按快速开始即可把本机微信本地库以只读方式解密,并在 `127.0.0.1:5678` 提供带令牌鉴权的页面、HTTP API 和 MCP。

> **只收,不发。** 全程只读本机微信数据库,没有任何向微信发送消息的通道。不修改官方微信、不关闭 SIP。

本套件的读取器源码与预编译二进制基于开源项目 [missuo/wechat-realtime-reader](https://github.com/missuo/wechat-realtime-reader),位于 `reader/`。

## 快速开始

环境:macOS(Apple Silicon),微信 4.x 已登录并保持在线。无需先装 Go(仓库已附带预编译二进制)。

```bash
git clone https://github.com/lamp-cat/wechat-realtime-reader.git
cd wechat-realtime-reader
./scripts/setup.sh
```

`setup.sh` 会:检查环境、确保二进制可执行、在 `~/.config/wechat-realtime-reader/` 生成数据源配置(已有则保留;若本机只有一个微信账号目录会自动填入)、渲染 launchd 配置。可重复执行。

然后完成一次性手工步骤:

1. **确认数据源**:打开 `~/.config/wechat-realtime-reader/source-config.json`,把 `<WXID>` 改成你的微信 id(账号目录一般在 `~/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/`)。若安装时已自动填入,核对即可。
2. **抓密钥**(首次,或微信大版本更新导致无法解密时):登录并保持微信在线,运行 `./scripts/recapture-keys.sh`。脚本会对微信做一份**签名的临时副本**,用 Frida hook CommonCrypto PBKDF,把各库密钥写入 `~/.config/wechat-realtime-reader/keys.json`(权限 0600)。**不改官方微信、不关 SIP,也不会在终端打印密钥。** 出现微信安全提示时立即停止,不要反复重试。
3. **完全磁盘访问权限**:系统设置 → 隐私与安全性 → 完全磁盘访问权限,加入 `reader/bin/wechat-reader`(或你实际运行的那个二进制),否则读不到本地库。
4. **启动服务**:
   - 前台:`./scripts/serve.sh`(默认 `127.0.0.1:5678`)
   - 或再次运行 `./scripts/setup.sh`,在已有密钥的情况下会通过 launchd 保活

启动后终端会打印带令牌的本机地址,用浏览器打开即可。令牌也可用 `reader/bin/wechat-reader token` 查看,保存在数据目录的 `state/web-token`(0600)。**令牌 = 完整读权限,请当机密对待,不要分享、不要提交到 Git。**

## 常用命令

```bash
reader/bin/wechat-reader doctor   # 自检密钥/库(不打印密钥)
reader/bin/wechat-reader sync     # 增量解密、同步快照
reader/bin/wechat-reader serve    # 只读页面 + API + MCP(127.0.0.1:5678,令牌鉴权)
reader/bin/wechat-reader status   # 各库新鲜度
reader/bin/wechat-reader token    # 查看访问令牌(请当机密)
```

从源码编译(可选,需 Go 1.25+):

```bash
cd reader && go build -o bin/wechat-reader ./cmd/wechat-reader
```

## 目录说明

- `reader/` — 读取器:Go 源码、预编译二进制 `bin/wechat-reader`(Apple Silicon)、上游说明与抓密钥配套文件
- `config/source-config.json.template` — 数据源配置模板(只有占位符,不含真实值)
- `scripts/setup.sh` — 一键安装可自动化的部分(幂等)
- `scripts/recapture-keys.sh` — 一次性抓取本机微信数据库密钥
- `scripts/serve.sh` — 启动只读服务
- `launchd/com.lampcat.wechatreader.plist.template` — launchd 保活模板,由 `setup.sh` 渲染安装
- `skills/wechat-local-db-read/` — 给其他 agent 用的「只读读取本机微信消息库」skill

本机运行时的配置与机密在仓库之外:

```text
~/.config/wechat-realtime-reader/
├── source-config.json   # 数据源映射,0600
├── keys.json            # 各库解密密钥,0600
├── image-key.json       # 图片 .dat 密钥(首次运行时自动推导),0600
└── serve.log            # launchd 日志(可能含令牌,0600)
~/.local/share/wechat-realtime-reader/   # 明文快照与 state/web-token,目录 0700
```

这些文件不要拷进仓库,也不要发到聊天里。

## 安全与边界

- **只读、只收**:没有任何向微信发送消息的通道。
- **不改微信、不关 SIP**:不修改官方 App、不改其签名;抓密钥只在临时副本上进行。
- **密钥与令牌只存本地 0600 文件**,不要在日志、接口或聊天里明文写出。
- 服务只绑定回环地址 `127.0.0.1`。访问时请用 `127.0.0.1`,HTTP 客户端设 `trust_env=False`,避免走到系统代理。
- 单账号;远程查看不在本项目范围。
- `wxgf` 原图需要本机有 `ffmpeg`(`brew install ffmpeg`),否则回退缩略图。
- 遇到任何微信安全提示、登录受限或异常崩溃,立刻停止当前操作。删改前先备份。

## Skill

把 `skills/wechat-local-db-read/` 放进你的 skill 库,即可让其他 agent 按同一套铁律查询本机微信消息。步骤与排障见该目录下的 `SKILL.md`。

## 许可

本仓库中由 lamp-cat 编写的 skill、脚本、模板与说明以 MIT 许可发布(见 `LICENSE`)。`reader/` 目录中的读取器源码来自 [missuo/wechat-realtime-reader](https://github.com/missuo/wechat-realtime-reader),按原样收录,版权归原作者。
