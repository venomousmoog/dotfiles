/**
 * Better Paste from Markdown for Google Docs
 *
 * Two usage modes:
 *   1. Sidebar: Markdown menu > Paste from Markdown (or run showSidebar)
 *   2. Whole-doc: Paste markdown into doc, run formatMarkdown from editor
 *
 * Heading remapping:  # -> Title, ## -> H1, ### -> H2, etc.
 * Inline code:        Courier New with highlighted background
 * Code blocks:        Tight spacing in a shaded single-cell table
 * Tables:             Formatted headers, proportional column widths, tight spacing
 * Also supports:      bold, italic, strikethrough, links, lists, blockquotes
 */

// ── Configuration ──────────────────────────────────────────────────

var CONFIG = {
  CODE_FONT:         'JetBrains Mono',
  CODE_FONT_SIZE:    10,
  CODE_BG:           '#fdf7ee',
  CODE_FG:           '#333333',
  CODE_BORDER:       '#dddddd',

  INLINE_CODE_BG:    null,
  INLINE_CODE_FG:    '#006400',

  BLOCKQUOTE_BG:     '#f7f7f7',
  BLOCKQUOTE_BORDER: '#008080',
  BLOCKQUOTE_FG:     '#333333',

  TABLE_HEADER_BG:   '#2C3E50',
  TABLE_HEADER_FG:   '#eeeeee',
  TABLE_ALT_ROW_BG:  '#fffaf5',
  TABLE_BORDER:      '#000000',
  TABLE_BORDER_WIDTH: 1,

  PAGE_WIDTH_PT:     468  // 6.5 inches at 72 pt/in (letter, 1" margins)
};

var HEADING_MAP = {};
HEADING_MAP[1] = DocumentApp.ParagraphHeading.TITLE;
HEADING_MAP[2] = DocumentApp.ParagraphHeading.HEADING1;
HEADING_MAP[3] = DocumentApp.ParagraphHeading.HEADING2;
HEADING_MAP[4] = DocumentApp.ParagraphHeading.HEADING3;
HEADING_MAP[5] = DocumentApp.ParagraphHeading.HEADING4;
HEADING_MAP[6] = DocumentApp.ParagraphHeading.HEADING5;

// ── Menu & UI ──────────────────────────────────────────────────────

function onOpen(e) {
  try {
    DocumentApp.getUi()
      .createMenu('Markdown')
      .addItem('Paste from Markdown\u2026', 'showSidebar')
      .addToUi();
  } catch (err) {
    Logger.log('onOpen: could not create menu: ' + err);
  }
}

function showSidebar() {
  var html = HtmlService.createHtmlOutputFromFile('Sidebar')
    .setTitle('Paste Markdown');
  DocumentApp.getUi().showSidebar(html);
}

// ── Entry Points ───────────────────────────────────────────────────

function getDefaultFontSize_(body) {
  var attrs = body.getAttributes();
  if (attrs[DocumentApp.Attribute.FONT_SIZE]) {
    return attrs[DocumentApp.Attribute.FONT_SIZE];
  }
  for (var i = 0; i < Math.min(body.getNumChildren(), 10); i++) {
    var child = body.getChild(i);
    if (child.getType() === DocumentApp.ElementType.PARAGRAPH) {
      var text = child.editAsText();
      if (text.getText().length > 0) {
        var size = text.getFontSize(0);
        if (size) return size;
      }
    }
  }
  return 11;
}

// Called from the sidebar
function insertMarkdown(markdown, options) {
  var extraLineBreaks = options && options.extraLineBreaks;

  // Merge any sidebar overrides into CONFIG
  if (options && options.styles) {
    var s = options.styles;
    if (s.CODE_FONT)         CONFIG.CODE_FONT         = s.CODE_FONT;
    if (s.CODE_BG)           CONFIG.CODE_BG           = s.CODE_BG;
    if (s.CODE_FG)           CONFIG.CODE_FG           = s.CODE_FG;
    if (s.INLINE_CODE_FG)    CONFIG.INLINE_CODE_FG    = s.INLINE_CODE_FG;
    if (s.TABLE_HEADER_BG)   CONFIG.TABLE_HEADER_BG   = s.TABLE_HEADER_BG;
    if (s.TABLE_HEADER_FG)   CONFIG.TABLE_HEADER_FG   = s.TABLE_HEADER_FG;
    if (s.TABLE_ALT_ROW_BG)  CONFIG.TABLE_ALT_ROW_BG  = s.TABLE_ALT_ROW_BG;
    if (s.TABLE_BORDER)      CONFIG.TABLE_BORDER      = s.TABLE_BORDER;
    if (s.BLOCKQUOTE_BG)     CONFIG.BLOCKQUOTE_BG     = s.BLOCKQUOTE_BG;
    if (s.BLOCKQUOTE_BORDER) CONFIG.BLOCKQUOTE_BORDER = s.BLOCKQUOTE_BORDER;
  }

  var doc = DocumentApp.getActiveDocument();
  var body = doc.getBody();

  // Set code font size to 1pt less than the document's Normal style
  CONFIG.CODE_FONT_SIZE = getDefaultFontSize_(body) - 1;

  var index = getInsertionIndex_(doc, body);
  var blocks = parseMarkdown_(markdown);

  for (var i = 0; i < blocks.length; i++) {
    index = insertBlock_(body, blocks[i], index);

    if (i < blocks.length - 1) {
      var nextType = blocks[i + 1].type;
      var curType = blocks[i].type;

      // After a table, insert a spacer if the next block is a normal paragraph
      // so the text doesn't sit flush against the table border
      var tableBeforeParagraph = (curType === 'table' || curType === 'code' || curType === 'blockquote')
        && nextType === 'paragraph';

      if (extraLineBreaks || tableBeforeParagraph) {
        var spacer = body.insertParagraph(index, '');
        index++;
      }
    }
  }
}

// Alternative: reads entire doc body as markdown, reformats in place.
// Run from the Apps Script editor if the sidebar/menu is unavailable.
function formatMarkdown() {
  var doc = DocumentApp.getActiveDocument();
  var body = doc.getBody();

  var markdown = body.getText();
  if (!markdown || markdown.trim() === '') {
    Logger.log('Document is empty.');
    return;
  }

  // Set code font size to 1pt less than the document's Normal style
  CONFIG.CODE_FONT_SIZE = getDefaultFontSize_(body) - 1;

  var blocks = parseMarkdown_(markdown);
  body.clear();

  var index = 0;
  for (var i = 0; i < blocks.length; i++) {
    index = insertBlock_(body, blocks[i], index);
  }

  // Remove the leading empty paragraph left by clear()
  if (body.getNumChildren() > 1) {
    var first = body.getChild(0);
    if (first.getType() === DocumentApp.ElementType.PARAGRAPH &&
        first.asParagraph().getText() === '') {
      body.removeChild(first);
    }
  }

  Logger.log('Formatted ' + blocks.length + ' blocks.');
}

function getInsertionIndex_(doc, body) {
  var cursor = doc.getCursor();
  if (cursor) {
    var el = cursor.getElement();
    while (el && el.getParent() !== body) {
      el = el.getParent();
    }
    if (el) {
      return body.getChildIndex(el) + 1;
    }
  }
  return body.getNumChildren();
}

// ── Block-Level Parser ─────────────────────────────────────────────

function parseMarkdown_(md) {
  var lines = md.split('\n');
  var blocks = [];
  var i = 0;

  while (i < lines.length) {
    var line = lines[i];

    // Fenced code block
    if (/^```/.test(line)) {
      var lang = line.replace(/^```/, '').trim();
      var code = [];
      i++;
      while (i < lines.length && !/^```\s*$/.test(lines[i])) {
        code.push(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      blocks.push({ type: 'code', content: code.join('\n'), language: lang });
      continue;
    }

    // Heading
    var hm = line.match(/^(#{1,6})\s+(.*)/);
    if (hm) {
      var content = hm[2].replace(/\s*#+\s*$/, '');
      blocks.push({ type: 'heading', level: hm[1].length, content: content });
      i++;
      continue;
    }

    // Horizontal rule (must come before list check)
    if (/^[\-\*_]{3,}\s*$/.test(line) && !/^[\-\*]\s+/.test(line)) {
      blocks.push({ type: 'hr' });
      i++;
      continue;
    }

    // Table
    if (/^\|/.test(line)) {
      var tableLines = [];
      while (i < lines.length && /^\|/.test(lines[i])) {
        tableLines.push(lines[i]);
        i++;
      }
      blocks.push({ type: 'table', lines: tableLines });
      continue;
    }

    // Blockquote
    if (/^>\s?/.test(line)) {
      var quoteLines = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) {
        quoteLines.push(lines[i].replace(/^>\s?/, ''));
        i++;
      }
      blocks.push({ type: 'blockquote', content: quoteLines.join(' ') });
      continue;
    }

    // Unordered list
    if (/^[\-\*]\s+/.test(line)) {
      var items = [];
      while (i < lines.length && /^[\-\*]\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^[\-\*]\s+/, ''));
        i++;
      }
      blocks.push({ type: 'ul', items: items });
      continue;
    }

    // Ordered list
    if (/^\d+\.\s+/.test(line)) {
      var items = [];
      while (i < lines.length && /^\d+\.\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\d+\.\s+/, ''));
        i++;
      }
      blocks.push({ type: 'ol', items: items });
      continue;
    }

    // Blank line
    if (line.trim() === '') {
      i++;
      continue;
    }

    // Paragraph — consecutive non-blank, non-special lines
    var pLines = [];
    while (i < lines.length &&
           lines[i].trim() !== '' &&
           !/^#{1,6}\s/.test(lines[i]) &&
           !/^```/.test(lines[i]) &&
           !/^\|/.test(lines[i]) &&
           !/^>\s?/.test(lines[i]) &&
           !/^[\-\*]\s+/.test(lines[i]) &&
           !/^\d+\.\s+/.test(lines[i]) &&
           !/^[\-\*_]{3,}\s*$/.test(lines[i])) {
      pLines.push(lines[i]);
      i++;
    }
    blocks.push({ type: 'paragraph', content: pLines.join(' ') });
  }

  return blocks;
}

// ── Block Inserters ────────────────────────────────────────────────

function insertBlock_(body, block, index) {
  switch (block.type) {
    case 'heading':    return insertHeading_(body, block, index);
    case 'paragraph':  return insertParagraph_(body, block, index);
    case 'code':       return insertCodeBlock_(body, block, index);
    case 'table':      return insertTable_(body, block, index);
    case 'ul':         return insertList_(body, block, index, false);
    case 'ol':         return insertList_(body, block, index, true);
    case 'blockquote': return insertBlockquote_(body, block, index);
    case 'hr':         return insertHR_(body, index);
    default:           return index;
  }
}

function insertHeading_(body, block, index) {
  var para = body.insertParagraph(index, '');
  para.setHeading(HEADING_MAP[block.level] || DocumentApp.ParagraphHeading.HEADING5);
  applyInlineFormatting_(para, block.content);
  return index + 1;
}

function insertParagraph_(body, block, index) {
  var para = body.insertParagraph(index, '');
  applyInlineFormatting_(para, block.content);
  // Clear explicit spacing so the Normal named style takes effect
  var attrs = {};
  attrs[DocumentApp.Attribute.SPACING_AFTER] = null;
  attrs[DocumentApp.Attribute.SPACING_BEFORE] = null;
  para.setAttributes(attrs);
  return index + 1;
}

function insertCodeBlock_(body, block, index) {
  // Single-cell table gives us background color containment and tight spacing
  var table = body.insertTable(index, [['']]);
  var cell = table.getCell(0, 0);
  cell.setBackgroundColor(CONFIG.CODE_BG);
  cell.setPaddingTop(6);
  cell.setPaddingBottom(6);
  cell.setPaddingLeft(8);
  cell.setPaddingRight(8);

  var lines = block.content.split('\n');

  // First line goes into the existing paragraph
  var firstPara = cell.getChild(0).asParagraph();
  firstPara.setText(lines.length > 0 ? lines[0] : '');
  formatCodePara_(firstPara);

  for (var i = 1; i < lines.length; i++) {
    var para = cell.appendParagraph(lines[i]);
    formatCodePara_(para);
  }

  table.setBorderColor(CONFIG.CODE_BORDER);
  table.setBorderWidth(0.5);
  table.setColumnWidth(0, CONFIG.PAGE_WIDTH_PT);

  return index + 1;
}

function formatCodePara_(para) {
  var text = para.editAsText();
  text.setFontFamily(CONFIG.CODE_FONT);
  text.setFontSize(CONFIG.CODE_FONT_SIZE);
  text.setForegroundColor(CONFIG.CODE_FG);
  para.setSpacingBefore(0);
  para.setSpacingAfter(0);
  para.setLineSpacing(1.15);
}

function insertTable_(body, block, index) {
  var parsed = parseTableData_(block.lines);
  if (parsed.rows.length === 0) return index;

  var numCols = parsed.rows[0].length;

  // Create table with raw cell text (will be replaced by applyInlineFormatting_)
  var table = body.insertTable(index, parsed.rows);

  // Column widths: use sqrt scaling to balance short vs long columns.
  // Pure proportional over-penalizes short columns; sqrt dampens the ratio
  // so short columns stay readable while long columns get more room.
  var maxLens = [];
  for (var j = 0; j < numCols; j++) {
    var mx = 0;
    for (var r = 0; r < parsed.rows.length; r++) {
      if (j < parsed.rows[r].length) {
        mx = Math.max(mx, parsed.rows[r][j].length);
      }
    }
    maxLens.push(Math.max(mx, 2));
  }

  var scaledLens = [];
  var totalScaled = 0;
  for (var j = 0; j < numCols; j++) {
    var s = Math.sqrt(maxLens[j]);
    scaledLens.push(s);
    totalScaled += s;
  }

  var minWidth = Math.max(30, Math.floor(CONFIG.PAGE_WIDTH_PT / (numCols * 3)));
  var rawWidths = [];
  var rawTotal = 0;
  for (var j = 0; j < numCols; j++) {
    var w = Math.max(minWidth, scaledLens[j] / totalScaled * CONFIG.PAGE_WIDTH_PT);
    rawWidths.push(w);
    rawTotal += w;
  }
  // Normalize so columns sum to exactly PAGE_WIDTH_PT (fills the page)
  var assigned = 0;
  for (var j = 0; j < numCols - 1; j++) {
    var w = Math.round(rawWidths[j] / rawTotal * CONFIG.PAGE_WIDTH_PT);
    table.setColumnWidth(j, w);
    assigned += w;
  }
  table.setColumnWidth(numCols - 1, CONFIG.PAGE_WIDTH_PT - assigned);

  // Format each cell
  for (var r = 0; r < table.getNumRows(); r++) {
    var row = table.getRow(r);
    for (var c = 0; c < row.getNumCells(); c++) {
      var cell = row.getCell(c);
      var para = cell.getChild(0).asParagraph();

      // Replace raw markdown with formatted text
      applyInlineFormatting_(para, parsed.rows[r][c]);

      // Header row
      if (r === 0) {
        cell.setBackgroundColor(CONFIG.TABLE_HEADER_BG);
        para.editAsText().setBold(true);
        para.editAsText().setForegroundColor(CONFIG.TABLE_HEADER_FG);
      } else {
        cell.setBackgroundColor(r % 2 === 0 ? CONFIG.TABLE_ALT_ROW_BG : '#ffffff');
      }

      // Column alignment from separator row
      if (parsed.alignments && c < parsed.alignments.length) {
        if (parsed.alignments[c] === 'CENTER') {
          para.setAlignment(DocumentApp.HorizontalAlignment.CENTER);
        } else if (parsed.alignments[c] === 'RIGHT') {
          para.setAlignment(DocumentApp.HorizontalAlignment.RIGHT);
        } else {
          para.setAlignment(DocumentApp.HorizontalAlignment.LEFT);
        }
      }

      // Tight spacing
      para.setSpacingBefore(1);
      para.setSpacingAfter(1);
      cell.setPaddingTop(3);
      cell.setPaddingBottom(3);
      cell.setPaddingLeft(5);
      cell.setPaddingRight(5);
    }
  }

  table.setBorderColor(CONFIG.TABLE_BORDER);
  table.setBorderWidth(CONFIG.TABLE_BORDER_WIDTH);

  return index + 1;
}

function insertList_(body, block, index, ordered) {
  var glyphType = ordered
    ? DocumentApp.GlyphType.NUMBER
    : DocumentApp.GlyphType.BULLET;

  for (var i = 0; i < block.items.length; i++) {
    var item = body.insertListItem(index, '');
    item.setGlyphType(glyphType);
    applyInlineFormatting_(item, block.items[i]);
    item.setSpacingBefore(0);
    if (i < block.items.length - 1) {
      // Tight spacing between list items
      item.setSpacingAfter(0);
    } else {
      // Last item: clear explicit spacing so Normal style takes effect
      var attrs = {};
      attrs[DocumentApp.Attribute.SPACING_AFTER] = null;
      item.setAttributes(attrs);
    }
    index++;
  }

  return index;
}

function insertBlockquote_(body, block, index) {
  // Two-column table: narrow teal border cell + content cell with gray background
  var table = body.insertTable(index, [['\u200B', '']]);

  // Border cell (simulates left border)
  var borderCell = table.getCell(0, 0);
  borderCell.setBackgroundColor(CONFIG.BLOCKQUOTE_BORDER);
  borderCell.setPaddingTop(0);
  borderCell.setPaddingBottom(0);
  borderCell.setPaddingLeft(0);
  borderCell.setPaddingRight(0);

  // Content cell
  var contentCell = table.getCell(0, 1);
  contentCell.setBackgroundColor(CONFIG.BLOCKQUOTE_BG);
  contentCell.setPaddingTop(6);
  contentCell.setPaddingBottom(6);
  contentCell.setPaddingLeft(10);
  contentCell.setPaddingRight(10);
  var para = contentCell.getChild(0).asParagraph();
  applyInlineFormatting_(para, block.content);
  para.editAsText().setForegroundColor(CONFIG.BLOCKQUOTE_FG);

  // Column widths: 2pt border + rest for content
  table.setColumnWidth(0, 2);
  table.setColumnWidth(1, CONFIG.PAGE_WIDTH_PT - 2);
  table.setBorderWidth(0);

  return index + 1;
}

function insertHR_(body, index) {
  var ruler = '';
  for (var k = 0; k < 72; k++) ruler += '\u2500';
  var para = body.insertParagraph(index, ruler);
  para.setAlignment(DocumentApp.HorizontalAlignment.CENTER);
  para.editAsText().setForegroundColor('#cccccc');
  para.editAsText().setFontSize(6);
  para.setSpacingBefore(4);
  para.setSpacingAfter(4);
  return index + 1;
}

// ── Table Data Parser ──────────────────────────────────────────────

function parseTableData_(lines) {
  var allRows = [];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (line.charAt(0) === '|') line = line.substring(1);
    if (line.charAt(line.length - 1) === '|') line = line.substring(0, line.length - 1);
    var cells = line.split('|');
    for (var j = 0; j < cells.length; j++) cells[j] = cells[j].trim();
    allRows.push(cells);
  }

  // Find separator row and extract alignments
  var alignments = null;
  var dataRows = [];

  for (var i = 0; i < allRows.length; i++) {
    var isSep = true;
    for (var j = 0; j < allRows[i].length; j++) {
      if (!/^:?[\-]+:?$/.test(allRows[i][j])) { isSep = false; break; }
    }
    if (isSep && allRows[i].length > 0) {
      alignments = [];
      for (var j = 0; j < allRows[i].length; j++) {
        var c = allRows[i][j];
        if (c.charAt(0) === ':' && c.charAt(c.length - 1) === ':') {
          alignments.push('CENTER');
        } else if (c.charAt(c.length - 1) === ':') {
          alignments.push('RIGHT');
        } else {
          alignments.push('LEFT');
        }
      }
    } else {
      dataRows.push(allRows[i]);
    }
  }

  // Normalize column count
  var numCols = 0;
  for (var i = 0; i < dataRows.length; i++) {
    numCols = Math.max(numCols, dataRows[i].length);
  }
  for (var i = 0; i < dataRows.length; i++) {
    while (dataRows[i].length < numCols) dataRows[i].push('');
  }

  return { rows: dataRows, alignments: alignments };
}

// ── Inline Markdown Parser ─────────────────────────────────────────

function parseInline_(text) {
  // Phase 1: split out inline code spans (backticks are unambiguous delimiters)
  var codeParts = splitByCode_(text);
  var segments = [];

  for (var i = 0; i < codeParts.length; i++) {
    if (codeParts[i].code) {
      segments.push({
        text: codeParts[i].text,
        bold: false, italic: false, strike: false, code: true, link: null
      });
    } else {
      var inner = parseFormattingAndLinks_(codeParts[i].text);
      for (var j = 0; j < inner.length; j++) segments.push(inner[j]);
    }
  }

  return segments;
}

function splitByCode_(text) {
  var parts = [];
  var re = /`([^`]+)`/g;
  var last = 0;
  var m;

  while ((m = re.exec(text)) !== null) {
    if (m.index > last) {
      parts.push({ text: text.substring(last, m.index), code: false });
    }
    parts.push({ text: m[1], code: true });
    last = re.lastIndex;
  }
  if (last < text.length) {
    parts.push({ text: text.substring(last), code: false });
  }

  return parts;
}

function parseFormattingAndLinks_(text) {
  var segments = [];
  // Order: bold-italic before bold before italic; images before links
  var re = /(\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|\*(.+?)\*|~~(.+?)~~|!\[([^\]]*)\]\([^)]+\)|\[([^\]]+)\]\(([^)]+)\))/g;
  var last = 0;
  var m;

  while ((m = re.exec(text)) !== null) {
    if (m.index > last) {
      segments.push(plainSeg_(text.substring(last, m.index)));
    }

    if (m[2] !== undefined) {
      segments.push({ text: m[2], bold: true, italic: true, strike: false, code: false, link: null });
    } else if (m[3] !== undefined) {
      segments.push({ text: m[3], bold: true, italic: false, strike: false, code: false, link: null });
    } else if (m[4] !== undefined) {
      segments.push({ text: m[4], bold: false, italic: true, strike: false, code: false, link: null });
    } else if (m[5] !== undefined) {
      segments.push({ text: m[5], bold: false, italic: false, strike: true, code: false, link: null });
    } else if (m[6] !== undefined) {
      segments.push(plainSeg_('[image: ' + m[6] + ']'));
    } else if (m[7] !== undefined) {
      segments.push({ text: m[7], bold: false, italic: false, strike: false, code: false, link: m[8] });
    }

    last = re.lastIndex;
  }

  if (last < text.length) {
    segments.push(plainSeg_(text.substring(last)));
  }
  if (segments.length === 0 && text.length > 0) {
    segments.push(plainSeg_(text));
  }

  return segments;
}

function plainSeg_(text) {
  return { text: text, bold: false, italic: false, strike: false, code: false, link: null };
}

// ── Formatting Application ─────────────────────────────────────────

function applyInlineFormatting_(element, markdownText) {
  var segments = parseInline_(markdownText);
  var fullText = '';
  for (var i = 0; i < segments.length; i++) fullText += segments[i].text;

  element.setText(fullText);
  if (fullText.length === 0) return;

  var textEl = element.editAsText();
  var offset = 0;

  for (var i = 0; i < segments.length; i++) {
    var seg = segments[i];
    if (seg.text.length === 0) continue;
    var start = offset;
    var end = offset + seg.text.length - 1;
    offset += seg.text.length;

    if (seg.bold)   textEl.setBold(start, end, true);
    if (seg.italic) textEl.setItalic(start, end, true);
    if (seg.strike) textEl.setStrikethrough(start, end, true);

    if (seg.code) {
      textEl.setFontFamily(start, end, CONFIG.CODE_FONT);
      textEl.setFontSize(start, end, CONFIG.CODE_FONT_SIZE);
      if (CONFIG.INLINE_CODE_BG) {
        textEl.setBackgroundColor(start, end, CONFIG.INLINE_CODE_BG);
      }
      textEl.setForegroundColor(start, end, CONFIG.INLINE_CODE_FG);
    }

    if (seg.link) {
      textEl.setLinkUrl(start, end, seg.link);
    }
  }
}
