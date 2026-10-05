# Contributing

Contributions, issue reports, and built-in application requests are welcome.

## Built-in application requests

Built-in applications are product-specific integrations maintained inside OSDAppClient. They are intentionally reserved for broadly used software with a stable, vendor-supported acquisition and unattended installation path.

Before requesting a built-in, review the criteria in:

- [Built-in application request policy](docs/built-in-apps.md#requesting-a-new-built-in-application)

A strong request includes:

```text
Product:
Vendor:
Vendor documentation:
Direct installer URL(s):
Architectures:
Silent install command:
Update/freshness mechanism:
Why this should be a generic built-in:
```

Do not request a built-in when acquiring the installer requires scraping, browser automation, traffic sniffing, temporary signed URLs, session cookies/tokens, or bypassing CDN/anti-bot controls.

For niche, customer-specific, internal, authenticated, or otherwise non-generic software, use the repository model instead.
