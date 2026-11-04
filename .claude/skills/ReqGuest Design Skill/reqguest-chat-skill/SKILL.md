---
name: reqguest-chat
description: Build or extend the ReqGuest staff mobile app as a WhatsApp-style chat UI, where every guest request is a chat and every event (creation, status change, assignment, comment, attachment) is a message in chronological order. Use when designing or coding ReqGuest screens, request threads, notifications, or mapping the ReqGuest SQL schema to UI.
---

# ReqGuest Chat — WhatsApp-style request app

The app should feel instantly familiar to anyone who uses WhatsApp. Nothing complex.

## Core model
- **One request = one chat.** The chat list shows every request visible to the signed-in user.
- **Inside a chat there is only a discussion.** Status changes, assignments, comments and attachments all appear as messages, in strict chronological order. No separate "details" or "timeline" screen is needed; details live in a bottom sheet opened by tapping the chat header.
- Open a chat and the list scrolls to the latest message, just like WhatsApp.

## Screens
Bottom tab bar (4 tabs):
1. **Requests** (`forum`): the chat list. Unread badge = number of chats with unread events.
2. **Alerts** (`notifications`): the notification feed, grouped by day (Today / Yesterday), with an unread dot and "Mark all read". Tapping an alert opens that chat.
3. **Team** (`groups`): departments of the tenant, members with presence (on shift / break / off) and open-request counts.
4. **You** (`account_circle`): profile, On shift, Alert sound, Show internal notes, account info, Sign Out.

### Requests (chat list)
- Top row: tenant name (left), camera + more (right). Large title "Requests" uses the ReqGuest logo.
- Search field ("Search rooms or requests"), then filter chips: All · Unread · Assigned to me · High priority.
- "Closed" row at the top, like WhatsApp's Archived: holds final-status requests (Delivered, Completed, Cancelled).
- Row: 52px round avatar tinted by department with the request-type icon · **requester (room) bold** · short title · last-event time (green when unread) · preview of the last event (icon prefix: `swap_horiz` status, `person_add` assign, `lock` internal, `done_all` own message, `photo_camera` media) · high-priority tag · green unread pill.
- Sorted by the latest event time, newest first.

### Chat thread
- Header: back chevron with the unread count of *other* chats · avatar · "Room 515 · AC not cooling" · subline "In Progress · Suresh Nair" · call + info buttons.
- Amber system banner at the top: "Staff chat for {ref}. Status changes appear here in order, as they happen."
- Message types:
  - **Date pill**, centred (Today / Yesterday / date).
  - **Guest request card**, left-aligned, the first message: requester, title, description, PriorityTag, "Logged by …".
  - **Status pill**, centred: StatusBadge + who + note + time.
  - **Assignment pill**, centred: "Auto-assigned to Ramesh Singh", "You picked this up".
  - **Comment bubble**: own = right, green-100 bubble with blue `done_all` ticks; others = left, white with sender + department. **Internal notes** use a warning-bg bubble labelled "INTERNAL NOTE" with a lock.
  - **Attachment bubble**: media placeholder with file name, size and type.
- Composer: `+` attach · rounded input · lock toggle (switches to an internal note; the input turns amber) · green send button (camera when empty).
- **Action strip** above the composer: only the transitions allowed from the current status (`workflow_transitions`). The first forward action is primary, others outline, Cancel is ghost. Cancel confirms in a bottom sheet. Every transition posts a status pill and shows a toast with Undo.
- Closed chats hide the action strip and show "Delivered yesterday at 09:18".

## Schema → UI mapping (see `reference/schema/`)
- `requests` → chat. `requester_name` = chat name, `title` (room suffix stripped) = subtitle, `request_type` icon = avatar glyph, `priority` → PriorityTag.
- `request_status_history` → status pills (`from_status_id` NULL = guest request card).
- `request_assignments` → assignment pills (`assignment_type` auto / supervisor / self).
- `request_comments` → bubbles; `is_internal = 1` → internal-note style.
- `request_attachments` → media bubbles.
- `workflow_transitions` (`from_status_id` = current) → action strip; `action_name` = button label.
- `workflow_statuses.is_final = 1` → moves the chat to Closed.
- Map status codes to StatusBadge: requested/raised/received → new · accepted/assigned/on_hold → acknowledged · collected/delivering/in_progress/preparing/ready → in_progress · delivered/completed → completed · cancelled → cancelled.
- **Visibility by role**: admin sees all tenant requests; supervisor sees their department's; staff see only requests assigned to them.
- Sort events by `created_at`. On ties: guest → assignment → status → comment/attachment.

## Visual rules (ReqGuest Design System)
- Use the DS components: TabBar, SearchField, Chip, StatusBadge, PriorityTag, Avatar, Button, Switch, Sheet, Toast, EmptyState. Icons are Material Symbols Rounded.
- Brand green `#22DD60` only for primary action, selection, unread and success. Text on green is `#062B14`; green text on white is `#0B7A34`.
- App background `#F5F5F5`, white cards, 0.5px hairline separators, glass nav and tab bars.
- System fonts; tabular numerals for rooms, times and counts. No emoji, no exclamation marks.
- Copy leads with the room: "New request · Room 609 · Extra pillow". Middle-dot separators. Past-tense toasts with Undo.
- Light and dark themes via `data-theme`.

## Creative extras (kept WhatsApp-familiar)
- Incoming request drops a top toast ("New request · Room 609 · Extra pillow" + Open) and bumps the unread badges.
- Back button shows the unread count of other chats.
- The lock toggle in the composer switches to staff-only notes.

## Reference
- `reference/ReqGuest Chat.html`: self-contained working prototype (open in any browser, works offline).
- `reference/schema/`: source MySQL schema and seed data.
- `assets/`: ReqGuest logo and mark.
