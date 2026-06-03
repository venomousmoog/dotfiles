# Release Summary Formatting Instructions

Source: Google Doc `1pCgujBI7BEAfJxxtkMxp1vqvrL7FLFF9U5IROFw3vhU`

## Change Markers

```
[+] <added new feature>
[=] <improved existing feature>
[-] removed feature
```

## Writing Style

- Focus on the effect of the change on the **end user**, not on engineers
- Use simple, non-technical language
- Do not itemize every change — combine similar changes or groups of changes together
- Do not link diffs in descriptions
- Read full diff descriptions to understand stacks and context of surrounding changes

## Sections

Create three sections using `###` headings:

1. **Agent Features** — changes that affect user interactions
2. **Timeline Features** — changes that affect events generated & stored
3. **System Features** — general stability and quality improvements

Limit to ~5 high-level items per category.

## Output Template

```markdown
Conveyors: `<conveyor_1>` (R<old> → R<new>) and `<conveyor_2>` (R<old> → R<new>)

### Agent Features (user interactions)

* [+] Description of new feature
* [=] Description of improvement
* [-] Description of removal

### Timeline Features (events generated & stored)

* [+] ...

### System Features (stability & quality)

* [+] ...
```

## Example Output

See `references/example_output.md` for a real example.
