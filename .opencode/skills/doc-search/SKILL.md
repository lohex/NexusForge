---
name: "doc-search"
description: "Searches online documentation for technical information"
---

# Documentation Search Skill

This skill retrieves information from online documentation sources.

## Capabilities

- Fetch content from specific documentation URLs you provide
- Extract relevant technical information from documentation pages
- Combine fetched content with code examples where available

## Limitations

- **Cannot browse/search freely**: You must provide specific URLs
- **No WebSearch tool**: Cannot search across multiple documentation sites
- **URL required**: Must have the exact documentation URL to fetch

## Usage

Use this skill when you:
- Have a specific documentation URL you want to fetch
- Want to retrieve content from a known documentation site
- Need to fetch API docs, changelogs, or similar

## Tools

- **WebFetch**: Fetch content from your provided documentation URLs (markdown format preferred)
- **Read**: Read fetched documentation content

## Usage

Use this skill when you need to:
- Find documentation for APIs, libraries, or frameworks
- Look up configuration options
- Understand syntax or usage patterns
- Troubleshoot based on official documentation

## Tools

- **WebFetch**: Fetch content from documentation URLs (markdown format preferred)
- **WebSearch**: Search for specific terms across documentation sites
- **Read**: Read fetched documentation content

## Example Query

"Search MDN Web Docs for the Fetch API documentation and explain how to handle errors"

## Limitations

- Results may vary based on documentation availability
- Some documentation may be behind authentication
- Content may become outdated if documentation is removed