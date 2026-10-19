---
name: driving-chrome
description: "Use when a session needs to click, fill or read pages in Court's own Chrome through the Playwright MCP server (the `playwright` tools): signed-in sites such as Chatwoot, Meta, a sign-up flow or a live run. Covers starting the server with no approval prompt, and how to fill fields and click without Chrome dropping the tab."
---

# Driving Court's Chrome with Playwright

The `playwright` MCP server runs in extension mode: it drives Court's own Chrome, with his logins and 1Password, through the Playwright Extension. Use it for anything that needs his signed-in sessions; never ask him to log in to a separate browser.

## Starting the server

- It runs in a tmux window named `playwright`, on port 8931 (`~/.pi/agent/mcp-adapter.json` points there). Start it from the directory whose git-ignored `.env` holds `PLAYWRIGHT_MCP_EXTENSION_TOKEN`:

  ```sh
  tmux new-window -d -n playwright -c <dir-with-.env> \
    "creel exec PLAYWRIGHT_MCP_EXTENSION_TOKEN -- npx -y @playwright/mcp@latest --port 8931 --extension"
  ```

- With the token, the extension connects without a prompt and opens Chrome itself if it is closed. Without it, Court must click Allow each time.
- If a call times out or says "page closed", check `lsof -nP -iTCP:8931 -sTCP:LISTEN`; restart the window if nothing listens. Never read the `.env`.
- To see what the extension is doing, start the server with `DEBUG='pw:mcp*'` and `2>&1 | tee /tmp/pw-mcp.log`.

## The rules that keep the tab attached

1. **Never type into a field with `browser_type` or `browser_fill_form`.** Focusing a field makes 1Password insert its menu, an iframe from another extension; Chrome then detaches the debugger ("Cannot access a chrome-extension:// URL of different extension") and the tab disappears from Playwright. Set values by script instead:

   ```js
   () => {
     const set = (el, v) => {
       Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set.call(el, v);
       el.dispatchEvent(new Event('input', { bubbles: true }));
       el.dispatchEvent(new Event('change', { bubbles: true }));
     };
     const inputs = [...document.querySelectorAll('main input')];
     set(inputs[0], 'Business name');
   }
   ```

2. **Click by script**: `[...document.querySelectorAll('button')].find(b => b.textContent.trim().toLowerCase() === 'continue').click()`. The tab is usually behind Court's other tabs, so `browser_click` waits for it to be visible and times out. Match on `textContent`, not `innerText` (CSS can upper-case the text).
3. **One `playwright` call per message.** Parallel calls race on the same tab and leave the tab list wrong.
4. **After a navigation, wait before reading**: `browser_wait_for` with text you expect (or `textGone` for a "Checking…" label). Evaluating straight after `browser_navigate` fails with "Execution context was destroyed".
5. **Read with `browser_evaluate`** returning `document.querySelector('main').innerText` or the inputs' values and checked states. Snapshots of a background tab can lag a step behind.
6. **Work in one tab.** Navigate it between sites rather than opening several. For a short call on another signed-in site, open a page inside `browser_run_code_unsafe`, use it and close it in the same call.

## Calling a site's API as Court

When the page's own API is easier than clicking (Chatwoot is), call it from a tab on that site with the session the page already holds; for Chatwoot the session headers are in the `cw_d_session_info` cookie. Copy a secret into another site's form inside the same `browser_run_code_unsafe` call, so it never appears in the conversation.

## Before you mutate

Reading is always fine. Creating, deleting or paying through Court's browser is his account acting: say what you will create before you do it, and record what you created so it can be removed.
