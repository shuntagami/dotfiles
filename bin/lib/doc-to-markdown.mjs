// Google Docs API のレスポンスを Markdown に変換する共通モジュール。
//
// 対象ユーザー: apps/web/scripts/ 配下の .mjs スクリプト
//   - extract-product-design.mjs（商品設計 Doc 取り込み）
//   - sync-doc-to-md.mjs（任意タスクの Doc → .md 同期）
//   - 将来: 他の Doc を取り込むスクリプトでも再利用可
//
// 提供する関数:
//   - extractDocId(url)                      — URL から Doc ID を取り出す
//   - docToMarkdown(doc)                     — Docs API レスポンス → Markdown
//   - getDocWithSuggestionFallback(docs, id) — 提案モード反映済みで取得（権限が無ければ通常モードへフォールバック）
//
// 設計メモ:
// - getDocWithSuggestionFallback は googleapis の docs クライアント（呼び出し側で初期化）を受け取る
//   → このモジュール自体は Google API 認証を持たない（テスタブルで結合度低）
// - 提案モードビュー (PREVIEW_SUGGESTIONS_ACCEPTED) は commenter+ 権限が必要。
//   viewer 権限しかない Doc では通常モードにフォールバックする。

const HEADING_PREFIX = {
  HEADING_1: "# ",
  HEADING_2: "## ",
  HEADING_3: "### ",
  HEADING_4: "#### ",
  HEADING_5: "##### ",
  HEADING_6: "###### ",
  TITLE: "# ",
  SUBTITLE: "## ",
};

// =================================================================
// 公開 API
// =================================================================

export function extractDocId(url) {
  const m = url.match(/\/d\/([a-zA-Z0-9_-]+)/);
  return m ? m[1] : null;
}

export async function getDocWithSuggestionFallback(docs, documentId) {
  try {
    const r = await docs.documents.get({
      documentId,
      includeTabsContent: true,
      suggestionsViewMode: "PREVIEW_SUGGESTIONS_ACCEPTED",
    });
    return { data: r.data, mode: "PREVIEW_SUGGESTIONS_ACCEPTED" };
  } catch (e) {
    const msg = e?.errors?.[0]?.message || e?.message || "";
    if (e?.code === 403 || /permission|suggestion/i.test(msg)) {
      const r = await docs.documents.get({ documentId, includeTabsContent: true });
      return { data: r.data, mode: "DEFAULT_FOR_CURRENT_ACCESS", fallback: true };
    }
    throw e;
  }
}

export function docToMarkdown(doc) {
  // inline image は ![imageN] のプレースホルダーで位置だけ残す。
  // 画像バイナリ自体は取り込まず、運用側（LINE 配信ツール等）で都度貼る前提。
  // カウンタは doc 全体で連番にしたいので docToMarkdown スコープでリセット。
  imageCounter = 0;

  const tabs = doc.tabs;
  const segments = [];
  if (tabs?.length) {
    for (const tab of flattenTabs(tabs)) {
      const props = tab.tabProperties;
      const tabContent = tab.documentTab?.body?.content ?? [];
      if (tabs.length > 1 && props?.title) {
        segments.push(`<!-- tab: ${props.title} -->\n`);
      }
      segments.push(contentToMarkdown(tabContent, doc.lists));
    }
  } else {
    segments.push(contentToMarkdown(doc.body?.content ?? [], doc.lists));
  }
  return segments.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

let imageCounter = 0;

// =================================================================
// 内部ヘルパー
// =================================================================

function flattenTabs(tabs) {
  const out = [];
  for (const tab of tabs) {
    out.push(tab);
    if (tab.childTabs?.length) out.push(...flattenTabs(tab.childTabs));
  }
  return out;
}

function contentToMarkdown(content, lists) {
  const out = [];
  for (const el of content) {
    if (el.paragraph) {
      out.push(paragraphToMarkdown(el.paragraph, lists));
    } else if (el.table) {
      out.push(tableToMarkdown(el.table, lists));
    }
  }
  return out.filter((s) => s !== null).join("\n");
}

function paragraphToMarkdown(para, lists) {
  const style = para.paragraphStyle?.namedStyleType;
  const prefix = HEADING_PREFIX[style] ?? "";

  let text = "";
  for (const run of para.elements ?? []) {
    if (run.textRun) {
      text += textRunToMarkdown(run.textRun);
    } else if (run.richLink?.richLinkProperties) {
      const props = run.richLink.richLinkProperties;
      text += `[${props.title || props.uri}](${props.uri})`;
    } else if (run.inlineObjectElement) {
      imageCounter++;
      text += `![image${imageCounter}]`;
    }
  }
  text = text.replace(/\n$/, "");
  if (!text.trim()) return "";

  const bullet = para.bullet;
  if (bullet) {
    const nesting = bullet.nestingLevel || 0;
    const indent = "  ".repeat(nesting);
    const glyph = guessListGlyph(bullet, lists);
    return `${indent}${glyph} ${text}`;
  }

  if (prefix) return `\n${prefix}${text}\n`;
  return text;
}

function textRunToMarkdown(run) {
  let t = normalizeDocText(run.content || "");
  if (!t) return "";
  const style = run.textStyle || {};
  const link = style.link?.url;
  const trimmedNewline = t.endsWith("\n");
  let body = trimmedNewline ? t.slice(0, -1) : t;

  if (body.trim()) {
    if (style.bold) body = `**${body}**`;
    if (style.italic) body = `*${body}*`;
    if (link) body = `[${body}](${link})`;
  }
  return trimmedNewline ? body + "\n" : body;
}

function guessListGlyph(bullet, lists) {
  const listId = bullet.listId;
  const list = listId && lists?.[listId];
  const level = list?.listProperties?.nestingLevels?.[bullet.nestingLevel || 0];
  const glyphFmt = level?.glyphFormat;
  if (glyphFmt && /%\d+/.test(glyphFmt)) return "1.";
  return "-";
}

function tableToMarkdown(table, lists) {
  // Google Docs の Code Block は「1×1 / 背景がほぼ均一なグレー」のテーブルで表現される。
  // これを通常の markdown table に変換すると改行がスペースに潰れてしまうため、
  // 検出した場合は ``` フェンスで包んで改行を保持する。
  if (isCodeBlockTable(table)) {
    return tableToCodeBlock(table, lists);
  }

  const rows = [];
  for (const row of table.tableRows ?? []) {
    const cells = [];
    for (const cell of row.tableCells ?? []) {
      const cellText = contentToMarkdown(cell.content ?? [], lists)
        .replace(/\n+/g, " ")
        .replace(/\|/g, "\\|")
        .trim();
      cells.push(cellText || " ");
    }
    rows.push(cells);
  }
  if (!rows.length) return "";
  const colCount = Math.max(...rows.map((r) => r.length));
  const md = [];
  md.push("| " + rows[0].concat(Array(colCount - rows[0].length).fill("")).join(" | ") + " |");
  md.push("| " + Array(colCount).fill("---").join(" | ") + " |");
  for (const row of rows.slice(1)) {
    md.push("| " + row.concat(Array(colCount - row.length).fill("")).join(" | ") + " |");
  }
  return "\n" + md.join("\n") + "\n";
}

function isCodeBlockTable(table) {
  const rows = table.tableRows ?? [];
  if (rows.length !== 1) return false;
  const cells = rows[0].tableCells ?? [];
  if (cells.length !== 1) return false;
  const bg = cells[0].tableCellStyle?.backgroundColor?.color?.rgbColor;
  return isGreyBackground(bg);
}

function isGreyBackground(rgb) {
  if (!rgb) return false;
  const r = rgb.red ?? 0;
  const g = rgb.green ?? 0;
  const b = rgb.blue ?? 0;
  // 各チャンネルが 0.85〜0.97 かつほぼ均一（無彩色）= 薄いグレー = Code Block 背景
  const inRange = (v) => v >= 0.85 && v <= 0.97;
  if (!inRange(r) || !inRange(g) || !inRange(b)) return false;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  return max - min < 0.03;
}

function tableToCodeBlock(table, lists) {
  const cell = table.tableRows[0].tableCells[0];
  // contentToMarkdown は paragraph を "\n" で join するので、改行構造が保たれる。
  // ただし bold/italic/link 装飾が markdown で混ざると ``` の中で生で出てしまうため、
  // 装飾を捨てた素のテキスト抽出に切り替える。
  const text = extractPlainText(cell.content ?? []).replace(/\n+$/, "");
  return "\n```\n" + text + "\n```\n";
}

function extractPlainText(content) {
  const parts = [];
  for (const el of content) {
    if (!el.paragraph) continue;
    let line = "";
    for (const run of el.paragraph.elements ?? []) {
      if (run.textRun) {
        line += normalizeDocText(run.textRun.content || "");
      } else if (run.richLink?.richLinkProperties) {
        line += run.richLink.richLinkProperties.title || run.richLink.richLinkProperties.uri || "";
      } else if (run.inlineObjectElement) {
        imageCounter++;
        line += `![image${imageCounter}]`;
      }
    }
    line = line.replace(/\n$/, "");
    parts.push(line);
  }
  return parts.join("\n");
}

function normalizeDocText(text) {
  // Google Docs API returns soft line breaks as vertical tabs in some documents.
  return text.replace(/\v/g, "\n");
}
