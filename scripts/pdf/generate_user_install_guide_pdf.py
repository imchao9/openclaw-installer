from __future__ import annotations

import sys
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
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
    KeepTogether,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "user-install-guide.md"
OUTPUT = ROOT / "docs" / "user-install-guide.pdf"
DOCUMENT_TITLE = "OpenClaw 用户安装说明"


def register_fonts() -> tuple[str, str]:
    regular_path = "/System/Library/Fonts/STHeiti Light.ttc"
    bold_path = "/System/Library/Fonts/STHeiti Medium.ttc"
    pdfmetrics.registerFont(TTFont("CNRegular", regular_path, subfontIndex=0))
    pdfmetrics.registerFont(TTFont("CNBold", bold_path, subfontIndex=0))
    return "CNRegular", "CNBold"


BODY_FONT, BOLD_FONT = register_fonts()


def styles():
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
            spaceAfter=12,
        ),
        "h2": ParagraphStyle(
            "Heading2CN",
            parent=base["Heading2"],
            fontName=BOLD_FONT,
            fontSize=15,
            leading=20,
            textColor=colors.HexColor("#111827"),
            spaceBefore=14,
            spaceAfter=8,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "BodyCN",
            parent=base["BodyText"],
            fontName=BODY_FONT,
            fontSize=10.5,
            leading=16,
            alignment=TA_LEFT,
            textColor=colors.HexColor("#1f2937"),
            spaceAfter=7,
            wordWrap="CJK",
        ),
        "small": ParagraphStyle(
            "SmallCN",
            parent=base["BodyText"],
            fontName=BODY_FONT,
            fontSize=9,
            leading=13,
            textColor=colors.HexColor("#374151"),
            wordWrap="CJK",
        ),
        "code": ParagraphStyle(
            "Code",
            parent=base["Code"],
            fontName=BODY_FONT,
            fontSize=8.5,
            leading=11,
            textColor=colors.HexColor("#111827"),
            backColor=colors.HexColor("#f3f4f6"),
            borderColor=colors.HexColor("#e5e7eb"),
            borderWidth=0.5,
            borderPadding=6,
            spaceBefore=3,
            spaceAfter=9,
        ),
    }


S = styles()


def inline(text: str) -> str:
    out = []
    parts = text.split("`")
    for i, part in enumerate(parts):
        part = escape(part)
        if i % 2:
            out.append(f'<font name="Courier" backColor="#f3f4f6">{part}</font>')
        else:
            out.append(part)
    return "".join(out)


def table_from(lines: list[str]) -> Table:
    rows = []
    for line in lines:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells and all(set(cell) <= {"-", ":", " "} for cell in cells):
            continue
        rows.append([Paragraph(inline(cell), S["small"]) for cell in cells])
    col_count = max(len(row) for row in rows)
    widths = [75 * mm, 100 * mm] if col_count == 2 else None
    table = Table(rows, colWidths=widths, hAlign="LEFT", repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#eef2ff")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#111827")),
                ("FONTNAME", (0, 0), (-1, -1), BODY_FONT),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("LEADING", (0, 0), (-1, -1), 12),
                ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#d1d5db")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    return table


def build_story(markdown: str):
    story = []
    lines = markdown.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        if not line:
            i += 1
            continue
        if line.startswith("# "):
            story.append(Paragraph(inline(line[2:].strip()), S["title"]))
            story.append(Spacer(1, 4 * mm))
            i += 1
            continue
        if line.startswith("## "):
            story.append(Paragraph(inline(line[3:].strip()), S["h2"]))
            i += 1
            continue
        if line.startswith("### "):
            story.append(Paragraph(inline(line[4:].strip()), S["h2"]))
            i += 1
            continue
        if line.startswith("```"):
            code = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                code.append(lines[i])
                i += 1
            i += 1
            story.append(KeepTogether([Preformatted("\n".join(code), S["code"], maxLineLength=88)]))
            continue
        if line.startswith("|"):
            table_lines = []
            while i < len(lines) and lines[i].startswith("|"):
                table_lines.append(lines[i])
                i += 1
            story.append(table_from(table_lines))
            story.append(Spacer(1, 6 * mm))
            continue
        if line.startswith("- "):
            items = []
            while i < len(lines) and lines[i].startswith("- "):
                item = Paragraph(inline(lines[i][2:].strip()), S["body"])
                items.append(ListItem(item, leftIndent=0))
                i += 1
            story.append(
                ListFlowable(
                    items,
                    bulletType="bullet",
                    start="circle",
                    leftIndent=14,
                    bulletFontName=BODY_FONT,
                    bulletFontSize=8,
                )
            )
            story.append(Spacer(1, 3 * mm))
            continue
        if line[:2].isdigit() and ". " in line[:5]:
            start_num = int(line.split(". ", 1)[0])
            items = []
            while i < len(lines) and lines[i][:2].strip("0123456789") == "" and ". " in lines[i][:5]:
                text = lines[i].split(". ", 1)[1].strip()
                items.append(ListItem(Paragraph(inline(text), S["body"]), leftIndent=0))
                i += 1
            story.append(
                ListFlowable(
                    items,
                    bulletType="1",
                    start=str(start_num),
                    leftIndent=18,
                    bulletDedent=8,
                    bulletFontName=BODY_FONT,
                    bulletFontSize=10,
                )
            )
            story.append(Spacer(1, 3 * mm))
            continue
        story.append(Paragraph(inline(line), S["body"]))
        i += 1
    return story


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont(BODY_FONT, 8)
    canvas.setFillColor(colors.HexColor("#6b7280"))
    canvas.drawString(18 * mm, 12 * mm, DOCUMENT_TITLE)
    canvas.drawRightString(192 * mm, 12 * mm, f"第 {doc.page} 页")
    canvas.restoreState()


def main():
    global DOCUMENT_TITLE, OUTPUT, SOURCE

    if len(sys.argv) not in (1, 3, 4):
        print(
            "Usage: python3 scripts/pdf/generate_user_install_guide_pdf.py "
            "[source.md output.pdf [title]]",
            file=sys.stderr,
        )
        raise SystemExit(1)

    if len(sys.argv) >= 3:
        SOURCE = Path(sys.argv[1])
        OUTPUT = Path(sys.argv[2])
    if len(sys.argv) == 4:
        DOCUMENT_TITLE = sys.argv[3]

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=18 * mm,
        bottomMargin=18 * mm,
        title=DOCUMENT_TITLE,
        author="OpenClaw Installer",
    )
    story = build_story(SOURCE.read_text(encoding="utf-8"))
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print(OUTPUT)


if __name__ == "__main__":
    main()
