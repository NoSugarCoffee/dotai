# HTML Report Format for Architectural Reviews

This guide outlines how to structure a self-contained HTML report analyzing software architecture. The report uses Tailwind CSS and Mermaid diagrams from CDNs, rendered in the OS temp directory.

## Core Structure

The scaffold includes a semantic HTML5 document with Tailwind styling and Mermaid initialization. Custom CSS covers elements like "dashed seam lines" and "hand-drawn-feeling arrow heads" that Tailwind doesn't address directly.

## Content Organization

Reports follow a three-section pattern: header (with legend), candidate cards evaluating architectural options, and a top recommendation section. Each candidate card centers on before/after diagrams with minimal supporting prose.

## Diagram Approaches

The guide recommends matching visualization technique to content:

- **Mermaid flowcharts** work best for dependency and call-flow relationships
- **Hand-built boxes-and-arrows** suit cases where Mermaid's layout proves constraining
- **Cross-section stacking** illustrates layered structures effectively
- **Mass diagrams** compare interface surface area against implementation size
- **Call-graph collapse** shows structural consolidation

Diagrams should remain roughly 320px tall for comfortable side-by-side comparison.

## Language and Tone

The guidance emphasizes "plain English, concise" prose using precise architectural vocabulary from a referenced glossary. Approved terms include "module," "interface," "depth," "seam," and "adapter." The style explicitly discourages vague alternatives like "component," "easier to maintain," or "cleaner code."

Bullets capture wins using glossary terminology—locality, leverage, and interface reduction—rather than general improvement claims.
