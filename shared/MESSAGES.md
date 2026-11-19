# Island message format

This is the one format all islands understand: Windows, Android and Mac.

**Rule: this format never changes without telling the owner first.**

Each message is a small piece of text in a format called JSON. Think of it as a labelled form: every line has a label and a value.

## Example

```json
{
  "version": 1,
  "id": "chronos-standup-0930",
  "source": "chronos",
  "kind": "alert",
  "title": "Stand-up in 5 minutes",
  "body": "Room 2, with the design team",
  "category": "#4F8CFF",
  "priority": "normal",
  "duration": 8,
  "actions": [
    { "id": "snooze", "label": "Snooze" },
    { "id": "open", "label": "Open" }
  ]
}
```

## The fields

| Field | Required? | Allowed values | What it means |
|---|---|---|---|
| `version` | Yes | `1` | Which edition of this format the message uses. |
| `id` | Yes | Any text, up to 128 characters | The message's name. Sending the same `id` again **updates** that message instead of showing a second one. |
| `source` | Yes | A short lowercase app name: letters, digits and `-`, up to 32 characters (for example `chronos`, `classnotes`, `test`). `system` is kept for the island itself. | Who sent it. Button replies go back to this sender. |
| `kind` | Yes | `alert`, `timer`, `progress`, `media`, `reply` | What sort of message it is. |
| `title` | Yes | Text, up to 80 characters | The main line. |
| `body` | No | Text, up to 240 characters | The second line. |
| `progress` | No | A number from `0` to `1` | How far along. `0.5` means halfway. Leave it out if not relevant. |
| `category` | No | A colour such as `#4F8CFF` | The message's accent colour. If left out, the island uses its own default. |
| `priority` | No | `low`, `normal`, `high` | How important it is. If left out, it's `normal`. |
| `duration` | No | A number of seconds, or `"until_cleared"` | How long to show it. If left out, it's `5` seconds. |
| `actions` | No | Up to 2 buttons | Each has an `id` and a `label` of up to 20 characters. |
| `quiet` | No | `true` | *(Added 2026-11-13 with the owner's approval.)* Keep this message for the Home card's lists only (for example Chronos's upcoming items) and **do not show it on its own**. Islands that do not know the field would show it normally, so senders only use it with islands that understand it. Windows (Drop) understands it; Halo must also ignore quiet messages on the phone. |
| `endsAt` | No | A number: milliseconds since 1 January 1970 (UTC), as in `Date.now()` | *(added 2026-11-13, optional)* When something ends: a deadline, an event. An island that supports it shows a live countdown to that moment and keeps the message until a minute after it. Islands that do not know the field ignore it. |

`version` isn't on the original list of fields. It's there so older islands can recognise a newer format and handle it safely.

## The kinds

| Kind | Use it for |
|---|---|
| `alert` | Something just happened. |
| `timer` | A countdown or a running clock. |
| `progress` | Something with a percentage, such as a download. |
| `media` | What's playing. |
| `reply` | An answer or response from the source. |

## Priority

| Priority | What the island does |
|---|---|
| `low` | Waits its turn behind everything else. |
| `normal` | Shows in the order it arrived. |
| `high` | Shows straight away, ahead of anything waiting. |

## Clearing a message

To remove a message early, or to end one set to `until_cleared`, send:

```json
{ "version": 1, "type": "clear", "id": "chronos-standup-0930", "source": "chronos" }
```

## Button replies

When someone clicks a button, the island sends this back to the message's `source`:

```json
{
  "version": 1,
  "type": "action",
  "messageId": "chronos-standup-0930",
  "actionId": "snooze"
}
```

## Handling bad messages

An island must never crash on a bad message.

- **Required field missing or not allowed:** ignore the whole message and write a line to the log.
- **Unknown extra fields:** ignore those fields and show the message.
- **Text too long:** shorten it.
- **`progress` out of range:** limit it to between `0` and `1`.
- **More than 2 actions:** use the first 2.
- **Newer `version` than the island knows:** ignore the message and write a line to the log.

## How a message travels on the same PC

*(Added in session 1.3 after the owner asked for a local-only listener. The message contents above did not change.)*

On Windows, Drop listens on a **named pipe** called `IslandDrop`. A named pipe is a private channel inside Windows. Only the person signed in to this PC can open it, and the network is blocked, so nothing outside this PC can send to it.

- **Sending:** a program connects to `\.\pipe\IslandDrop` and writes **one message per line**. Each line is one complete message in the format above, as UTF-8 text with no line breaks inside it. It can send as many lines as it likes. A line longer than 16,000 characters is ignored.
- **Button replies:** when someone clicks a button, Drop writes the `action` reply (see above) as one line back down the same connection, if the sender is still connected. Drop also saves every reply to `%LocalAppData%\Island\replies\<source>.jsonl`, so a program that does not stay connected can read its replies later.
- **Bad messages** are handled as described in "Handling bad messages". Drop does not reply to them; it writes a line to its log.

## Built into Drop (not messages)

These are made by Drop itself and use the same screen design. They need no sender:

- **Now Playing** from Windows' media controls (Spotify, browsers and so on). It shows as a `media` message with `source` set to `system` and an id of `media-now-playing`. Its previous / play-pause / next buttons are Drop's own and are not limited to 2.
- **Timer:** started from the tray menu or Settings. It shows as a `timer` message with id `timer-main` and ends with a "Time's up" message with +5 min and OK buttons.

