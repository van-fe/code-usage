# CodeUsage 发布流程

GitHub Actions 不保存或使用任何 Apple 凭证。PR 和 `main` 分支只运行测试、生成 ad-hoc 签名的 App，以及无 Finder 依赖的 CI DMG。正式 Developer ID 签名和 Apple 公证只在发布者自己的 Mac 上进行。

## GitHub 设置

1. 在仓库的 Actions 设置中允许工作流读取仓库，并允许 Release Please 创建 Pull Request。
2. 为 `main` 开启分支保护，要求 `CI / test-and-package` 通过后才能合并。
3. 使用 Conventional Commits 或相同格式的 Squash PR 标题：
   - `fix:` 触发 PATCH 版本。
   - `feat:` 触发 MINOR 版本。
   - `feat!:` 或提交正文中的 `BREAKING CHANGE:` 触发 MAJOR 版本。
4. Release Please 会维护 Release PR、`version.json`、Git Tag 和 GitHub Release。GitHub Release 创建后，再从本地生成正式签名产物并上传。

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
   ```

## 正式发布

Release Please 创建版本 Tag 和 GitHub Release 后，在本机检出该 Tag，并确认工作区干净：

```bash
git checkout vX.Y.Z
./Scripts/release_local.sh
```

脚本会构建 Universal App、使用 Hardened Runtime 和安全时间戳签名、完成 App 与 DMG 公证、Staple 票据并执行 Gatekeeper 校验。默认不会连接或修改 GitHub。

确认产物后，显式上传到已存在的 GitHub Release：

```bash
./Scripts/release_local.sh --upload
```

`--upload` 要求当前 `HEAD` 正好位于对应的 `vX.Y.Z` Tag，并使用本机已登录的 GitHub CLI。Apple 私钥和公证凭证始终留在本机 Keychain。
