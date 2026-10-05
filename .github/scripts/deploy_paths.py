#!/usr/bin/env python3
"""مساراتُ هدفِ نشرٍ من ملفِّ سيرِه — لا نسخةٌ ثانيةٌ مكتوبةٌ بيد.

كاشفُ الانحرافِ (`deploy_drift.yml`) يَحتاجُ أن يَعرفَ ما يَمسُّ كلَّ هدف،
وكتابةُ القوائمِ فيه ثانيةً تَنحرِفُ — وانحرافُ كاشفِ الانحرافِ مُفارقةٌ لا
تُحتَمل. فتُقرأُ من `on.push.paths` في ملفِّ السيرِ نفسِه.

تُطبَعُ المساراتُ مفصولةً بمسافاتٍ لتُمرَّرَ إلى `git log -- …`.
"""
import re
import sys


def push_paths(text: str) -> list:
    """الأسطرُ `- '...'` التي تَتبعُ `paths:` حتى أوّلِ سطرٍ ليس منها."""
    out, inside = [], False
    for line in text.split("\n"):
        if re.match(r"\s*paths:\s*$", line):
            inside = True
            continue
        if not inside:
            continue
        m = re.match(r"\s*-\s*'([^']+)'\s*$", line)
        if m:
            out.append(m.group(1))
        else:
            break
    return out


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as fh:
        paths = push_paths(fh.read())
    if not paths:
        sys.exit(1)
    print(" ".join(paths))
