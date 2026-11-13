---
name: playtest-log
description: Turn the user's playtest feedback (chat, screenshots) into the project record — a docs/playtests/YYYY-MM-DD-*.md note, follow-up items, and decisions in docs/DECISIONS.md. Use whenever the user reports how the game played ("too easy", "X feels bad", "Y works now", screenshots of a bug).
---

# /playtest-log — record a playtest

This repo is public: write the note in English, translate the user's words faithfully (mark them as translated),
no personal data, no machine paths.

## 1. Note (`docs/playtests/YYYY-MM-DD-<topic>.md`, template in `docs/playtests/README.md`)

Version / commit played, class, difficulty, what felt good / bad, bugs, the user's own verdicts on feel (quote,
do not paraphrase into stronger claims), decisions, follow-ups. Screenshots: describe what they show.

## 2. Follow-ups

- Each finding becomes a task where the user keeps tasks (ask if unsure; do not open public issues on your
  own). Body: what the user saw, the quote, the playtest file, a first hypothesis marked as unverified.
- Items the user confirmed working: mark the spec "done" and say so in the note.

## 3. Decisions

User decisions (targets, rules, accepted trade-offs) → `docs/DECISIONS.md` (current truth) and one dated line
in the `docs/ROADMAP.md` decisions log.

## 4. Next step

Recommend what to do about the findings: measure with `/balance` before tuning; hypothesis first, then a spec
and `/critic`.
