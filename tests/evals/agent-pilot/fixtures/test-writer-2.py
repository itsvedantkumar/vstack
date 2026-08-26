def parse_csv_row(row):
    """Split a single CSV row into fields.

    Just fixed: previously split naively on every comma, which broke a
    quoted field containing a comma (e.g. '"Doe, Jane",42' produced three
    fields instead of two). Now a comma inside a double-quoted field is
    treated as part of the field, not a separator.
    """
    fields = []
    cur = ""
    in_quotes = False
    for ch in row:
        if ch == '"':
            in_quotes = not in_quotes
        elif ch == "," and not in_quotes:
            fields.append(cur)
            cur = ""
        else:
            cur += ch
    fields.append(cur)
    return fields
