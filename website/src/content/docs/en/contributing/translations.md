---
title: Translating FluxDown
description: Help translate the app, the web UI, and this website into your language — no coding required.
section: contributing
order: 2
---

FluxDown is translated by its community on a self-hosted [Weblate](https://translate.zerx.dev/projects/fluxdown/) instance. Everything happens in the browser — **no Git, no coding, no build setup required**.

## What can be translated

![FluxDown project on Weblate](/docs/weblate/project.png)

| Component | What it covers |
| --- | --- |
| **Desktop & Mobile App** | Every string in the Windows/macOS/Linux app and the mobile app |
| **Web App** | The web UI served by the headless server |
| **Website** | fluxdown.zerx.dev — landing page, FAQ, changelog |

English is the source language; Simplified Chinese is maintained by the core team. Everything else is yours to build.

## Quick start

1. [Register](https://translate.zerx.dev/accounts/register/) on the translation site (email or GitHub login).
2. Open the [FluxDown project](https://translate.zerx.dev/projects/fluxdown/) and pick a component and a language.
3. Translate string by string — the editor shows the English source, nearby strings, and a glossary:

![Weblate translation editor](/docs/weblate/editor.png)

Press **Save and continue** to move through the list. Not sure about a string? Click **Suggest** instead — another translator can review it later.

## Placeholders

Text in curly braces like `{name}`, `{count}`, or `{speed}` is replaced with live values at runtime. **Keep placeholders exactly as-is** — reposition them freely to fit your language's grammar, but never translate or delete what's inside the braces. Weblate warns you automatically if a placeholder goes missing.

## Starting a new language

Your language isn't listed yet? Open a component and click **Start new translation**:

![Starting a new translation](/docs/weblate/new-language.png)

Weblate creates the translation file for you and opens a pull request against the FluxDown repository once you start translating. After it merges:

- **App**: your language appears automatically in *Settings → Language* in the next release — the app discovers translation files at runtime.
- **Web UI & website**: the language shows up in the language switcher with the next deploy.

No code changes are needed anywhere. The language selector labels itself with the `languageNativeName` string, so translate that key first.

## Tips

- **Partial translations are fine.** Untranslated strings fall back to English key by key — a 30% translated language is already useful.
- **Consistency beats literalness.** Check the glossary and nearby strings; reuse the same term for the same concept.
- **You will be asked to sign the CLA** on your first contribution — a one-time click inside Weblate.
- Found a typo in the English source? Report it via the [feedback form](/feedback) or open an issue — source strings are managed in the repository.
