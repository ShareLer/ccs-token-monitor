# ccMonitor macOS 发布与 Gatekeeper 检查报告

检查日期：2026-07-11
检查范围：当前 `main`、`release.sh`、`project.yml`、README，以及 GitHub Release `v1.0.5`

## 结论

**当前 GitHub Release 存在与 UniGate 相同的首次安装问题。**

用户通过 Safari、Chrome 等浏览器下载并解压 `ccMonitor-v1.0.5-macOS.zip` 后，macOS 会给下载内容附加 quarantine 属性。当前 `ccMonitor.app` 只有 ad-hoc 签名，没有 Developer ID 身份，也没有 Apple notarization ticket。在正常开启 Gatekeeper 的 Mac 上，用户会看到“Apple 无法验证是否包含恶意软件”一类提示，不能按普通已公证应用的方式直接打开。

执行下面的命令会移除 quarantine，使应用绕过这次 Gatekeeper 下载来源检查：

```bash
xattr -cr "/Applications/ccMonitor.app"
```

这不是 Apple 信任链修复，而是用户在确认下载来源后手动取消 quarantine。本报告按“不使用 Apple 开发者账号”的前提，只给出与 UniGate 一致的社区发布方案。该方案不能消除首次安装命令，但可以让构建、签名、安装说明和后续发布行为稳定且可验证。

## 已确认事实

### 1. 发布脚本没有分发签名和公证

`release.sh` 明确写着：

```text
This script does not Developer ID sign or notarize the app.
```

脚本当前只执行：

1. Xcode Release 构建。
2. 用 `ditto` 打 zip。
3. 生成 SHA-256 文件。
4. 创建 tag 和 GitHub Release。

脚本没有执行以下任何步骤：

- 使用 `Developer ID Application` 证书签名。
- `notarytool submit` 提交 Apple 公证。
- `stapler staple` 附加公证票据。
- `spctl` 或 `syspolicy_check` 分发验收。

### 2. `CODE_SIGN_STYLE=Automatic` 不代表可公开分发

`project.yml` 中配置了：

```yaml
CODE_SIGN_STYLE: Automatic
ENABLE_HARDENED_RUNTIME: YES
```

这两个配置不足以建立公开分发信任：

- Automatic Signing 只表示由 Xcode 自动选择当前机器可用的签名方式。没有 Developer ID 证书时，命令行 Release 构建可以退化为 ad-hoc 签名。
- Hardened Runtime 是 notarization 的前置条件之一，不是开发者身份，也不是公证结果。

因此不能根据 Xcode 显示“签名成功”判断 Gatekeeper 会接受 GitHub 下载的应用。

### 3. `v1.0.5` 实际产物是 ad-hoc 签名

对 GitHub Release 中的 `ccMonitor.app` 执行：

```bash
codesign -dv --verbose=4 ccMonitor.app
```

关键结果：

```text
flags=0x10002(adhoc,runtime)
Signature=adhoc
TeamIdentifier=not set
```

这说明 Hardened Runtime 已开启，但应用没有 Apple 可验证的开发者身份。

### 4. 代码结构校验通过，不等于 Gatekeeper 信任

执行：

```bash
codesign --verify --deep --strict --verbose=4 ccMonitor.app
```

结果为：

```text
valid on disk
satisfies its Designated Requirement
```

这只证明 app bundle 自 ad-hoc 签名后没有被修改，不能证明发布者身份，也不能替代 notarization。

### 5. 产物没有 notarization ticket

执行：

```bash
xcrun stapler validate ccMonitor.app
```

结果为：

```text
ccMonitor.app does not have a ticket stapled to it.
```

退出码为 `65`。

执行：

```bash
syspolicy_check distribution ccMonitor.app
```

结果为失败，退出码为 `70`，包含两个明确诊断：

```text
Adhoc Signed App
This app is adhoc signed. While it may run locally, adhoc signed apps are not suitable for distribution.

Notary Ticket Missing
A Notarization ticket is not stapled to this application.
```

本次检查机器的全局 `spctl` assessment 被关闭，因此没有把本机双击结果作为证据。上述签名身份、stapler 和 `syspolicy_check` 结果已经足以确认公开分发问题。

### 6. Release 包含调试 entitlement

执行：

```bash
codesign -d --entitlements :- ccMonitor.app
```

实际产物包含：

```xml
<key>com.apple.security.get-task-allow</key>
<true/>
```

`get-task-allow=true` 允许调试器附加到应用，不应出现在公开 Release 中。它不是本次 Gatekeeper 拦截的直接原因，但说明当前 Release 签名配置仍带有开发构建属性。修复时应让 Release 构建移除该 entitlement，并在脚本中验证它不存在或为 `false`。

## 为什么本地构建能打开，GitHub 下载却打不开

两者的差异不是应用代码，而是 quarantine：

1. `./build.sh` 在本地生成的 app 通常没有 `com.apple.quarantine`。
2. 浏览器下载的 zip 会带 quarantine，解压后的 app 通常继承该属性。
3. 第一次启动带 quarantine 的 app 时，Gatekeeper 会检查签名身份和 notarization。
4. 当前产物只有 ad-hoc 签名且未公证，因此检查失败。
5. `xattr -cr` 删除扩展属性后，不再触发这次下载来源检查，所以应用能够运行。

因此，“开发机器上 `open ./build/.../ccMonitor.app` 正常”不能作为 Release 可安装性的验收标准。

## 统一解决方案：无 Apple 开发者账号的社区分发

本方案与 UniGate 保持一致，项目只维护 ad-hoc 签名这一条发布路径。必须接受一个事实：**无法让带 quarantine 的公开下载产物自动通过 Gatekeeper。**

可做的是把当前行为变成明确、可验证、对用户透明的发布流程，而不是声称已经解决免授权安装。

### 发布脚本应做的调整

1. 明确执行 ad-hoc 签名，不依赖 Automatic Signing 在不同机器上的隐式结果。
2. 执行严格代码结构校验，并确认结果确实为 ad-hoc，避免发布机器环境变化导致产物不可预测。
3. 对 zip 执行 `unzip -tq`。
4. 生成只包含文件名的可移植 SHA-256 文件。
5. 从最终 zip 解压 app，再次校验签名，确保上传字节就是本地验证字节。
6. 将构建产物绑定到当前 commit；只有本地安装验证完成后才允许创建 tag 和 Release。
7. README 固定写明首次安装步骤，Release Notes 只记录版本改动。

建议的 ad-hoc 验收：

```bash
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
grep -q 'Signature=adhoc' <<<"$SIGNATURE_DETAILS"
grep -q 'TeamIdentifier=not set' <<<"$SIGNATURE_DETAILS"

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_PATH" 2>&1)"
! grep -q '<key>com.apple.security.get-task-allow</key>.*<true/>' \
  <<<"$(tr -d '\n' <<<"$ENTITLEMENTS")"
```

可移植校验文件应这样生成：

```bash
ZIP_NAME="$(basename "$ZIP_PATH")"
(
  cd "$DIST_DIR"
  shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"
)
```

当前 `v1.0.5` 的校验文件记录的是：

```text
<hash>  ./dist/ccMonitor-v1.0.5-macOS.zip
```

用户把 zip 和 `.sha256` 下载到同一目录后直接运行 `shasum -a 256 -c ...` 会因为本地没有 `./dist/` 子目录而失败。校验文件应只记录 `ccMonitor-v1.0.5-macOS.zip`。

### README 应写明的首次安装步骤

```markdown
## 第一次安装

1. 从项目 GitHub Releases 下载 `ccMonitor-*-macOS.zip`。
2. 解压 zip。
3. 将 `ccMonitor.app` 移动到“应用程序”。
4. 只在确认文件来自本项目 Release 后，打开终端执行：

   ```bash
   xattr -cr "/Applications/ccMonitor.app"
   ```

5. 从“应用程序”打开 `ccMonitor.app`。
```

文档必须提醒用户只对确认来自本项目 GitHub Release 的应用执行该命令。SHA-256 能检查下载内容是否与 Release 资产一致，但不能证明 Apple 开发者身份。

## 现有发布脚本的其他风险

这些问题不会直接导致 Gatekeeper 拦截，但建议在重写发布流程时一起修复。

### 1. 只拒绝已跟踪改动，可能发布不可追溯代码

当前检查使用：

```bash
git status --porcelain --untracked-files=no
```

项目会在发布前运行 `xcodegen generate`。如果新增 Swift 文件尚未加入 Git，XcodeGen 仍可能把它编入产物，但 tag 不包含该文件，导致 Release 无法从 tag 复现。

应改为拒绝所有未提交内容：

```bash
[[ -z "$(git status --porcelain)" ]] || die "worktree must be clean"
```

### 2. 没有校验 tag 与应用版本一致

脚本接受参数 `v1.2.3`，但没有检查 app 的 `CFBundleShortVersionString` 和 `CFBundleVersion`。可能发布 tag 为新版本、bundle 内仍显示旧版本的包。

构建后至少检查：

```bash
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$APP_PATH/Contents/Info.plist")"

[[ "v$BUNDLE_VERSION" == "$TAG" ]] \
  || die "bundle version does not match tag"
```

### 3. tag 创建和推送发生在产物完整验收之前

当前脚本构建和压缩后直接创建、推送 tag，再创建 Release。它没有安装验证、签名策略验证或分发验收。后续任何检查失败都会留下没有可用 Release 的远程 tag。

建议采用两阶段流程：

```text
build
  -> 构建、签名、压缩、哈希、解压复验、本地安装验证
  -> 写入包含 commit 和产物哈希的 manifest

publish
  -> 确认工作区干净、HEAD 已推送、manifest commit/hash 未变化
  -> 确认 tag/Release 不存在
  -> 创建 tag 和 Release
```

### 4. 没有验证上传产物

创建 Release 后，脚本没有确认 zip 和 SHA-256 是否实际上传，也没有把 GitHub 返回的 asset digest 与本地哈希比较。应在上传完成后读取 Release asset 列表和 digest 做最终核对。

## 实施原则

代码和文档中只保留这一套 ad-hoc 社区发布流程，不增加 Developer ID、notarization 或签名身份自动探测分支。发布脚本必须显式控制签名方式，README 必须明确首次安装需要执行 `xattr -cr`，Release Notes 只记录版本更新。这样可以避免不同发布机器根据本地证书状态产生不同产物。

## 修复完成后的验收清单

- [ ] 工作区干净，HEAD 已推送。
- [ ] tag 与 bundle 版本一致。
- [ ] 脚本明确执行并验证 ad-hoc 签名。
- [ ] Release entitlements 不包含 `get-task-allow=true`。
- [ ] zip 完整性和解压后 app 签名均通过。
- [ ] SHA-256 文件只包含 zip 文件名，可直接使用 `shasum -a 256 -c`。
- [ ] README 包含下载、解压、移动到应用程序、移除 quarantine、打开应用的完整步骤。
- [ ] Release Notes 只写版本更新，不重复长期安装说明。
- [ ] 在一台 Gatekeeper 正常开启的干净 Mac 上验证：未授权时被阻止，执行文档命令后能正常打开。

## 参考

- `man codesign`
- `man xattr`
