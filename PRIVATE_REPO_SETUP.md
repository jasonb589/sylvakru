# 用你自己的私人仓库云端打包 Windows

这份文档记录「不本地打包、改用 GitHub Actions 出 Windows 包」的完整流程。

**路线**:不使用 fork(fork 无法转为 private),改为**新建一个 private 空仓库**,
再把本地代码推上去。上游通过 `upstream` remote 保留,以后仍可手动同步。

下面的命令都需要在**本地装有 git 的环境**执行(当前开发机没有 git)。

---

## 0. 前置信息

| 项 | 值 |
|---|---|
| 上游原仓库 | `https://github.com/AfalpHy/sylvakru.git` |
| 你的 GitHub 账号 | `jasonb589` |
| 你的私人仓库(目标) | `https://github.com/jasonb589/sylvakru.git` |
| Flutter 版本 | `3.47.2`(由 `.fvmrc`、`pubspec.yaml`、workflow 三处共同固定) |
| 工作流文件 | `.github/workflows/build-windows.yml` |

> **为什么不 fork**:GitHub 不允许把 fork 转成 private(fork 与原仓库共享
> commit 网络,设为 private 会绕过原仓库的可见性控制)。所以只能新建空仓库。

---

## 1. 在 GitHub 上新建 private 空仓库

1. 打开 https://github.com/new
2. **Repository name** 填 `sylvakru`
3. 可见性选 **Private**
4. **以下三项全部不要勾**(保持真正的空仓库):
   - `Add a README file`
   - `Add .gitignore`
   - `Choose a license`
5. **Create repository**

> 第 4 步很关键:如果仓库带了初始 commit,`git push` 会因为历史不相关而被拒绝,
> 还得额外处理。空仓库才能直接推。

---

## 2. 改本地 remote

当前 `origin` 指向的是上游 `AfalpHy/sylvakru`,要改名成 `upstream` 保留下来,
再把 `origin` 指向你自己的私人仓库:

```powershell
cd <你的项目目录>

# 把现有 origin(指向上游)改名成 upstream
git remote rename origin upstream

# 新增 origin 指向你自己的私人仓库
git remote add origin https://github.com/jasonb589/sylvakru.git

git remote -v   # 确认:origin = 你的仓库,upstream = AfalpHy
```

预期输出大致为:
```
origin    https://github.com/jasonb589/sylvakru.git (fetch)
origin    https://github.com/jasonb589/sylvakru.git (push)
upstream  https://github.com/AfalpHy/sylvakru.git (fetch)
upstream  https://github.com/AfalpHy/sylvakru.git (push)
```

---

## 3. 首次推送

```powershell
git checkout main
git add lib/ .github/ .gitignore PRIVATE_REPO_SETUP.md
git commit -m "feat: 侧边栏新增「最近添加」入口,并把 Windows 打包交给 CI"
git push -u origin main
```

> **认证**:GitHub 早已不支持账号密码。用 **Personal Access Token** 当密码
> (Settings → Developer settings → Personal access tokens,勾 `repo` 权限),
> 或者装 GitHub Desktop / 配 SSH key。

---

## 4. 启用 Actions

新建的仓库里,`.github/workflows/` 下的工作流**在首次被 push 后才出现**:

1. 进入 `jasonb589/sylvakru` 的 **Actions** 标签页
2. 若看到提示横幅,点 **I understand my workflows, go ahead and enable them**
3. 左侧应出现 **Build Windows**

---

## 5. 触发方式(二选一)

### A. 手动触发(日常验证用)

**Actions → Build Windows → Run workflow → 选分支 → Run workflow**

- 只构建**已经 push 上去**的代码,不会带上未提交的本地改动
- 跑完后在该次运行的 **Artifacts** 区域下载 `sylvakru-windows-x64.zip`

### B. 打 tag 触发(出正式包用)

```powershell
git tag v4.1.0
git push origin v4.1.0
```

- tag 名必须以 `v` 开头才会触发(`push: tags: ['v*']`)
- 构建成功后,zip 会自动附到 **Releases** 页面同名 Release 上
- Release 不存在时会自动创建

---

## 6. 额度与许可证注意事项

**Actions 额度**:免费账号的 **private** 仓库每月 2000 分钟,Windows runner 按 **2 倍**计费。
一次 Windows Flutter 构建约 5–15 分钟 → 实际消耗 10–30 分钟额度。
所以触发条件刻意收窄成「手动 + 打 tag」,避免每次 push 都烧额度。

> 对比:public 仓库的标准 runner **不计入额度**。若哪天不介意公开,
> 把仓库改成 public 反而更省心。

**GPL-3.0**:本项目是 GPL-3.0。private 仓库自用没问题;
但**把打好的包分发给别人**会触发 GPL 的源码提供义务,而 private 仓库对他人不可见。
若要分发,建议把仓库改为 public。

---

## 7. 工作流做了什么

```
Checkout → 装 Flutter 3.47.2 → flutter pub get
        → flutter analyze --no-pub   (失败即中止)
        → flutter build windows --release
        → 压缩成 sylvakru-windows-x64.zip
        → 上传 Artifact
        → [仅 tag 触发] 创建/复用 Release 并附上 zip
```

`Analyze` 步骤**不容错**:静态分析报错会直接终止,不会浪费一次完整构建。
构建失败时,把失败步骤的日志贴出来排查。

---

## 8. 以后同步上游更新

因为没有 fork 关系,GitHub 不会自动帮你追踪上游,但 `upstream` remote 已经配好,
手动同步一样方便:

```powershell
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

有冲突时按需解决。你自己的功能改动建议开在独立分支上提交,减少和上游的冲突面:

```powershell
git checkout -b feat/recently-added
# ... 改代码 ...
git add lib/
git commit -m "feat: 最近添加入口"
git checkout main
git merge feat/recently-added
git push origin main
```

---

## 9. 附:要不要装本地环境？

只出包的话,**不需要**本地 Flutter。但有一类情况值得装**轻量**本地环境:

| 场景 | 建议 |
|---|---|
| 只想拿到 Windows 包 | 纯云端,什么都不用装 |
| 想先筛掉语法/签名错误再去云端 | 只装 **Flutter SDK + Git**(约 3 GB),跑 `flutter analyze` |
| 想真正跑起来调试、热重载 | 需再装 **Visual Studio 2022 + C++ 桌面开发**(约 8–15 GB) |

Windows 完整本地构建的磁盘占用(Flutter + VS + 依赖缓存)约 **20–25 GB**,
下载量 5–10 GB,首次配置约 1 小时。
