TRADEPEDIA BRIDGE FOR CODEX

Purpose:
Use this repository as a temporary bridge for the Tradepedia Android auto-update task.

Important:
- Do not redesign Tradepedia.
- Do not rewrite the Tradepedia HTML/CSS/JS.
- Use the real content.html provided by the user as-is.
- Copy the real content.html into:
  1) public/content.html
  2) app/src/main/assets/fallback.html

If the real HTML is too large for chat, ask the user to paste it in chunks or upload it directly through GitHub web editor.

Target architecture:
- APK remains fixed.
- App fetches public content.html on startup.
- If download succeeds, cache it locally.
- If offline, show cached content.
- If no cache exists, show fallback.html from APK assets.

Expected public content URL format:
https://chaoslightnight2-ctrl.github.io/Shorts-blogger/content.html

Codex tasks:
1. Check whether public/content.html contains placeholder content.
2. Replace placeholder with the real Tradepedia content.html when provided.
3. Keep the design and content unchanged.
4. Configure GitHub Pages to publish public/content.html.
5. Configure Android CONTENT_URL to the public GitHub Pages URL.
6. Build APK artifact.
7. Return public content URL and APK artifact link.
