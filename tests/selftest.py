#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""跨平台自检：只使用临时目录，绝不触碰真实 Antigravity 安装。

    python tests/selftest.py

覆盖：源码可编译、词典完整性、引擎模板、注入产物、asar 打包/解包往返、
install.py --info 的跨平台状态输出、PowerShell 编码、发布文件与隐私检查。
"""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import asar    # noqa: E402
import install  # noqa: E402

RESULTS = []


def case(name, fn):
    try:
        detail = fn()
        RESULTS.append((True, name, detail or ""))
    except Exception as e:
        RESULTS.append((False, name, "%s: %s" % (type(e).__name__, e)))


def require(cond, msg):
    if not cond:
        raise AssertionError(msg)


def read(path, binary=False):
    mode = "rb" if binary else "r"
    kw = {} if binary else {"encoding": "utf-8"}
    with open(path, mode, **kw) as f:
        return f.read()


def test_sources_compile():
    for name in ("install.py", "asar.py"):
        compile(read(os.path.join(ROOT, name)), name, "exec")
    return "install.py / asar.py 语法通过"


def test_dictionary():
    p = os.path.join(ROOT, "dicts", "zh_cn.json")
    raw = read(p)
    pairs = json.loads(raw, object_pairs_hook=lambda kv: kv)
    keys = [k for k, _ in pairs]
    require(len(set(keys)) == len(keys), "词典存在重复 key")
    d = dict(pairs)
    require(len(d) >= 5000, "词条数不足 5000：%d" % len(d))
    for k, v in d.items():
        require(not k.startswith("__"), "非法 key: %r" % k)
        require(isinstance(k, str) and k.strip(), "空 key")
        require(isinstance(v, str) and v.strip(), "空译文: %r" % k)
    return "%d 条词条，键唯一且均有译文" % len(d)


def test_engine_template():
    s = read(os.path.join(ROOT, "dicts", "engine.js"))
    require(s.count("__DICT_ITEMS__") == 1, "占位符数量必须为 1")
    require("(function() {" in s, "缺少引擎 IIFE")
    require("MutationObserver" in s, "缺少 DOM 监听")
    require("Welcome back|Good to see you" in s, "缺少欢迎页动态规则")
    require("__DICT_ITEMS__" in s, "缺少词典注入点")
    return "引擎模板结构完整"


def test_build_injection():
    d = install.load_dictionary()
    inj = install.build_injection(d)
    require("__DICT_ITEMS__" not in inj, "占位符未被替换")
    require(install.TAG in inj, "缺少版本标记")
    require(len(inj) > 100000, "注入产物异常偏小")
    require("欢迎回来" in inj or "允许" in inj, "译文未写入引擎")
    return "注入产物 %d 字节，含 %d 条词条" % (len(inj.encode("utf-8")), len(d))


def _make_sample_asar(dest):
    with tempfile.TemporaryDirectory(prefix="agy_selftest_") as td:
        os.makedirs(os.path.join(td, "dist"))
        os.makedirs(os.path.join(td, "node_modules", "chrome-devtools-mcp", "build"))
        with open(os.path.join(td, "package.json"), "w", encoding="utf-8") as f:
            json.dump({"name": "antigravity", "version": "9.9.9"}, f)
        with open(os.path.join(td, "dist", "preload.js"), "w", encoding="utf-8") as f:
            f.write('"use strict";\nconsole.log("hello");\n')
        with open(os.path.join(td, "dist", "中文.txt"), "w", encoding="utf-8") as f:
            f.write("简体中文内容 ★✓")
        with open(os.path.join(td, "node_modules", "chrome-devtools-mcp", "build", "bin.bin"), "wb") as f:
            f.write(bytes(range(256)))
        asar.pack(td, dest, ["**/node_modules/chrome-devtools-mcp/**"])


def _walk_files(base):
    out = {}
    for root, _dirs, files in os.walk(base):
        for name in files:
            p = os.path.join(root, name)
            with open(p, "rb") as f:
                out[os.path.relpath(p, base).replace(os.sep, "/")] = f.read()
    return out


def test_asar_roundtrip():
    with tempfile.TemporaryDirectory(prefix="agy_selftest_") as td:
        packed = os.path.join(td, "sample.asar")
        _make_sample_asar(packed)
        names = [n for n, _, _ in asar.list_files(packed)]
        require("dist/preload.js" in names, "解包后缺少 dist/preload.js")
        require(any(n.endswith("bin.bin") for n in names), "unpacked 文件丢失")
        out = os.path.join(td, "out")
        asar.extract(packed, out)
        with tempfile.TemporaryDirectory(prefix="agy_selftest_") as src:
            os.makedirs(os.path.join(src, "dist"))
            os.makedirs(os.path.join(src, "node_modules", "chrome-devtools-mcp", "build"))
            with open(os.path.join(src, "package.json"), "w", encoding="utf-8") as f:
                json.dump({"name": "antigravity", "version": "9.9.9"}, f)
            with open(os.path.join(src, "dist", "preload.js"), "w", encoding="utf-8") as f:
                f.write('"use strict";\nconsole.log("hello");\n')
            with open(os.path.join(src, "dist", "中文.txt"), "w", encoding="utf-8") as f:
                f.write("简体中文内容 ★✓")
            with open(os.path.join(src, "node_modules", "chrome-devtools-mcp", "build", "bin.bin"), "wb") as f:
                f.write(bytes(range(256)))
            a, b = _walk_files(src), _walk_files(out)
            require(a == b, "往返后内容不一致: %r vs %r" % (sorted(a), sorted(b)))
    return "打包 → 解包往返一致（含中文文件名、二进制、unpacked）"


def test_install_info():
    with tempfile.TemporaryDirectory(prefix="agy_selftest_") as td:
        if sys.platform == "darwin":
            app = os.path.join(td, "Antigravity.app")
            res = os.path.join(app, "Contents", "Resources")
        else:
            app = os.path.join(td, "Antigravity")
            res = os.path.join(app, "resources")
        os.makedirs(res)
        sample = os.path.join(res, "app.asar")
        _make_sample_asar(sample)
        env = dict(os.environ)
        env["AGZH_ASAR"] = sample
        env.pop("AGZH_FULL_BAK", None)
        r = subprocess.run(
            [sys.executable, os.path.join(ROOT, "install.py"), "--info"],
            capture_output=True, text=True, env=env, cwd=ROOT, timeout=120)
        require(r.returncode == 0, "--info 退出码 %d: %s" % (r.returncode, r.stderr))
        info = json.loads(r.stdout)
        require(info["exists"] is True, "exists 应为 True")
        require(info["version"] == "9.9.9", "版本读取错误: %r" % info.get("version"))
        require(info["localized"] is False, "未注入的样本不应标记为已汉化")
        require(info["app_root"] == app, "app_root 推导错误: %r" % info.get("app_root"))
        require(info["dictionary_entries"] >= 5000, "词典未加载")
    return "--info 在自定义路径下输出正确 JSON"


def test_windows_simulation():
    """在非 Windows 主机上模拟 win32，验证路径探测与注册表分支的安全降级。"""
    orig_platform = install.sys.platform
    keys = ("LOCALAPPDATA", "APPDATA", "PROGRAMFILES", "PROGRAMFILES(X86)", "AGZH_ASAR")
    saved = {k: os.environ.get(k) for k in keys}
    try:
        install.sys.platform = "win32"
        with tempfile.TemporaryDirectory(prefix="agy_selftest_") as td:
            os.environ["LOCALAPPDATA"] = td
            for k in keys[1:]:
                os.environ.pop(k, None)
            res = os.path.join(td, "Programs", "Antigravity", "resources")
            os.makedirs(res)
            target = os.path.join(res, "app.asar")
            with open(target, "wb") as f:
                f.write(b"x")
            p, r = install.detect_paths()
            require(os.path.abspath(p) == os.path.abspath(target),
                    "Windows 路径探测错误: %r" % p)
            require(r == res, "resources_dir 推导错误: %r" % r)
            require(install.app_root(r) == os.path.join(td, "Programs", "Antigravity"),
                    "Windows app_root 推导错误")
            roots = install._win_install_roots()
            require(any("Antigravity" in x for x in roots), "候选路径生成失败")
            # 非 Windows 上 winreg 不可用，进程检测应安全返回而不是抛异常
            require(install.check_app_running() is False, "Windows 进程检测应安全降级")
    finally:
        install.sys.platform = orig_platform
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    return "Windows 路径探测 / app_root / 注册表降级模拟通过"


def test_launchers():
    ps = os.path.join(ROOT, "ag-zh.ps1")
    with open(ps, "rb") as f:
        require(f.read(3) == b"\xef\xbb\xbf", "ag-zh.ps1 需要 UTF-8 BOM（Windows PowerShell 5.1）")
    cmd = read(os.path.join(ROOT, "ag-zh.cmd"), binary=True)
    require(all(b < 128 for b in cmd), "ag-zh.cmd 必须保持纯 ASCII，避免代码页乱码")
    if sys.platform != "win32":
        r = subprocess.run(["bash", "-n", os.path.join(ROOT, "ag-zh")], capture_output=True)
        require(r.returncode == 0, "ag-zh 语法错误: %s" % r.stderr.decode("utf-8", "replace"))
    return "PS1 带 BOM / CMD 纯 ASCII / bash 语法通过"


def test_release_files():
    for name in ("README.md", "LICENSE", "CREDITS.md", ".gitignore",
                 "ci/ci.yml", "enable-ci.sh"):
        p = os.path.join(ROOT, name)
        require(os.path.isfile(p) and os.path.getsize(p) > 50, "缺少或过小: %s" % name)
    readme = read(os.path.join(ROOT, "README.md"))
    for kw in ("Windows", "ag-zh.cmd", "restore-full", "zhonghugo"):
        require(kw in readme, "README 缺少关键内容: %s" % kw)
    return "发布文件齐全"


def test_no_hardcoded_private_paths():
    # 拼接构造，避免自检文件自身出现被检测的字面量
    _u = "wang" + "qieyu"
    bad = ("/Users/" + _u, "WorkBuddy/2026-", "C:\\Users\\" + _u)
    scan = ["install.py", "asar.py", "ag-zh", "ag-zh.ps1", "ag-zh.cmd",
            "tests/selftest.py", "ci/ci.yml", "enable-ci.sh", "README.md"]
    for name in scan:
        text = read(os.path.join(ROOT, name))
        for token in bad:
            # 自检脚本自身包含这些字面量，跳过
            if name == "tests/selftest.py":
                continue
            require(token not in text, "%s 含硬编码本机路径 %s" % (name, token))
    return "无硬编码个人路径"


def main():
    case("源码语法", test_sources_compile)
    case("词典完整性", test_dictionary)
    case("翻译引擎模板", test_engine_template)
    case("注入产物", test_build_injection)
    case("asar 往返", test_asar_roundtrip)
    case("跨平台 --info", test_install_info)
    case("Windows 模拟", test_windows_simulation)
    case("启动脚本", test_launchers)
    case("发布文件", test_release_files)
    case("隐私检查", test_no_hardcoded_private_paths)

    print("== antigravity-zh-toolkit 自检 (%s / Python %s) ==" %
          (sys.platform, sys.version.split()[0]))
    for ok, name, detail in RESULTS:
        print("  [%s] %-16s %s" % ("PASS" if ok else "FAIL", name, detail))
    failed = [r for r in RESULTS if not r[0]]
    print("结果: %d 通过, %d 失败" % (len(RESULTS) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
