"""Read and write the plain Lua tables the game's data files are made of.

Enough of Lua for `hull { ... }` files: tables, strings, numbers, booleans,
nil, comments. Lets the generator read existing ships as templates and check
its own output round-trips, with no Lua install needed."""

import re

_TOKEN = re.compile(r"""
    (?P<ws>\s+|--\[\[.*?\]\]|--[^\n]*) |
    (?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*') |
    (?P<num>-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<sym>[{}\[\]=,;()])
""", re.S | re.X)


def tokens(src):
    pos = 0
    out = []
    while pos < len(src):
        m = _TOKEN.match(src, pos)
        if not m:
            raise ValueError("can't read Lua at %r" % src[pos:pos + 30])
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        out.append((kind, m.group(kind)))
    return out


def _unquote(s):
    body = s[1:-1]
    return bytes(body, "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


class _Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

    def take(self, want=None):
        tok = self.t[self.i]
        if want and tok[1] != want:
            raise ValueError("expected %s, got %s" % (want, tok[1]))
        self.i += 1
        return tok

    def value(self):
        kind, v = self.peek()
        if v == "{":
            return self.table()
        self.take()
        if kind == "str":
            return _unquote(v)
        if kind == "num":
            n = float(int(v, 16)) if v.lower().startswith(("0x", "-0x")) else float(v)
            return int(n) if n.is_integer() and "." not in v and "e" not in v.lower() else n
        if v == "true":
            return True
        if v == "false":
            return False
        if v == "nil":
            return None
        raise ValueError("unexpected %s" % v)

    def table(self):
        self.take("{")
        arr, keyed = [], {}
        while self.peek()[1] != "}":
            kind, v = self.peek()
            if v == "[":
                self.take()
                k = self.value()
                self.take("]")
                self.take("=")
                keyed[k] = self.value()
            elif kind == "name" and self.peek(1)[1] == "=":
                self.take()
                self.take("=")
                keyed[v] = self.value()
            else:
                arr.append(self.value())
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        if keyed and arr:
            for n, x in enumerate(arr, 1):
                keyed[n] = x
            return keyed
        return keyed if keyed else arr


def read_calls(src):
    """Every `name { ... }` call in a data file, as (name, table)."""
    p = _Parser(tokens(src))
    out = []
    while p.i < len(p.t):
        kind, v = p.take()
        if kind == "name" and p.peek()[1] == "{":
            out.append((v, p.table()))
        elif kind == "name" and p.peek()[1] == "(" and p.peek(1)[1] == "{":
            p.take("(")
            out.append((v, p.table()))
            p.take(")")
    return out


IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def num(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int) or abs(v - round(v)) < 1e-6:
        return str(int(round(v)))
    return ("%.3f" % v).rstrip("0").rstrip(".")


def write(v, indent=""):
    """Lua source for a value, laid out the way the Shipyard export does."""
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return num(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, (list, tuple)):
        if not v:
            return "{}"
        items = [write(x, indent + "\t") for x in v]
        if all(not isinstance(x, (list, tuple, dict)) for x in v):
            return "{ " + ", ".join(items) + " }"
        return "{\n" + indent + "\t" + (",\n" + indent + "\t").join(items) + ",\n" + indent + "}"
    if isinstance(v, dict):
        pos = [v[k] for k in sorted(k for k in v if isinstance(k, int))]
        keys = [k for k in v if not isinstance(k, int)]
        items = [write(x, indent + "\t") for x in pos]
        for k in keys:
            key = k if IDENT.match(k) else "[" + write(k) + "]"
            items.append(key + " = " + write(v[k], indent + "\t"))
        one = "{ " + ", ".join(items) + " }"
        if len(one) < 100 and "\n" not in one:
            return one
        return "{\n" + indent + "\t" + (",\n" + indent + "\t").join(items) + ",\n" + indent + "}"
    raise TypeError(type(v))
