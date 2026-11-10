#!/usr/bin/env python3
"""Generate kidlearn_ai_config.json and optionally copy it to a Kindle.

The generated file is read by KidLearn on startup from
koreader/settings/kidlearn_ai_config.json.  Only the Python standard library
is used, so this works on a normal macOS/Linux development machine.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

PRESETS = (
    "openai",
    "deepseek",
    "qwen",
    "kimi",
    "zhipu",
    "doubao",
    "gemini",
    "claude",
    "siliconflow",
    "openrouter",
    "ollama",
    "custom",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="生成小小学习家 AI 配置文件，可直接复制到 Kindle。"
    )
    parser.add_argument("--preset", default="deepseek", choices=PRESETS, help="AI 服务预设，默认 deepseek")
    parser.add_argument("--api-key", required=True, help="API Key（不要提交到 Git）")
    parser.add_argument("--model", required=True, help="模型名称，例如 deepseek-chat")
    parser.add_argument("--base-url", help="接口地址；省略时使用预设默认地址")
    parser.add_argument("--name", help="显示名称；省略时使用预设名称")
    parser.add_argument("--output", default="kidlearn_ai_config.json", help="本地输出路径")
    parser.add_argument(
        "--mount",
        help="Kindle 挂载点，例如 /Volumes/Kindle；指定后会复制到 koreader/settings/",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    profile = {
        "preset": args.preset,
        "api_key": args.api_key.strip(),
        "model": args.model.strip(),
    }
    if args.base_url:
        profile["base_url"] = args.base_url.strip()
    if args.name:
        profile["name"] = args.name.strip()
    if not profile["api_key"]:
        print("错误：API Key 不能为空。", file=sys.stderr)
        return 2
    if not profile["model"]:
        print("错误：模型名称不能为空。", file=sys.stderr)
        return 2

    output = Path(args.output).expanduser()
    output.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已生成：{output}")
    print(f"服务：{args.preset} · {profile['model']}")

    if args.mount:
        settings_dir = Path(args.mount).expanduser() / "koreader" / "settings"
        if not settings_dir.is_dir():
            print(f"错误：找不到 {settings_dir}，请确认 Kindle 已用 USB 连接并已挂载。", file=sys.stderr)
            return 3
        destination = settings_dir / "kidlearn_ai_config.json"
        shutil.copyfile(output, destination)
        print(f"已推送到：{destination}")
        print("安全弹出 Kindle，重启 KOReader 后生效。")
    else:
        print("下一步：把该文件复制到 Kindle 的 koreader/settings/kidlearn_ai_config.json。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
