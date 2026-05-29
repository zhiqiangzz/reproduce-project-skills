# Paper running-example annotation

When a project ships a paper (PDF in `paper/`, `docs/`, or root), annotate the source code so a reader can follow the paper → code mapping.

## Locate the PDF

```bash
find . -maxdepth 3 -name '*.pdf' \
  ! -path './.git/*' ! -path './figures/*' \
  -print
```

If multiple PDFs, prefer:
1. `paper/main.pdf` / `paper/*.pdf`
2. `docs/<conference><year>.pdf` (e.g. `docs/SOSP19AE.pdf`)
3. Any PDF whose filename matches the repo name.

## Extract text

Try in this order:
- `pdftotext -layout <file.pdf> -` (most reliable, ships with `poppler-utils`; `uv pip install pdfminer.six` as a Python fallback)
- `python -c 'import pdfplumber; ...'` if `pdftotext` isn't available.

## Find the running example

Search the extracted text for section headers (case-insensitive):

- `Running Example`
- `Motivating Example`
- `Overview`
- `Background and Example`
- `Case Study`
- `Example` (only if it's a top-level section)

Grab the surrounding ~50 lines as context. Note any code identifiers — function names, class names, file names — quoted in `code style` or `Times-Italic`.

## Match to code

For each identifier from the paper text:

```bash
grep -rn "<identifier>" --include='*.py' --include='*.cc' --include='*.h' --include='*.cu' .
```

Score candidates:
- 3 points: identifier appears in an `examples/*.py` filename or top-level def
- 2 points: identifier appears in a function/class definition
- 1 point: identifier appears only inside a function body or comment

Pick the highest-scoring example file (usually `examples/<paper_running_example>.py`).

## Produce the annotated copy

```bash
cp examples/<chosen>.py examples/<chosen>_annotated.py
```

Then, **for each paragraph in the paper that describes a chunk of code**, insert a comment block above the matching code:

```python
# === Paper §3.2 / Figure 4 ============================================
# "We start with a single Conv2D layer and apply rule R3 to introduce a
#  parallel residual branch, as shown in Figure 4."
# ----------------------------------------------------------------------
weight2 = graph.new_weight(dims=(256, 16, 3, 3))
t2 = graph.conv2d(input=input, weight=weight2, ...)
```

Rules:
- Use `# === Paper §X.Y / Figure Z ===` as a recognisable banner so future readers can grep for `Paper §`.
- Quote at most 2 sentences from the paper per banner — long quotes drift out of fair use and clutter the file.
- Don't paraphrase. Quote literally, then add a one-line plain-language note if needed.
- Preserve the original file as `examples/<chosen>.py`; the annotated version is a copy.

## Verification

```bash
.venv/bin/python examples/<chosen>_annotated.py   # still runs
grep -c '^# === Paper §' examples/<chosen>_annotated.py  # >= 1
```
