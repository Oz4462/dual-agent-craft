def slugify(text: str) -> str:
    text = text.strip().lower()
    parts: list[str] = []
    current: list[str] = []

    for char in text:
        if char.isalnum():
            current.append(char)
        elif current:
            parts.append("".join(current))
            current = []

    if current:
        parts.append("".join(current))

    return "-".join(parts)


if __name__ == "__main__":
    assert slugify("Hello World") == "hello-world"
    assert slugify("  A_B  c ") == "a-b-c"
    slugify("äÄ!!ö")
    assert slugify("") == ""
    print("OK")