# Allowlists

Palladium uses allowlists to decide which URLs can be downloaded. An allowlist is a JSON document containing regular-expression patterns. A URL is allowed when it matches at least one enabled entry from any configured allowlist.

The built-in default allowlist is loaded from `https://al.getpalladium.app/default.json`. You can add your own allowlist from an HTTPS URL, import a `.json` file, or paste its JSON directly in **Settings > URL Allowlists**.

## Create an allowlist

Use this version 1 document format:

```json
{
  "version": 1,
  "name": "My allowlist",
  "entries": [
    {
      "name": "Example site",
      "pattern": "^https?://(www\\.)?example\\.com/.+$",
      "enabled": true
    }
  ]
}
```

| Field | Required | Description |
| --- | --- | --- |
| `version` | Yes | Must be `1`. |
| `name` | No | The allowlist name shown in Palladium. |
| `entries` | Yes | An array of URL-matching entries. |
| `entries[].name` | No | A human-readable name for the entry. Palladium uses the pattern if omitted. |
| `entries[].pattern` | Yes | An ICU regular expression evaluated against the entered URL. |
| `entries[].enabled` | No | Set to `false` to exclude an entry. Omit it or set it to `true` to use the entry. |

Patterns should normally begin with `^` and end with `$` so they match only the intended URLs. JSON requires a backslash to be escaped, so use `\\.` to match a literal dot. Test each pattern before publishing: an invalid regular expression prevents Palladium from loading that allowlist.

## Add a hosted allowlist

Host the JSON at a public HTTPS URL, then in Palladium open **Settings > URL Allowlists**, choose **Add allowlist**, and enter the URL. Palladium downloads the document immediately and checks it whenever you choose **Refresh**.

For example, an allowlist hosted at `https://example.com/palladium-allowlist.json` can contain:

```json
{
  "version": 1,
  "name": "Example media sites",
  "entries": [
    {
      "name": "Example Videos",
      "pattern": "^https?://(www\\.)?videos\\.example\\.com/.+$",
      "enabled": true
    },
    {
      "name": "Disabled example",
      "pattern": "^https?://disabled\\.example\\.com/.+$",
      "enabled": false
    }
  ]
}
```

Only HTTPS source URLs can be added remotely. Keep the URL stable so existing users continue receiving updates.

## Palladium examples

### Allow every URL

[`https://al.getpalladium.app/all.json`](https://al.getpalladium.app/all.json) is an unrestricted allowlist:

```json
{
  "version": 1,
  "name": "Palladium's allowlist",
  "entries": [
    {
      "name": "All",
      "pattern": ".*",
      "enabled": true
    }
  ]
}
```

This pattern permits every URL. Only add it if you intend to remove allowlist restrictions entirely.

### Default allowlist

[`https://al.getpalladium.app/default.json`](https://al.getpalladium.app/default.json) is Palladium's built-in default allowlist:

```json
{
  "version": 1,
  "name": "Palladium's default allowlist",
  "entries": [
    {
      "name": "Vimeo",
      "pattern": "^https?://(www\\.)?vimeo\\.com/.+$",
      "enabled": true
    },
    {
      "name": "Internet Archive",
      "pattern": "^https?://(www\\.)?archive\\.org/.+$",
      "enabled": true
    },
    {
      "name": "PeerTube",
      "pattern": "^https?://([a-zA-Z0-9-]+\\.)?peertube\\.[a-zA-Z]{2,}/.+$",
      "enabled": true
    }
  ]
}
```

## Add a local or pasted allowlist (v1.1.1+)

To use an allowlist without hosting it:

1. Save the JSON as a file ending in `.json`, then choose **Import file** in **Settings > URL Allowlists**; or
2. Choose **Paste JSON**, paste the complete document, and select **Add**.

Local and pasted allowlists are stored in the app. Edit or replace the source and import or paste it again to update it.
