#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


@dataclass(frozen=True)
class DeviceInfo:
    device_model: str
    system_name: str
    system_version: str


@dataclass(frozen=True)
class Score:
    overall: float
    speed: Optional[float]
    throughput: float
    resource: float
    median_rtf: Optional[float]
    median_tps: float
    median_cpu: float
    median_mem_mb: float


@dataclass(frozen=True)
class SummaryRow:
    model_id: str
    model_name: str
    engine_id: str
    prompt_count: int
    model_load_ms: Optional[float]
    score: Score


@dataclass(frozen=True)
class Export:
    started_at_iso8601: str
    dataset: str
    device: DeviceInfo
    summaries: list[SummaryRow]


def _parse_float(v: Any) -> Optional[float]:
    if v is None:
        return None
    try:
        return float(v)
    except Exception:
        return None


def load_export(path: Path) -> Export:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    device_raw = data.get("device") or {}
    device = DeviceInfo(
        device_model=str(device_raw.get("deviceModel") or ""),
        system_name=str(device_raw.get("systemName") or ""),
        system_version=str(device_raw.get("systemVersion") or ""),
    )

    summaries: list[SummaryRow] = []
    for s in data.get("summaries") or []:
        score_raw = s.get("score") or {}
        model_load_ms = _parse_float(s.get("modelLoadMs"))
        score = Score(
            overall=float(score_raw.get("overallScore0to100") or 0.0),
            speed=_parse_float(score_raw.get("speedScore")),
            throughput=float(score_raw.get("throughputScore") or 0.0),
            resource=float(score_raw.get("resourceScore") or 0.0),
            median_rtf=_parse_float(score_raw.get("medianRtf")),
            median_tps=float(score_raw.get("medianTokensPerSecond") or 0.0),
            median_cpu=float(score_raw.get("medianCpuAvg") or 0.0),
            median_mem_mb=float(score_raw.get("medianMemMaxMB") or 0.0),
        )
        summaries.append(
            SummaryRow(
                model_id=str(s.get("modelId") or ""),
                model_name=str(s.get("modelDisplayName") or ""),
                engine_id=str(s.get("engineId") or ""),
                prompt_count=int(s.get("promptCount") or 0),
                model_load_ms=model_load_ms,
                score=score,
            )
        )

    return Export(
        started_at_iso8601=str(data.get("startedAtISO8601") or ""),
        dataset=str(data.get("dataset") or ""),
        device=device,
        summaries=summaries,
    )


def find_latest_results_json(repo_dir: Path) -> Path:
    # Prefer files pulled by scripts/test-all-device.sh.
    candidates = list(repo_dir.glob("device-exports/**/results-*.json"))
    if not candidates:
        raise FileNotFoundError("No results JSON found under device-exports/**/results-*.json")

    # Heuristic: pick the "largest" benchmark (most prompt runs), breaking ties by newest.
    def score_path(p: Path) -> tuple[int, float]:
        total_prompts = 0
        try:
            with p.open("r", encoding="utf-8") as f:
                d = json.load(f)
            for s in d.get("summaries") or []:
                total_prompts += int(s.get("promptCount") or 0)
        except Exception:
            total_prompts = 0
        return (total_prompts, p.stat().st_mtime)

    return max(candidates, key=score_path)


def fmt_num(v: Optional[float], digits: int = 2) -> str:
    if v is None:
        return "-"
    if not (v == v) or v in (float("inf"), float("-inf")):
        return "-"
    return f"{v:.{digits}f}"


def markdown_table(export: Export) -> str:
    rows = sorted(export.summaries, key=lambda r: r.score.median_tps, reverse=True)

    header = [
        "| Model | Engine | Prompts | Median Tok/s |",
        "|---|---|---:|---:|",
    ]

    body = []
    for r in rows:
        body.append(
            "| "
            + " | ".join(
                [
                    r.model_name.replace("\n", " "),
                    f"`{r.engine_id}`",
                    str(r.prompt_count),
                    fmt_num(r.score.median_tps),
                ]
            )
            + " |"
        )

    return "\n".join(header + body)


def _iso_date(iso: str) -> str:
    try:
        # Expect "2026-02-15T13:36:15Z"
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d")
    except Exception:
        return iso


def generate_bar_chart_svg(
    *,
    rows: list[SummaryRow],
    out_path: Path,
    title: str,
    subtitle: str,
    unit: str,
    value_fn,
    sort_key_fn,
    ascending: bool,
    max_rows: int = 25,
    max_value_override: Optional[float] = None,
    tick_digits: Optional[int] = None,
    value_digits: int = 1,
) -> None:
    rows2 = [r for r in rows if value_fn(r) is not None]
    rows2.sort(key=sort_key_fn, reverse=not ascending)
    rows2 = rows2[:max_rows]
    if not rows2:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("", encoding="utf-8")
        return

    values = [float(value_fn(r) or 0.0) for r in rows2]
    max_value = float(max_value_override) if max_value_override is not None else (max(values) if values else 1.0)
    if max_value <= 0:
        max_value = 1.0

    # Layout constants inspired by android-offline-transcribe/assets/android_tokens_per_second.svg
    width = 860
    left_label_w = 300
    chart_x0 = left_label_w
    chart_x1 = 760
    chart_w = chart_x1 - chart_x0
    bar_h = 20
    row_gap = 6
    top_y = 60

    rows_h = len(rows2) * (bar_h + row_gap) - row_gap
    axis_y = top_y + rows_h + 16
    height = axis_y + 40

    ticks = 5
    tick_step = max_value / ticks
    if tick_digits is None:
        if max_value < 1:
            tick_digits = 2
        elif max_value < 10:
            tick_digits = 1
        else:
            tick_digits = 0

    def esc(s: str) -> str:
        return (
            s.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&apos;")
        )

    parts: list[str] = []
    parts.append(f"<svg xmlns='http://www.w3.org/2000/svg' width='{width}' height='{height}' viewBox='0 0 {width} {height}'>")
    parts.append("<style>")
    parts.append("text { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif; }")
    parts.append(".title { font-size: 18px; font-weight: 700; fill: #1f2937; }")
    parts.append(".subtitle { font-size: 11px; fill: #6b7280; }")
    parts.append(".axis { font-size: 10px; fill: #6b7280; }")
    parts.append(".label { font-size: 11px; fill: #374151; }")
    parts.append(".value { font-size: 10px; fill: #374151; font-weight: 600; }")
    parts.append("</style>")
    parts.append("<rect width='100%' height='100%' fill='#ffffff' />")
    parts.append(f"<text x='{left_label_w}' y='24' class='title'>{esc(title)}</text>")
    parts.append(f"<text x='{left_label_w}' y='42' class='subtitle'>{esc(subtitle)}</text>")

    # Axes
    parts.append(f"<line x1='{chart_x0}' y1='56' x2='{chart_x0}' y2='{axis_y}' stroke='#e5e7eb' />")
    parts.append(f"<line x1='{chart_x0}' y1='{axis_y}' x2='{chart_x1}' y2='{axis_y}' stroke='#e5e7eb' />")

    # X ticks + grid
    for i in range(ticks + 1):
        v = tick_step * i
        x = chart_x0 + (v / max_value) * chart_w
        parts.append(f"<line x1='{x:.1f}' y1='{axis_y}' x2='{x:.1f}' y2='{axis_y + 5}' stroke='#d1d5db' />")
        parts.append(f"<text x='{x:.1f}' y='{axis_y + 20}' text-anchor='middle' class='axis'>{fmt_num(v, digits=tick_digits)}</text>")
        if i != 0:
            parts.append(f"<line x1='{x:.1f}' y1='56' x2='{x:.1f}' y2='{axis_y}' stroke='#f3f4f6' />")

    def color_for(engine_id: str) -> str:
        if engine_id.startswith("native."):
            return "#9ca3af"
        return "#3b82f6"

    # Bars
    for idx, r in enumerate(rows2):
        y = top_y + idx * (bar_h + row_gap)
        label_y = y + 15

        parts.append(f"<text x='{chart_x0 - 8}' y='{label_y}' text-anchor='end' class='label'>{esc(r.model_name)}</text>")

        value = float(value_fn(r) or 0.0)
        w = (max(0.0, value) / max_value) * chart_w
        fill = color_for(r.engine_id)
        parts.append(f"<rect x='{chart_x0}' y='{y}' width='{w:.1f}' height='{bar_h}' rx='3' fill='{fill}' />")

        parts.append(f"<text x='{chart_x0 + w + 6:.1f}' y='{label_y}' class='value'>{fmt_num(value, digits=value_digits)}</text>")

    parts.append("</svg>")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(parts) + "\n", encoding="utf-8")


def update_readme(readme_path: Path, generated_block: str) -> None:
    text = readme_path.read_text(encoding="utf-8")
    start = "<!-- BENCHMARK_RESULTS_START -->"
    end = "<!-- BENCHMARK_RESULTS_END -->"

    a = text.find(start)
    b = text.find(end)
    if a == -1 or b == -1 or b <= a:
        raise ValueError(f"README markers not found: {start} / {end}")

    before = text[: a + len(start)]
    after = text[b:]
    new_text = before + "\n" + generated_block.rstrip() + "\n" + after
    readme_path.write_text(new_text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a simple tok/s benchmark table + SVG from TTSEval results JSON.")
    parser.add_argument("--input", type=str, default="", help="Path to results-*.json. Defaults to latest under device-exports/**/.")
    parser.add_argument("--readme", type=str, default="README.md", help="README path (repo-relative).")
    parser.add_argument("--svg-tps", type=str, default="docs/ios_tts_tok_per_sec.svg", help="Tok/s SVG output path (repo-relative).")
    parser.add_argument("--update-readme", action="store_true", help="Update README between BENCHMARK_RESULTS markers.")
    args = parser.parse_args()

    repo_dir = Path(__file__).resolve().parents[1]
    in_path = Path(args.input) if args.input else find_latest_results_json(repo_dir)
    if not in_path.is_absolute():
        in_path = (repo_dir / in_path).resolve()

    export = load_export(in_path)
    subtitle = f"{export.device.device_model} ({export.device.system_name} {export.device.system_version}), dataset={export.dataset}, {len(export.summaries)} models, {_iso_date(export.started_at_iso8601)}"

    svg_tps = (repo_dir / args.svg_tps).resolve()

    generate_bar_chart_svg(
        rows=export.summaries,
        out_path=svg_tps,
        title="iOS TTS — Median Throughput (tok/s)",
        subtitle=subtitle,
        unit="tok/s",
        value_fn=lambda r: r.score.median_tps,
        sort_key_fn=lambda r: float(r.score.median_tps),
        ascending=False,
        value_digits=1,
    )

    block_lines = []
    block_lines.append("### Latest Benchmark")
    block_lines.append("")
    block_lines.append(f"- Device: `{export.device.device_model}` ({export.device.system_name} {export.device.system_version})")
    block_lines.append(f"- Dataset: `{export.dataset}`")
    block_lines.append(f"- Started: `{export.started_at_iso8601}`")
    block_lines.append("")
    block_lines.append(f"![iOS TTS Tok/s]({args.svg_tps})")
    block_lines.append("")
    block_lines.append(markdown_table(export))

    block = "\n".join(block_lines) + "\n"

    if args.update_readme:
        readme_path = Path(args.readme)
        if not readme_path.is_absolute():
            readme_path = (repo_dir / readme_path).resolve()
        update_readme(readme_path, block)

    print(f"Input: {in_path}")
    print(f"SVG tps:     {svg_tps}")
    if args.update_readme:
        print(f"README updated: {readme_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
