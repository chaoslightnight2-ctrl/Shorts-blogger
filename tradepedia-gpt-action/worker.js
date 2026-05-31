const CONTENT_PATH = "public/content.html";
const FALLBACK_PATH = "app/src/main/assets/fallback.html";
const CONTENT_URL = "https://chaoslightnight2-ctrl.github.io/Shorts-blogger/content.html";

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/health") {
        return json({ ok: true });
      }

      if (request.method === "POST" && url.pathname === "/entries") {
        authorize(request, env);
        const payload = await request.json();
        const result = await addOrUpdateEntry(payload, env);
        return json(result);
      }

      return json({ ok: false, error: "Not found" }, 404);
    } catch (error) {
      const status = Number(error.status || 500);
      return json({ ok: false, error: error.message || "Internal error" }, status);
    }
  }
};

function authorize(request, env) {
  const expected = env.TRADEPEDIA_ACTION_SECRET;
  if (!expected) throw httpError(500, "TRADEPEDIA_ACTION_SECRET is not configured.");

  const auth = request.headers.get("authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token || token !== expected) throw httpError(401, "Invalid bearer token.");
}

async function addOrUpdateEntry(payload, env) {
  validatePayload(payload);

  const owner = env.GITHUB_OWNER || "chaoslightnight2-ctrl";
  const repo = env.GITHUB_REPO || "Shorts-blogger";
  const branch = env.GITHUB_BRANCH || "main";
  const token = env.GITHUB_TOKEN;
  if (!token) throw httpError(500, "GITHUB_TOKEN is not configured.");

  const current = await getFile(owner, repo, CONTENT_PATH, branch, token);
  const html = decodeBase64Utf8(current.content);
  const updated = updateTradepediaHtml(html, payload);
  const message = `Update Tradepedia entry: ${updated.entry.title}`;

  const contentCommit = await putFile(owner, repo, CONTENT_PATH, branch, token, {
    message,
    content: encodeBase64Utf8(updated.html),
    sha: current.sha
  });

  const fallback = await getFile(owner, repo, FALLBACK_PATH, branch, token);
  await putFile(owner, repo, FALLBACK_PATH, branch, token, {
    message,
    content: encodeBase64Utf8(updated.html),
    sha: fallback.sha
  });

  return {
    ok: true,
    id: updated.entry.id,
    title: updated.entry.title,
    action: updated.action,
    count: updated.count,
    contentUrl: CONTENT_URL,
    commit: contentCommit.commit?.sha || null
  };
}

function updateTradepediaHtml(html, payload) {
  const dataMatch = html.match(/<script id="pageData" type="application\/json">([\s\S]*?)<\/script>/);
  if (!dataMatch) throw httpError(500, "pageData script block was not found.");

  const pages = JSON.parse(dataMatch[1]);
  const entry = buildEntry(payload);
  const existingIndex = pages.findIndex(page => page.id === entry.id);

  let action = "added";
  if (existingIndex >= 0) {
    if (payload.replaceExisting === false) throw httpError(409, `Entry already exists: ${entry.id}`);
    pages[existingIndex] = entry;
    action = "updated";
  } else {
    pages.push(entry);
    pages.sort((a, b) => a.title.localeCompare(b.title, "tr"));
  }

  const nextData = `<script id="pageData" type="application/json">${JSON.stringify(pages)}</script>`;
  let nextHtml = html.replace(dataMatch[0], nextData);
  nextHtml = upsertNavButton(nextHtml, entry, existingIndex >= 0);
  nextHtml = updateCounts(nextHtml, pages.length);

  return { html: nextHtml, entry, action, count: pages.length };
}

function buildEntry(payload) {
  const id = slugify(payload.id || payload.title);
  const title = cleanText(payload.title);
  const kind = cleanText(payload.kind);
  const category = cleanText(payload.category);
  const level = cleanText(payload.level || "Baslangic");
  const tags = Array.isArray(payload.tags) ? payload.tags.map(cleanText).filter(Boolean) : [];
  const related = Array.isArray(payload.related) ? payload.related.map(cleanText).filter(Boolean) : [];

  const html = [
    `<article class="entry" id="${escapeAttr(id)}">`,
    `<div class="crumb"><a href="#top">Ana sayfa</a> &rsaquo; <a href="#index">Tum maddeler</a> &rsaquo; ${escapeHtml(title)}</div>`,
    `<h2>${escapeHtml(title)}</h2>`,
    `<div class="meta"><span>${escapeHtml(kind)}</span><span>${escapeHtml(category)}</span><span>${escapeHtml(level)}</span>${tags.map(tag => `<span>${escapeHtml(tag)}</span>`).join("")}</div>`,
    `<p class="summary">${paragraphText(payload.summary)}</p>`,
    section(id, "tanim", "Tanim", payload.body),
    payload.usage ? section(id, "kullanim", "Nasil kullanilir?", payload.usage) : "",
    payload.pitfalls ? section(id, "tuzak", "Yanlis kullanim", payload.pitfalls) : "",
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
  }).join(" &middot; ");
  return `<section id="${escapeAttr(id)}-ilgili"><h3>Baglantili maddeler</h3><div class="related">${links}</div></section>`;
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

function upsertNavButton(html, entry, existed) {
  const button = `<button class="nav-item" data-id="${escapeAttr(entry.id)}"><span>${escapeHtml(entry.title)}</span><small>${escapeHtml(entry.kind)} &middot; ${escapeHtml(entry.category)}</small></button>`;
  const existingButton = new RegExp(`<button class="nav-item" data-id="${escapeRegExp(entry.id)}">[\\s\\S]*?<\\/button>`);
  if (existingButton.test(html)) return html.replace(existingButton, button);
  if (existed) return html;

  const navMatch = html.match(/(<div class="nav-list" id="navList">)([\s\S]*?)(<\/div>\s*<\/aside>)/);
  if (!navMatch) throw httpError(500, "navList block was not found.");
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
      throw httpError(400, `Missing required field: ${field}`);
    }
  }
}

async function getFile(owner, repo, path, branch, token) {
  const response = await githubFetch(`/repos/${owner}/${repo}/contents/${encodeURIComponentPath(path)}?ref=${encodeURIComponent(branch)}`, token);
  return response;
}

async function putFile(owner, repo, path, branch, token, body) {
  return githubFetch(`/repos/${owner}/${repo}/contents/${encodeURIComponentPath(path)}`, token, {
    method: "PUT",
    body: JSON.stringify({ branch, ...body })
  });
}

async function githubFetch(path, token, init = {}) {
  const response = await fetch(`https://api.github.com${path}`, {
    ...init,
    headers: {
      "accept": "application/vnd.github+json",
      "authorization": `Bearer ${token}`,
      "content-type": "application/json",
      "user-agent": "tradepedia-gpt-action",
      "x-github-api-version": "2022-11-28",
      ...(init.headers || {})
    }
  });

  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw httpError(response.status, data.message || `GitHub API failed with ${response.status}`);
  }
  return data;
}

function cleanText(value) {
  return String(value || "").trim().replace(/\s+/g, " ");
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

function encodeURIComponentPath(path) {
  return path.split("/").map(encodeURIComponent).join("/");
}

function decodeBase64Utf8(value) {
  const binary = atob(String(value || "").replace(/\n/g, ""));
  const bytes = Uint8Array.from(binary, char => char.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function encodeBase64Utf8(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8"
    }
  });
}

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}
