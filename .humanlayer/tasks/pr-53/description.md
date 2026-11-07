[HumanLayer skills](https://github.com/humanlayer/skills)

## Why the change

Make HumanLayer's `visual-pr` available as a `dev` skill across the configured coding tools so agents can prepare concise visual PR descriptions on request.

## Special things to note

- HumanLayer is pinned as a whole repo because its plugins have no APM skill manifest; this advances the existing pin to a commit that contains `visual-pr`.
- The skill layout check passed, while the full local installer stopped during MCP sync on an existing `dot-mcp-oauth` Codex connection conflict.

## Change outline

The APM pin supplies the skill, and the publication map gives it the `dev` name:

```diff
 humanlayer/skills
-  3c26291
+  4d69d20
   └── plugins/
       ├── show-me/skills/show-me       → docs.show-me
+      └── visual-pr/skills/visual-pr    → dev.visual-pr
```
