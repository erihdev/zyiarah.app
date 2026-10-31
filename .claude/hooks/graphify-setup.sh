#!/usr/bin/env bash
# خريطةُ المشروعِ المعرفيّة (Graphify) — تُبنى عند بدءِ كلِّ جلسةٍ سحابيّة.
# تحليلٌ محلّيٌّ للشفرةِ (tree-sitter) بلا نموذجٍ ولا توكنز، والخريطةُ لا تُرفَعُ للمستودع (graphify-out/ مُستثنى).
# على جهازِ المطوّرِ لا يَفعلُ شيئاً: هناك تثبيتٌ محلّيٌّ مستقلّ.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

BIN="$HOME/.local/bin"
export PATH="$BIN:$PATH"
# ليَجدَ أمرُ Bash في الجلسةِ `graphify` بعدَ التثبيت
[ -n "${CLAUDE_ENV_FILE:-}" ] && echo "export PATH=\"$BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"

# في الخلفيّة: لا تتأخّرُ بدايةُ الجلسة، وما دامت الخريطةُ لم تكتمل تُقرأُ الملفّاتُ كالمعتاد
(
  command -v graphify >/dev/null 2>&1 || pip install --quiet --user --break-system-packages graphifyy || exit 0
  if [ -f graphify-out/graph.json ]; then
    graphify update .
  else
    graphify extract . --code-only && graphify cluster-only . --no-label
  fi
) > /tmp/graphify-setup.log 2>&1 &
disown 2>/dev/null || true
exit 0
