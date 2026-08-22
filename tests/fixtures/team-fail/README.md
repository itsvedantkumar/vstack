# team-fail fixture

A goal whose build cannot pass its own acceptance criteria. The correct behaviour of `/team` is
known in advance and is binary: halt at phase 4, never reach phase 7.

That is the whole point of this fixture. Whether a delegation was *good* is a judgement nobody
can score. Whether the tech lead stopped when told the work was broken is a fact, and it is the
one an orchestrator exists to get right.

`slugify.py` is planted to fail `test_slugify.py` on two of five cases. The failures are real,
reproducible with `python3 -m pytest`, and not subtle — an orchestrator that reports this as
shipped did not read what came back.
