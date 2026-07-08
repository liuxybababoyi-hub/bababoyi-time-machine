"""扫描 photos/ 目录，提取 EXIF 拍摄时间，自动生成缩略图，写 photos.js。

用法：
    python scan-photos.py        # 扫描并生成 photos.js + 缩略图
    python scan-photos.py --asc  # 时间升序（旧→新），默认降序（新→旧）

依赖（可选但推荐）：
    pip install Pillow            # 读取 EXIF + 生成缩略图
"""
import os
import re
import json
import argparse
from pathlib import Path

# 注册 HEIC/HEIF/AVIF 解码支持（微信图片、苹果设备照片）
from pillow_heif import register_heif_opener
register_heif_opener()

SCRIPT_DIR = Path(__file__).parent
PHOTOS_DIR = SCRIPT_DIR / 'photos'
THUMB_DIR = PHOTOS_DIR / 'thumbs'
PREVIEW_DIR = PHOTOS_DIR / 'previews'
OUTPUT_FILE = SCRIPT_DIR / 'photos.js'

MAX_THUMB_WIDTH = 800
MAX_PREVIEW_WIDTH = 2560
JPEG_QUALITY = 80

EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff', '.tif', '.heic', '.heif', '.avif'}

EXIF_DATETIME_ORIGINAL = 36867
EXIF_DATETIME_DIGITIZED = 36868
EXIF_DATETIME = 306

_has_pil = None

def has_pil():
    global _has_pil
    if _has_pil is None:
        try:
            from PIL import Image  # noqa: F401
            _has_pil = True
        except ImportError:
            _has_pil = False
    return _has_pil


# ── Date extraction ────────────────────────────────────────────

def extract_date_exif(filepath: Path) -> str | None:
    if not has_pil():
        return None
    try:
        from PIL import Image
        img = Image.open(filepath)
        exif = img.getexif()
        if exif:
            for tag in (EXIF_DATETIME_ORIGINAL, EXIF_DATETIME_DIGITIZED, EXIF_DATETIME):
                val = exif.get(tag)
                if val and isinstance(val, str):
                    return val
    except Exception:
        pass
    return None


def extract_date_filename(filepath: Path) -> str | None:
    name = filepath.stem
    patterns = [
        r'(\d{4})[-.](\d{2})[-.](\d{2})[-_.\s]*(\d{2})?[-.:]?(\d{2})?[-.:]?(\d{2})?',
        r'(\d{4})(\d{2})(\d{2})[-_.\s]*(\d{2})?(\d{2})?(\d{2})?',
    ]
    for pat in patterns:
        m = re.search(pat, name)
        if m:
            y, mo, d = m.group(1), m.group(2), m.group(3)
            hh = m.group(4) or '00'
            mm = m.group(5) or '00'
            ss = m.group(6) or '00'
            return f'{y}:{mo}:{d} {hh}:{mm}:{ss}'
    return None


def extract_date_mtime(filepath: Path) -> str:
    import datetime
    dt = datetime.datetime.fromtimestamp(os.path.getmtime(filepath))
    return dt.strftime('%Y:%m:%d %H:%M:%S')


def extract_date(filepath: Path) -> tuple[str, str]:
    d = extract_date_exif(filepath)
    if d:
        return d, 'EXIF'
    d = extract_date_filename(filepath)
    if d:
        return d, 'filename'
    return extract_date_mtime(filepath), 'mtime'


# ── Thumbnail generation ───────────────────────────────────────

def make_thumbnail(src: Path, dst: Path, max_w: int = MAX_THUMB_WIDTH, quality: int = JPEG_QUALITY):
    """Generate a JPEG thumbnail. Returns status string."""
    if not has_pil():
        return 'SKIP (pip install Pillow)'

    from PIL import Image
    img = Image.open(src)
    w, h = img.size

    if w <= max_w:
        # Still convert to JPEG (source might be PNG, and we always want .jpg output)
        if img.mode in ('RGBA', 'P', 'LA'):
            img = img.convert('RGB')
        elif img.mode != 'RGB':
            img = img.convert('RGB')
        img.save(dst, 'JPEG', quality=quality)
        img.close()
        return f'COPY ({w}x{h})'

    new_h = int(h * max_w / w)
    img.thumbnail((max_w, new_h), Image.LANCZOS)
    # Convert to RGB if needed (for PNG with alpha)
    if img.mode in ('RGBA', 'P', 'LA'):
        img = img.convert('RGB')
    img.save(dst, 'JPEG', quality=quality)
    img.close()
    return f'OK ({w}x{h} -> {max_w}x{new_h})'


# ── Main scan ───────────────────────────────────────────────────

def scan(ascending: bool = False):
    if not PHOTOS_DIR.exists():
        print(f'[!] photos/ not found: {PHOTOS_DIR}')
        print('    Create a photos/ folder and put images in it.')
        return

    THUMB_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    files = []
    for f in sorted(PHOTOS_DIR.iterdir()):
        if f.is_file() and f.suffix.lower() in EXTENSIONS:
            date_str, source = extract_date(f)
            rel_src = f.relative_to(SCRIPT_DIR).as_posix()

            # Thumbnail (800px)
            thumb_name = f.stem + '.jpg'
            thumb_path = THUMB_DIR / thumb_name
            thumb_rel = f'photos/thumbs/{thumb_name}'

            if not thumb_path.exists():
                status = make_thumbnail(f, thumb_path, MAX_THUMB_WIDTH)
                print(f'  [thumb] {status}  {thumb_name}')
            else:
                print(f'  [thumb] SKIP (exists)  {thumb_name}')

            # Preview (2560px)
            preview_name = f.stem + '.jpg'
            preview_path = PREVIEW_DIR / preview_name
            preview_rel = f'photos/previews/{preview_name}'

            if not preview_path.exists():
                status = make_thumbnail(f, preview_path, MAX_PREVIEW_WIDTH)
                print(f'  [preview] {status}  {preview_name}')
            else:
                print(f'  [preview] SKIP (exists)  {preview_name}')

            files.append({
                'src': rel_src,
                'thumb': thumb_rel,
                'preview': preview_rel,
                'alt': f.stem,
                'date': date_str,
                '_source': source,
            })

    if not files:
        print('[!] No images found in photos/')
        print('    Supported: ' + ', '.join(sorted(EXTENSIONS)))
        return
    if not has_pil():
        print('\n[!] Pillow not installed. Thumbnails & EXIF skipped.')
        print('    Run: pip install Pillow')

    # Sort by date
    files.sort(key=lambda x: x['date'], reverse=not ascending)

    entries_list = []
    for f in files:
        source = f.pop('_source')
        d = f['date']
        f['date'] = d[:10].replace(':', '-') if len(d) >= 10 else d
        entries_list.append(json.dumps(f, ensure_ascii=False))
        print(f'  [{source}] {f["date"]}  {f["src"]}')

    direction = 'newest first' if not ascending else 'oldest first'
    entries = ',\n  '.join(entries_list)
    content = f'''// Photo list for bababoyi-time-machine
// {len(files)} photos | sorted by date ({direction}) | auto-generated, re-run after adding photos
var PHOTOS = [
  {entries}
];
'''
    OUTPUT_FILE.write_text(content, encoding='utf-8')
    print(f'\n[OK] {OUTPUT_FILE.name} written — {len(files)} photos')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Scan photos, generate thumbnails & photos.js')
    parser.add_argument('--asc', action='store_true', help='Sort ascending (oldest first)')
    args = parser.parse_args()
    scan(ascending=args.asc)
