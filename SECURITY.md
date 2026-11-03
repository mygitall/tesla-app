# 安全说明

## 车钥匙私钥（phone-key.pem）

- 位置：`teslaapp/phone-key.pem`，随 IPA 一起打包
- 用途：BLE 手机钥匙签名（解锁、启动、上锁）
- 风险：**任何拿到 IPA 的人都能用这把钥匙控制本车**

### 当前结论（2026-11-03）

> 业主确认：**IPA 从未外传**（没发给他人、没传网盘/微信）。
> 因此保持现状，不重新配对。

### 如果将来 IPA 外传了

必须重新生成密钥并到车旁重新配对，旧钥匙需从车端白名单移除：

```bash
cd ~/Desktop/AI开发/app/iosapp/tesla
tesla-keygen -key-file teslaapp/phone-key.pem -output teslaapp/phone-key.pub create
# 然后到车旁执行 add-key 配对（见 README）
```

## 其余安全措施

| 项 | 状态 |
|---|---|
| 访问密钥存储 | Keychain（非 UserDefaults）|
| 离线缓存加密 | `.completeFileProtection`（锁屏不可读）|
| 退出/清数据 | 清 Keychain、cookie、缓存、崩溃日志 |
| 定位权限 | 已移除（删掉 AutoEntry 死代码）|
