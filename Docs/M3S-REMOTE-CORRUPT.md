# M3s 验收记录：WebDAV/SMB 损坏文件过滤

日期：2026-11-20。分支：`m3s-remote-corrupt`。基线：Infuse 8.5.10（参照客户端待装）。

M3n 只过滤本地损坏文件。本轮为 WebDAV/SMB 增加容器签名校验：MKV/WebM 必须 EBML，MP4/MOV 必须 ftyp/moov/mdat，AVI RIFF，TS 同步字节；扩展名未知或读取失败保留（未知不等于损坏）。

## 交付内容

- `MediaSignature`：64B 头部签名判定。
- WebDAV 扫描 Range 0..64；SMB 扫描 read min(64,size)。
- `SMBClient.read` 失败重连重试一次；解决 NFO/海报读取后 context shutdown 导致签名读失败。
- 单测 MediaSignatureTests；验收 `Scripts/run-remote-corrupt-filter.sh`。

## 实测结果

| 检查 | 结果 |
| --- | --- |
| WebDAV | 只保留 Good Movie，Broken 不入库 |
| SMB | 只保留 Good Movie，Broken 不入库 |
| 单测 | MediaSignatureTests 通过，总 **36/36** |
| 脚本 | `Scripts/run-remote-corrupt-filter.sh` PASS |
| 五端/device/Mac | 全部 **BUILD SUCCEEDED** |
| 真实服务器 | 待验证 |

证据：`reports/m3s-webdav-corrupt.json`、`reports/m3s-smb-corrupt.json`、`reports/m3s-remote-corrupt.txt`。

## 可复现差异与未验证

1. **魔数正确但内容截断/损坏**仍可能入库。
2. **读取失败按未知保留**；网络故障不会误删。
3. **真实 SMB3/OpenList**未测。
4. **音频听测、HDR 测量、真实 Trakt/CloudKit、visionOS 真机**未完成。

## 下一项

M5ai/M6d：碎片 MP4/SMB 性能；真机 visionOS；音频听测；HDR 测量；真实 SMB3/Trakt；CloudKit；真实 OpenList。
