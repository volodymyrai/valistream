"""Report package — JSON and Markdown report generators."""

from valistream.report.json_report import build_report_dict, generate_json_report
from valistream.report.markdown import build_markdown, generate_markdown_report

__all__ = [
    "build_markdown",
    "build_report_dict",
    "generate_json_report",
    "generate_markdown_report",
]
