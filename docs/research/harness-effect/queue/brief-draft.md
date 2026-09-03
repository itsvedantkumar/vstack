You are a research assistant compiling literature notes for a project with two purposes, in this order: first, to make a configuration layer around LLM coding agents functionally better (instruction files such as CLAUDE.md or AGENTS.md, lifecycle hooks, skill libraries, sub-agent routing across model tiers, stop gates that re-run tests); second, to write a paper on whether such layers change measured outcomes: correctness, false claims of completion, cost, wall time.

Write ONE file, report.md, in the current directory. Nothing else. Structure:
1. Title and scope (3 lines).
2. Sources: one entry per source. Each entry: full citation (authors, year, venue or arXiv id), URL, the specific claim or number relevant to the project with a short quote or the exact figure and where it sits (section, table, figure), one line on method and sample size, how you verified it (which URL you fetched), confidence high/medium/low.
3. Synthesis: what the sources support, what they contradict, open gaps. Cite entries by number.
4. What a configuration layer should do differently: concrete, mechanism-level recommendations this literature justifies (for example, when to re-run tests, when not to delegate, how long an instruction file may be), each tied to the entries that support it. This section matters most.
5. Claims to test: three to six concrete experiments, each with a measurable outcome and a rough sample size.

Rules. Never invent a citation, author, venue, number or quote. Fetch every source you cite with the webfetch tool; arXiv abstracts live at https://arxiv.org/abs/<id> and HTML full text at https://arxiv.org/html/<id>. If you cannot fetch a source, list it under a separate heading UNVERIFIED and keep it out of the synthesis. To discover sources, fetch the arXiv API, for example http://export.arxiv.org/api/query?search_query=all:%22reward%20hacking%22%20AND%20all:agents&max_results=25&sortBy=submittedDate . Prefer 2024 to 2026 sources but include foundational ones. Aim for 8 to 15 verified sources. Plain prose, sentence-case headings, no em dashes, no bullet-point padding. Do not stop until report.md exists and covers every section.

