# Shorts-blogger Tradepedia content

This repository publishes `public/content.html` with GitHub Pages.

Runtime contract:

- The APK should load the remote `content.html` URL.
- If the download succeeds, the APK can cache it.
- If the network is unavailable, the APK should use cache.
- If cache is unavailable, the APK should use `app/src/main/assets/fallback.html`.

To update Tradepedia content from a source HTML file:

```powershell
.\scripts\publish-tradepedia-content.ps1 -SourceHtml "C:\path\to\tradepedia_html_kopyala.txt"
git add public/content.html app/src/main/assets/fallback.html
git commit -m "Update Tradepedia content"
git push origin main
```

After the push, GitHub Actions deploys the `public` folder to GitHub Pages.
