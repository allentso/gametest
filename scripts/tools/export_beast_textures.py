"""One-off: copy image/beast/* -> image/beasts/beast_{id}[_variant].png (PIL RGBA PNG)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "image" / "beast"
DST = ROOT / "assets" / "image" / "beasts"

PINYIN_TO_ID = {
    "zhulong": "001",
    "yinglong": "002",
    "fenghuang": "003",
    "baize": "004",
    "baihu": "005",
    "qilin": "006",
}

VARIANT_TO_SUFFIX = {
    "normal": "",
    "yiwen": "_yiwen",
    "xuancai": "_xuancai",
    "xuancai_yiwen": "_xuancai_yiwen",
}


def main():
    from PIL import Image

    DST.mkdir(parents=True, exist_ok=True)
    for p in sorted(SRC.iterdir()):
        if not p.is_file() or p.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
            continue
        stem = p.stem
        parts = stem.split("_", 1)
        if len(parts) != 2:
            print("skip (bad name):", p.name)
            continue
        py, var = parts[0], parts[1]
        bid = PINYIN_TO_ID.get(py)
        if not bid:
            print("skip (unknown pinyin):", p.name)
            continue
        suf = VARIANT_TO_SUFFIX.get(var)
        if suf is None:
            print("skip (unknown variant):", p.name)
            continue
        out_name = f"beast_{bid}{suf}.png"
        out_path = DST / out_name
        im = Image.open(p).convert("RGBA")
        im.save(out_path, "PNG")
        print(out_name, "<-", p.name)


if __name__ == "__main__":
    main()
