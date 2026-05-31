import fs from "node:fs";

const contentPath = "public/content.html";
const fallbackPath = "app/src/main/assets/fallback.html";

const payloadPath = process.argv[2];
if (!payloadPath) {
  throw new Error("Usage: node scripts/update-tradepedia-entry.mjs payload.json");
}

const payload = JSON.parse(fs.readFileSync(payloadPath, "utf8"));
validatePayload(payload);

const sourceHtml = fs.readFileSync(contentPath, "utf8");
const result = updateTradepediaHtml(sourceHtml, payload);

fs.writeFileSync(contentPath, result.html, "utf8");
fs.writeFileSync(fallbackPath, result.html, "utf8");

console.log(JSON.stringify({
  ok: true,
  action: result.action,
  id: result.entry.id,
  title: result.entry.title,
  count: result.count
}, null, 2));

function updateTradepediaHtml(html, payload) {
  const dataMatch = html.match(/<script id="pageData" type="application\/json">([\s\S]*?)<\/script>/);
  if (!dataMatch) throw new Error("pageData script block was not found.");

  const pages = JSON.parse(dataMatch[1]);
  const entry = buildEntry(payload);
  const existingIndex = pages.findIndex(page => page.id === entry.id);

  let action = "added";
  if (existingIndex >= 0) {
    if (payload.replaceExisting === false) {
      throw new Error(`Entry already exists: ${entry.id}`);
    }
    pages[existingIndex] = entry;
    action = "updated";
  } else {
    pages.push(entry);
    pages.sort((a, b) => a.title.localeCompare(b.title, "tr"));
  }

  const nextData = `<script id="pageData" type="application/json">${JSON.stringify(pages)}</script>`;
  let nextHtml = html.replace(dataMatch[0], nextData);
  nextHtml = upsertNavButton(nextHtml, entry);
  nextHtml = updateCounts(nextHtml, pages.length);

  return { html: nextHtml, entry, action, count: pages.length };
}

function buildEntry(payload) {
  const id = slugify(payload.id || payload.title);
  const title = cleanText(payload.title);
  const kind = cleanText(payload.kind);
  const category = cleanText(payload.category);
  const level = cleanText(payload.level || "Başlangıç");
  const tags = Array.isArray(payload.tags) ? payload.tags.map(cleanText).filter(Boolean) : [];
  const related = Array.isArray(payload.related) ? payload.related.map(cleanText).filter(Boolean) : [];

  const html = [
    `<article class="entry" id="${escapeAttr(id)}">`,
    `<div class="crumb"><a href="#top">Ana sayfa</a> › <a href="#index">Tüm maddeler</a> › ${escapeHtml(title)}</div>`,
    `<h2>${escapeHtml(title)}</h2>`,
    `<div class="meta"><span>${escapeHtml(kind)}</span><span>${escapeHtml(category)}</span><span>${escapeHtml(level)}</span>${tags.map(tag => `<span>${escapeHtml(tag)}</span>`).join("")}</div>`,
    `<p class="summary">${paragraphText(payload.summary)}</p>`,
    section(id, "tanim", "Tanım", payload.body),
    payload.usage ? section(id, "kullanim", "Nasıl kullanılır?", payload.usage) : "",
    payload.pitfalls ? section(id, "tuzak", "Yanlış kullanım", payload.pitfalls) : "",
    payload.botNote ? section(id, "bot", "Bot / backtest notu", payload.botNote) : "",
    related.length ? relatedSection(id, related) : "",
    `</article>`
  ].join("");

  return { id, title, kind, category, html };
}

function section(id, suffix, heading, text) {
  return `<section id="${escapeAttr(id)}-${suffix}"><h3>${escapeHtml(heading)}</h3>${paragraphs(text)}</section>`;
}

function relatedSection(id, related) {
  const links = related.map(item => {
    const href = slugify(item);
    return `<a href="#${escapeAttr(href)}">${escapeHtml(item)}</a>`;
  }).join(" · ");
  return `<section id="${escapeAttr(id)}-ilgili"><h3>Bağlantılı maddeler</h3><div class="related">${links}</div></section>`;
}

function paragraphs(text) {
  return String(text || "")
    .split(/\n{2,}/)
    .map(paragraphText)
    .filter(Boolean)
    .map(part => `<p>${part}</p>`)
    .join("");
}

function paragraphText(text) {
  return escapeHtml(cleanText(text)).replace(/\n/g, "<br>");
}

function upsertNavButton(html, entry) {
  const button = `<button class="nav-item" data-id="${escapeAttr(entry.id)}"><span>${escapeHtml(entry.title)}</span><small>${escapeHtml(entry.kind)} · ${escapeHtml(entry.category)}</small></button>`;
  const existingButton = new RegExp(`<button class="nav-item" data-id="${escapeRegExp(entry.id)}">[\\s\\S]*?<\\/button>`);
  if (existingButton.test(html)) return html.replace(existingButton, button);

  const navMatch = html.match(/(<div class="nav-list" id="navList">)([\s\S]*?)(<\/div>\s*<\/aside>)/);
  if (!navMatch) throw new Error("navList block was not found.");
  return html.replace(navMatch[0], `${navMatch[1]}${navMatch[2]}${button}${navMatch[3]}`);
}

function updateCounts(html, count) {
  return html
    .replace(/\d+\s+madde/g, `${count} madde`)
    .replace(/Toplam\s+\d+\s+madde/g, `Toplam ${count} madde`);
}

function validatePayload(payload) {
  for (const field of ["title", "kind", "category", "summary", "body"]) {
    if (!payload || typeof payload[field] !== "string" || !payload[field].trim()) {
      throw new Error(`Missing required field: ${field}`);
    }
  }
}

function cleanText(value) {
  return String(value || "").trim().replace(/[ \t]+/g, " ");
}

function slugify(value) {
  return String(value || "")
    .toLocaleLowerCase("tr")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\u0131/g, "i")
    .replace(/\u011f/g, "g")
    .replace(/\u00fc/g, "u")
    .replace(/\u015f/g, "s")
    .replace(/\u00f6/g, "o")
    .replace(/\u00e7/g, "c")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/'/g, "&#39;");
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
