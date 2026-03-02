---
name: workon
description: Automates the Trello-driven development workflow for working on cards. Use when the user says /workon followed by a Trello card URL, or asks to work on a Trello card. Fetches card context, assigns it, moves to IN PROGRESS, investigates the codebase, triages priority, and creates a plan.
---

# Work On Trello Card

## Trigger

User sends `/workon <TRELLO_CARD_URL>` or pastes a Trello card link with intent to work on it.

## Workflow

### Phase 1: Switch to Plan Mode

Before doing anything else, switch to plan mode. All investigation and planning must happen before any code changes.

### Phase 2: Fetch Card Context

Extract the card short ID from the URL. The short ID is the segment after `/c/` in the URL (e.g. `YmgddE5E` from `https://trello.com/c/YmgddE5E/137-some-title`).

Use the Trello MCP server `project-0-escape-tsunami-trello` to fetch all card context in parallel:

1. `get_card` with `cardId` and `includeMarkdown: true`
2. `get_card_comments` with `cardId`
3. `get_acceptance_criteria` with `cardId`

### Phase 2.5: Download and Analyze Attachments

After fetching the card, extract ALL attachments from the `get_card` response. Download and analyze every attachment — images, videos, and other files.

#### Download

Use the `download_attachment` MCP tool on `project-0-escape-tsunami-trello` to download each attachment. It handles Trello API authentication automatically and returns base64-encoded data.

```
CallMcpTool: download_attachment
  cardId: "<card_full_id>"
  attachmentId: "<attachment_id>"
```

The response is JSON with `fileName`, `mimeType`, and `data` (base64). Save decoded files to `.cursor/tmp/<cardShortId>/` (using the short ID from the URL, e.g. `2028Rogh`). This keeps attachments from different cards separated.

```powershell
New-Item -ItemType Directory -Force -Path .cursor\tmp\<cardShortId> | Out-Null
$json = Get-Content "<agent-tools-output-path>" -Raw | ConvertFrom-Json
[System.IO.File]::WriteAllBytes(".cursor\tmp\<cardShortId>\<filename>", [System.Convert]::FromBase64String($json.data))
```

Extract the `attachmentId` from the attachment URL in the `get_card` response — it's the segment after `/attachments/` (e.g. `69a2bd34c958846e2119d1b6` from `.../attachments/69a2bd34c958846e2119d1b6/download/...`).

#### Analyze by type

- **Images** (jpg, jpeg, png, gif, webp): Use the `Read` tool on the downloaded file path to view and analyze each image. Look for screenshots, mockups, visual references, UI states, error messages, or reproduction steps shown visually.
- **Videos** (mp4, webm, mov): First, try using the `Task` tool with `subagent_type: "generalPurpose"` and pass the downloaded video file paths in the `attachments` parameter. Ask the subagent to describe the video content in detail — what is shown, any UI interactions, bugs demonstrated, or expected vs actual behavior. If direct video analysis fails, extract frames using `ffmpeg` and analyze those images instead:
  ```bash
  ffmpeg -i ".cursor/tmp/<cardShortId>/video.<ext>" -vf "fps=5" ".cursor/tmp/<cardShortId>/frames/frame-%03d.png"
  ```
  Then use the `Read` tool on each extracted frame. Use `fps=5` by default. Increase fps for fast-paced or short videos where detail matters, decrease to `fps=1` or `fps=0.5` for long videos (>30s) to keep frame count manageable.
- **Other files** (pdf, txt, json, etc.): Read or inspect as appropriate using the `Read` or `Shell` tools.

#### Handle failures

If any attachment fails to download (network error, 403, 404, expired URL, etc.):
1. **Stop and flag it immediately** to the user before continuing — list the attachment name, URL, and the error.
2. Wait for the user to either provide the attachment manually or confirm to skip it.
3. Do NOT silently skip failed attachments.

### Phase 3: Assign and Move Card

Run these in parallel via `CallMcpTool` on `project-0-escape-tsunami-trello`:

1. **Assign Joe** using `assign_member_to_card`:
   - `cardId`: the card's full ID (from `get_card` response)
   - `memberId`: `5269468e5b22765e26003cb6`

2. **Move to IN PROGRESS** using `move_card`:
   - `cardId`: the card's full ID
   - `listId`: `69811c43efb9f4653aab4bea`

### Phase 4: Triage Priority

Check the card's labels from the `get_card` response. If the card does not already have one of these priority labels, assign one using `update_card_details` based on your assessment of severity:

| Priority | Label ID | When to Use |
|----------|----------|-------------|
| Low Prio | `696d57f2c18d5f6d50738c96` | Minor polish, cosmetic, non-urgent improvements |
| Medium Prio | `697cff8bb9fdeeee47b4c103` | Functional issues with workarounds, moderate impact |
| High Prio | `696d4ff170dadc1db180be56` | Broken functionality, significant user impact, no workaround |
| ⚠️CRITICAL! | `69643e23e5558734307fc89c` | Game-breaking, data loss, crashes, security vulnerabilities |

To assign a label, use `update_card_details` with the card's existing label IDs plus the new one in the `labels` array. Do not remove existing labels.

### Phase 5: Investigate

Thoroughly investigate the issue or feature request in the codebase:

- Use explore subagents and search tools to find all relevant code
- Trace the full data flow (server to client, or vice versa)
- Identify root causes for bugs, or integration points for features
- Note any related systems that may be affected

### Phase 6: Create Plan

Present findings and a concrete plan using `CreatePlan`. The plan should:

- Explain the root cause (for bugs) or the design approach (for features)
- List specific files and code locations to change
- Include code snippets where helpful
- Be proportional to the task complexity

### Phase 7: After Implementation

After the plan is confirmed and implemented in agent mode, **do not** move the card to READY FOR QA automatically. Wait for the user to explicitly signal that work is complete (e.g. "move to QA", "ready for QA", "done").

When the user gives the signal, move the card using `move_card`:
- `cardId`: the card's full ID
- `listId`: `69643e3ab7974788298e0794`
