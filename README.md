# wechat-connecter-read-only

一个可复用的 **Grok Bot / agent skill**:在 macOS 上**只读、只收**地读取本机微信(4.x)的本地消息数据库(会话、消息、联系人、群、图片),供任意 agent 查询或做下游处理。

Skill 文件:[`skills/wechat-local-db-read/SKILL.md`](skills/wechat-local-db-read/SKILL.md)

## 它是什么
把「用 `wechat-realtime-reader` 只读读取本机微信本地库」这套流程固化成一份通用模板,让任何 agent 处理「读微信本地消息」时都遵循同一套铁律和步骤。它是**通用模板**,不含任何机器的密钥、令牌或写死的绝对路径——这些值由运行时从本地配置文件读取。

## 铁律
- **只读、只收**:绝不提供任何向微信发送消息的通道。
- **不改微信、不关 SIP**:不动官方 App、不改签名。
- **机密只存本地 0600 文件**:密钥、令牌一律不在聊天/日志/接口返回里明文出现。
- **回环调用绕过系统代理**:用 `127.0.0.1`,客户端设 `trust_env=False`。
- **遇到微信安全提示立即停止**;删改前先备份。

## 前置条件
- macOS(Apple Silicon),微信 4.x 已登录并在线。
- 已安装 `wechat-realtime-reader`,并完成过一次性「抓密钥」。
- 读取器进程已获「完全磁盘访问权限」。

## 如何使用
把 `skills/wechat-local-db-read/` 放进你的 skill 库;在对话里用 `/` 或 `@` 选它,或写进 routine 的提示词。详细步骤、命令与排障见 SKILL.md。

## 边界
- 单账号;只读、只收,**没有发送路径**。
- 远程查看不在本 skill 范围。
