from __future__ import annotations

import re
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "scripts" / "assets" / "download-sources.yml"
OUTPUT = ROOT / "docs" / "download-sources.pdf"


def register_fonts() -> tuple[str, str]:
    regular_path = "/System/Library/Fonts/STHeiti Light.ttc"
    bold_path = "/System/Library/Fonts/STHeiti Medium.ttc"
    pdfmetrics.registerFont(TTFont("CNRegular", regular_path, subfontIndex=0))
    pdfmetrics.registerFont(TTFont("CNBold", bold_path, subfontIndex=0))
    return "CNRegular", "CNBold"


BODY_FONT, BOLD_FONT = register_fonts()


def make_styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "TitleCN",
            parent=base["Title"],
            fontName=BOLD_FONT,
            fontSize=22,
            leading=28,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#111827"),
            spaceAfter=8,
        ),
        "subtitle": ParagraphStyle(
            "SubtitleCN",
            parent=base["BodyText"],
            fontName=BODY_FONT,
            fontSize=10,
            leading=15,
            alignment=TA_CENTER,
            textColor=colors.HexColor("#4b5563"),
            spaceAfter=8,
        ),
        "h2": ParagraphStyle(
            "Heading2CN",
            parent=base["Heading2"],
            fontName=BOLD_FONT,
            fontSize=14,
            leading=18,
            textColor=colors.HexColor("#111827"),
            spaceBefore=9,
            spaceAfter=6,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "BodyCN",
            parent=base["BodyText"],
            fontName=BODY_FONT,
            fontSize=9.5,
            leading=14,
            alignment=TA_LEFT,
            textColor=colors.HexColor("#1f2937"),
            spaceAfter=5,
            wordWrap="CJK",
        ),
        "small": ParagraphStyle(
            "SmallCN",
            parent=base["BodyText"],
            fontName=BODY_FONT,
            fontSize=7.2,
            leading=9.5,
            textColor=colors.HexColor("#374151"),
            wordWrap="CJK",
        ),
        "tiny": ParagraphStyle(
            "TinyCN",
            parent=base["BodyText"],
            fontName=BODY_FONT,
            fontSize=6.6,
            leading=8.6,
            textColor=colors.HexColor("#374151"),
            wordWrap="CJK",
        ),
        "code": ParagraphStyle(
            "CodeCN",
            parent=base["Code"],
            fontName=BODY_FONT,
            fontSize=8,
            leading=10,
            textColor=colors.HexColor("#111827"),
            backColor=colors.HexColor("#f3f4f6"),
            borderColor=colors.HexColor("#e5e7eb"),
            borderWidth=0.5,
            borderPadding=5,
            spaceBefore=2,
            spaceAfter=8,
        ),
    }


S = make_styles()


def inline(text: str) -> str:
    text = escape(text)
    text = re.sub(r"`([^`]+)`", r'<font name="Courier">\1</font>', text)
    return text


def read_manifest() -> list[dict[str, str]]:
    assets: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for raw in MANIFEST.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        id_match = re.match(r"\s+- id:\s+(.+?)\s*$", line)
        if id_match:
            if current:
                assets.append(current)
            current = {"id": strip_value(id_match.group(1))}
            continue
        item_match = re.match(r"\s+([a-zA-Z0-9_-]+):\s*(.*?)\s*$", line)
        if item_match and current is not None:
            current[item_match.group(1)] = strip_value(item_match.group(2))
    if current:
        assets.append(current)
    return assets


def strip_value(value: str) -> str:
    return value.strip().strip('"')


def p(text: str, style: str = "body") -> Paragraph:
    return Paragraph(inline(text), S[style])


def bullet_list(items: list[str]) -> ListFlowable:
    return ListFlowable(
        [ListItem(p(item), leftIndent=0) for item in items],
        bulletType="bullet",
        leftIndent=14,
        bulletFontName=BODY_FONT,
        bulletFontSize=7,
    )


def asset_table(assets: list[dict[str, str]]) -> Table:
    rows = [[
        p("软件", "small"),
        p("当前文件", "small"),
        p("版本", "small"),
        p("更新方式", "small"),
        p("下载地址 / 来源页", "small"),
        p("SHA256", "small"),
    ]]
    for asset in assets:
        url = asset.get("url", "")
        source_page = asset.get("source_page", "")
        link_text = url if url == source_page else f"{url}\n来源: {source_page}"
        sha = asset.get("sha256", "")
        sha_text = "" if not sha else f"{sha[:16]}...\n{sha[-16:]}"
        rows.append([
            p(asset.get("name", asset.get("id", "")), "small"),
            p(asset.get("local_file", "不打包") or "不打包", "tiny"),
            p(asset.get("version", ""), "small"),
            p(asset.get("update_policy", ""), "tiny"),
            p(link_text, "tiny"),
            p(sha_text, "tiny"),
        ])

    table = Table(
        rows,
        colWidths=[30 * mm, 48 * mm, 22 * mm, 44 * mm, 93 * mm, 34 * mm],
        repeatRows=1,
        hAlign="LEFT",
    )
    table.setStyle(table_style())
    return table


def table_style() -> TableStyle:
    return TableStyle(
        [
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e0f2fe")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#0f172a")),
            ("FONTNAME", (0, 0), (-1, -1), BODY_FONT),
            ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#cbd5e1")),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 4),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ]
    )


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont(BODY_FONT, 8)
    canvas.setFillColor(colors.HexColor("#64748b"))
    canvas.drawString(14 * mm, 9 * mm, "OpenClaw 下载源与打包前刷新说明")
    canvas.drawRightString(283 * mm, 9 * mm, f"第 {doc.page} 页")
    canvas.restoreState()


def build_story():
    assets = read_manifest()
    public_assets = [a for a in assets if a.get("check_method") == "head"]
    manual_assets = [a for a in assets if a.get("check_method") != "head"]

    story = [
        p("OpenClaw 下载源与打包前刷新说明", "title"),
        p("平时只保存下载源；准备重新打上传包前，再手动刷新公开直链资产。", "subtitle"),
        p("核心策略", "h2"),
        bullet_list(
            [
                "可稳定 HEAD 的公开直链可以在打包前重新下载，并更新本地 SHA。",
                "Apple Command Line Tools 属于 Apple Developer 手动下载，当前固定来源，不进入定期直链刷新。",
                "钉钉、向日葵这类厂商页的最终文件 URL 可能变化，按官方下载页人工更新。",
                "豆包输入法不打包、不自动安装，用户需要时从官方页面手动下载。",
            ]
        ),
        Spacer(1, 4 * mm),
        p("常用命令", "h2"),
        Preformatted(
            "\n".join(
                [
                    "# 只检查直链是否可用，不下载",
                    "bash scripts/check-download-sources.sh",
                    "",
                    "# 预览会刷新哪些资产",
                    "bash scripts/refresh-download-assets.sh --dry-run",
                    "",
                    "# 打包前重新下载公开直链资产",
                    "bash scripts/refresh-download-assets.sh",
                    "",
                    "# profile 打包时自动刷新",
                    "REFRESH_DOWNLOAD_ASSETS=1 OVERWRITE_DIST=1 bash scripts/build-dist.sh all",
                ]
            ),
            S["code"],
        ),
        p("可自动刷新的公开直链", "h2"),
        asset_table(public_assets),
        PageBreak(),
        p("人工来源与不自动下载项", "h2"),
        asset_table(manual_assets),
        Spacer(1, 5 * mm),
        p("更新后验收", "h2"),
        bullet_list(
            [
                "运行 refresh 脚本后，确认 scripts/assets/download-sources.yml 中 SHA 已更新。",
                "如果文件名或版本号变化，手动更新 docs/download-sources.md 和 scripts/assets/download-sources.yml。",
                "同步到 install-files/openclaw-team/ 后重新打包。",
                "至少在一台测试 Mac 上运行 bash install-openclaw.sh --skip-secrets。",
                "如果改动 Node、Codex、OpenClaw、CLIProxyAPI 或 Clash 相关包，再运行 INSTALL_PHASE=validate bash install-files/install-new-macbook.sh。",
            ]
        ),
    ]
    return story


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=landscape(A4),
        rightMargin=12 * mm,
        leftMargin=12 * mm,
        topMargin=12 * mm,
        bottomMargin=14 * mm,
        title="OpenClaw 下载源与打包前刷新说明",
        author="OpenClaw Installer",
    )
    doc.build(build_story(), onFirstPage=footer, onLaterPages=footer)
    print(OUTPUT)


if __name__ == "__main__":
    main()
