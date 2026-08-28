# CodeUsage 发布流程

GitHub Actions 不保存或使用任何 Apple 凭证。PR 和 `main` 分支会运行测试并生成 ad-hoc 签名的 App 与带完整拖拽安装界面的 CI DMG。Release Please 创建 GitHub Release 后，发布工作会自动构建并上传 ad-hoc 签名的 Universal DMG、Universal ZIP 和源码 ZIP。正式 Developer ID 签名和 Apple 公证仍只在发布者自己的 Mac 上进行。

## GitHub 设置

1. 在仓库的 Actions 设置中允许工作流读取仓库，并允许 Release Please 创建 Pull Request。
2. 为 `main` 开启分支保护，要求 `CI / test-and-package` 通过后才能合并。
3. 使用 Conventional Commits 或相同格式的 Squash PR 标题：
   - `fix:` 触发 PATCH 版本。
   - `feat:` 触发 MINOR 版本。
   - `feat!:` 或提交正文中的 `BREAKING CHANGE:` 触发 MAJOR 版本。
4. Release Please 会维护 Release PR、`version.json`、Git Tag 和 GitHub Release；Release 创建成功后，`publish-assets` 作业会自动上传 ad-hoc 签名的发布产物。

## GitHub 自动发布产物

只有当 Release Please 真正创建新的 GitHub Release 时，`publish-assets` 作业才会运行。它会检出 Release Tag，在 `macos-15` arm64 runner 上构建 arm64 与 x86_64 双架构 App，并向对应 Release 上传：

- `CodeUsage-<version>-macos-universal.dmg`
- `CodeUsage-<version>-macos-universal.zip`
- `CodeUsage-<version>-source.zip`

自动 DMG 会通过 Finder 现场生成背景引用、窗口尺寸和图标位置，不使用带旧卷路径的固定 `.DS_Store` 模板。产物只使用 ad-hoc 签名，不包含 Developer ID 凭证或 Apple 公证票据。首次打开时，macOS 可能要求用户通过 Finder 右键“打开”进行确认。

如果 Release 已经存在但产物上传失败，或需要为旧 Release 补齐产物，可在 GitHub 的 **Actions → Release Please → Run workflow** 中输入 `release_tag`（例如 `v0.10.0`）。手动模式不会创建新版本，只会重新构建并覆盖指定 Release 的同名产物。

## 本地 Apple 凭证

不要把证书、私钥、Apple ID、App 专用密码或 App Store Connect API Key 放进仓库。

1. 在“钥匙串访问”中安装包含私钥的 `Developer ID Application` 证书。
2. 把公证凭证保存在本机 Keychain：

   ```bash
   xcrun notarytool store-credentials CodeUsage-notary
   ```

   根据提示输入 Apple ID、Team ID 和 App 专用密码。也可以按照 `notarytool store-credentials --help` 使用 App Store Connect 团队 API Key。

3. 只设置非秘密的标识信息：

   ```bash
   export CODEUSAGE_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
   export CODEUSAGE_BUNDLE_IDENTIFIER='com.example.CodeUsage'
   export CODEUSAGE_NOTARY_PROFILE='CodeUsage-notary'
   export CODEUSAGE_PROVISIONING_PROFILE="$HOME/Downloads/CodeUsage_Developer_ID.provisionprofile"
   ```

## CloudKit 发布前配置

CodeUsage 的正式 Bundle ID 是 `com.van-fe.CodeUsage`，iCloud Container 是 `iCloud.com.van-fe.CodeUsage`。Apple Developer 后台需让该 App ID 启用 iCloud/CloudKit 并关联这个 Container，然后创建与该 App ID 对应的 **Developer ID provisioning profile**。Profile 只保存在发布者本机，不提交到 GitHub。

CloudKit Production 环境需要先存在 `UsageSnapshot` Record Type，字段如下：

| 字段 | CloudKit 类型 |
| --- | --- |
| `provider` | String |
| `schemaVersion` | Int(64) |
| `updatedAt` | Date/Time |
| `payload` | Bytes |

在 CloudKit Console 中确认 Development schema 后，将 schema 部署到 Production。正式发布脚本固定使用 `Config/CodeUsage.entitlements` 中的 Production 环境；如果 Profile 缺少 Bundle ID、CloudKit、iCloud Container 或 Production 环境，脚本会在签名前终止。

GitHub Actions 不持有 provisioning profile，因此 CI 构建仍为 ad-hoc 签名，运行时不会获得 iCloud 权限。这是预期行为；只有本机正式签名并公证的发布包启用 CloudKit。
ad-hoc 构建仍使用正式 Bundle ID `com.van-fe.CodeUsage`，以确保本机偏好设置和后续升级路径一致，但不会附带受限的 iCloud entitlements。

首次配置或更换 Profile 后，可在不构建、不签名、不提交公证的情况下验证环境：

```bash
./Scripts/release_local.sh --validate-config
```

## 正式发布

Release Please 创建版本 Tag 和 GitHub Release 后，如果需要用 Developer ID 签名和 Apple 公证产物取代自动上传的 ad-hoc 产物，在本机检出该 Tag，并确认工作区干净：

```bash
git checkout vX.Y.Z
./Scripts/release_local.sh
```

脚本会校验并嵌入 Developer ID provisioning profile，使用 CloudKit entitlements、Hardened Runtime 和安全时间戳签名，完成 App 与 DMG 公证、Staple 票据并执行 Gatekeeper 校验。默认不会连接或修改 GitHub。

确认产物后，显式上传到已存在的 GitHub Release：

```bash
./Scripts/release_local.sh --upload
```

`--upload` 要求当前 `HEAD` 正好位于对应的 `vX.Y.Z` Tag，并使用本机已登录的 GitHub CLI。它会覆盖 Release 中同名的 Universal ZIP 和 DMG，源码 ZIP 保持不变。Apple 私钥和公证凭证始终留在本机 Keychain。
