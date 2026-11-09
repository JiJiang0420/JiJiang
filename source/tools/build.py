#!/usr/bin/env python3
"""Export, package and checksum the slice using installed Godot 4.6.3 templates."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
TARGETS = {
    "windows": ("Windows", "WitchesFeast2.exe"),
    "linux": ("Linux", "WitchesFeast2.x86_64"),
    "web": ("Web", "index.html"),
}


def run(command, log, env=None):
    print("Running:", " ".join(map(str, command)), flush=True)
    with log.open("w") as handle:
        result = subprocess.run(list(map(str, command)), cwd=ROOT, env=env,
                                stdout=handle, stderr=subprocess.STDOUT)
    text = log.read_text(errors="replace")
    if result.returncode or "SCRIPT ERROR:" in text or "ERROR:" in text:
        raise RuntimeError(f"Build/check failed; inspect {log}\n{text[-4000:]}")


def archive(directory, output):
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as pack:
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                pack.write(path, Path(directory.name) / path.relative_to(directory))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, default=ROOT / "builds")
    parser.add_argument("--targets", nargs="+", choices=TARGETS, default=list(TARGETS))
    parser.add_argument("--skip-tests", action="store_true")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    if not version.startswith("4.6.3"):
        raise RuntimeError(f"Expected Godot 4.6.3, got {version}")
    base = [args.godot, "--headless", "--path", GAME]
    run(base + ["--editor", "--import", "--quit"], out / "import.log")
    if not args.skip_tests:
        for suite in ("smoke", "combat_v02"):
            with tempfile.TemporaryDirectory(prefix="wf2-smoke.") as scratch:
                env = os.environ.copy()
                env.update(WITCHES_FEAST_TEST="1", XDG_DATA_HOME=f"{scratch}/data",
                           XDG_CONFIG_HOME=f"{scratch}/config", XDG_CACHE_HOME=f"{scratch}/cache")
                run(base + ["--script", f"res://tests/{suite}.gd"], out / f"{suite}-tests.log", env)
    license_file = out / "GODOT-LICENSES.txt"
    run(base + ["--script", ROOT / "tools/export_licenses.gd", "--", license_file],
        out / "licenses.log")
    packages = []
    for target in args.targets:
        preset, filename = TARGETS[target]
        directory = out / target
        directory.mkdir(exist_ok=True)
        run(base + ["--export-release", preset, directory / filename], out / f"export-{target}.log")
        if target == "linux":
            (directory / filename).chmod(0o755)
        shutil.copy2(license_file, directory / license_file.name)
        shutil.copy2(GAME / "assets/fonts/LICENSE.txt", directory / "NOTO-LICENSE.txt")
        instructions = {
            "windows": "解压后双击 WitchesFeast2.exe。无需安装 Godot。",
            "linux": "解压后运行 chmod +x WitchesFeast2.x86_64，再执行 ./WitchesFeast2.x86_64。",
            "web": "在此目录运行 python3 -m http.server 8000，再打开 http://localhost:8000。\n不能直接双击 HTML。浏览器兼容性需要单独验证；优先使用桌面 Chromium 浏览器。",
        }
        (directory / "开始试玩.txt").write_text(
            "魔女的盛宴 2.0 · 三神遗宴 / 垂直切片 v0.2\n\n" + instructions[target] +
            "\n\n建议先进入试炼场。WASD 移动；左键拖绘、松开施法；右键取消；"
            "1/2/3 切换；空格闪避；中键拖动旋转；Home 复位；Esc 暂停；H 操作指南。\n"
            "试炼场 Q 切换当前斗篷分支：短切 / 收线 / 推墙。收线、推墙需在松开左键后再按右键执行第二段。\n"
            "八分钟标准局 / 三分钟快速局。阶段结束进入商店；最后击败首领。\n"
            "阶段残纱自动保存；不支持战斗中途续局。简化模型与程序动画，数值待试玩验收。\n",
            encoding="utf-8")
        package = out / f"WitchesFeast2-v0.2-{target}.zip"
        archive(directory, package)
        packages.append(package)
    source = out / "WitchesFeast2-v0.2-source.zip"
    with zipfile.ZipFile(source, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as pack:
        for path in sorted(ROOT.rglob("*")):
            if not path.is_file() or path.is_relative_to(out):
                continue
            rel = path.relative_to(ROOT)
            if any(part in {".godot", "builds", "__pycache__"} for part in rel.parts):
                continue
            if path.suffix in {".blend1", ".pyc"}:
                continue
            pack.write(path, Path("witches-feast-2") / rel)
    packages.append(source)
    (out / "SHA256SUMS.txt").write_text("".join(
        f"{hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()}  {path.name}\n"
        for path in packages), encoding="utf-8")
    print("Builds complete:", out, flush=True)
    for path in packages:
        print(f"  {path.name}: {path.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
