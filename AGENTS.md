# AGENTS.md - SUSE Observability Documentation Repository

This is the documentation repository for SUSE Rancher Prime: Observability (formerly StackState).
It uses **Antora** as the static site generator with **AsciiDoc** content files.

## Quick Reference

| Task | Command |
|------|---------|
| Install dependencies | `make environment` |
| Build locally | `make local` |
| Build with feature flags | `make local-stackpacks2` |
| Preview site | `make preview` |
| Clean build | `make clean` |

## Build Commands

### Initial Setup

```bash
# Clone with submodules (required - contains UI bundle and shared attributes)
git clone --recursive <repo>
cd stackstate-product-docs

# Install Node.js dependencies
make environment
```

### Building the Site

```bash
# Local development build
make local

# Build with stackpacks2 feature flag enabled
make local-stackpacks2

# Production build (uses remote playbook)
make remote
```

### Previewing

```bash
# Start local HTTP server on port 8080
make preview

# Or manually open build/site/index.html in browser
```

### Testing

There are no automated tests in this repository. Quality assurance is done through:
- Local preview builds (`make local` + `make preview`)
- Visual review of generated documentation
- GitHub Pages deployment preview on merge to main

## Project Structure

```
docs/
└── latest/
    ├── antora.yml              # Component descriptor
    └── modules/en/
        ├── nav.adoc            # Navigation structure
        ├── pages/              # Documentation content (.adoc files)
        ├── partials/           # Reusable content snippets
        ├── images/             # Images for documentation
        └── attachments/        # Downloadable files
shared/                         # Shared content module
product-docs-common/            # [SUBMODULE] Global attributes, extensions
dsc-style-bundle/               # [SUBMODULE] UI theme/styling
```

## AsciiDoc Content Guidelines

### File Header Format

Every `.adoc` file must start with a title and metadata:

```asciidoc
= Page Title
:revdate: YYYY-MM-DD
:page-revdate: {revdate}
:description: Brief description for SEO
```

The `:revdate:` should be updated when content is modified.

### Cross-References

Use `xref:` macro for internal links:

```asciidoc
xref:path/to/file.adoc[Link Text]
xref:/setup/install-stackstate/requirements.adoc[Requirements]
```

- Paths are relative to the `pages/` directory
- Leading `/` is optional but recommended for clarity

### Product Names

Always use attribute variables from `product-docs-common/global-attributes.yml`:

```asciidoc
{stackstate-product-name}    // "SUSE Observability"
{rancher-product-name}       // "SUSE Rancher Prime"
```

Never hardcode product names - use attributes for consistency and rebrandability.

### Feature Flags

Conditional content uses `ifdef`/`endif`:

```asciidoc
ifdef::ss-ff-stackpacks2_enabled[]
Content only shown when feature flag is enabled
endif::ss-ff-stackpacks2_enabled[]
```

Feature flags are set in `ss-local-playbook.yml`.

### Section Structure

```asciidoc
= Page Title (Level 0 - only one per file)

== Major Section (Level 1)

=== Subsection (Level 2)

==== Minor Section (Level 3)
```

### Code Blocks

Specify language for syntax highlighting:

```asciidoc
[,bash]
----
kubectl create namespace suse-observability
----

[,yaml]
----
apiVersion: v1
kind: ConfigMap
----

[,text]
----
Plain text output
----
```

### Admonitions

```asciidoc
[NOTE]
====
Informational note content.
====

[WARNING]
====
Warning content.
====

[TIP]
====
Helpful tip content.
====
```

### Tables

```asciidoc
|===
| Header 1 | Header 2 | Header 3

| Cell 1
| Cell 2
| Cell 3
|===
```

### Tabs (for multi-platform instructions)

```asciidoc
[tabs]
====
Kubernetes::
+
--
Kubernetes-specific instructions here.
--
OpenShift::
+
--
OpenShift-specific instructions here.
--
====
```

### Partials (Reusable Content)

Include shared content with:

```asciidoc
include::partial$variables.adoc[]
include::latest@shared:en:partial$variables.adoc[]
```

## Navigation

The site navigation is defined in `docs/latest/modules/en/nav.adoc`:

```asciidoc
* xref:page.adoc[Section Title]
** xref:subpage.adoc[Subsection]
*** xref:subsubpage.adoc[Sub-subsection]
```

When adding new pages, update `nav.adoc` to include them in the navigation tree.

## Naming Conventions

- **File names**: Use lowercase with hyphens (e.g., `k8s-quick-start-guide.adoc`)
- **Kubernetes prefix**: Use `k8s-` for Kubernetes-related pages
- **Time series prefix**: Use `k8sTs-` for metrics/telemetry pages
- **README.adoc**: Used for section index pages

## Extensions in Use

- `@asciidoctor/tabs`: Tabbed content blocks
- `@antora/lunr-extension`: Site search
- `@sntke/antora-mermaid-extension`: Mermaid diagram support

### Mermaid Diagrams

```asciidoc
[mermaid]
----
graph TD
    A[Start] --> B[Process]
    B --> C[End]
----
```

## Important Notes

- **No automated tests**: Validate changes by building locally with `make local`
- **Submodules required**: Always clone with `--recursive` or run `git submodule update --init`
- **Node.js 18+**: Required for Antora build
- **Build output**: Generated site goes to `build/site/` (gitignored)
