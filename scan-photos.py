"""扫描 photos/ 目录，提取 EXIF 拍摄时间，生成按时间排序的 photos.js。

用法：
    python scan-photos.py        # 扫描并生成 photos.js
    python scan-photos.py --asc  # 时间升序（旧→新），默认降序（新→旧）

依赖（可选）：
    pip install Pillow            # 安装后可读取 EXIF 拍摄时间，更准确
"""
import os
import re
import json
import argparse
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PHOTOS_DIR = SCRIPT_DIR / 'photos'
OUTPUT_FILE = SCRIPT_DIR / 'photos.js'

EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff', '.tif', '.heic', '.heif', '.avif'}

# EXIF tags
EXIF_DATETIME_ORIGINAL = 36867
EXIF_DATETIME_DIGITIZED = 36868
EXIF_DATETIME = 306


def extract_date_exif(filepath: Path) -> str | None:
    """通过 PIL/Pillow 提取 EXIF 拍摄日期。返回格式 'YYYY:MM:DD HH:MM:SS'"""
    try:
        from PIL import Image
        img = Image.open(filepath)
        exif = img.getexif()
        if exif:
            for tag in (EXIF_DATETIME_ORIGINAL, EXIF_DATETIME_DIGITIZED, EXIF_DATETIME):
                val = exif.get(tag)
                if val and isinstance(val, str):
                    return val  # e.g. "2026:06:10 13:21:11"
    except Exception:
        pass
    return None


def extract_date_filename(filepath: Path) -> str | None:
    """从文件名中提取日期。支持常见命名模式。"""
    name = filepath.stem
    patterns = [
        r'(\d{4})[-.](\d{2})[-.](\d{2})[-_.\s]*(\d{2})?[-.:]?(\d{2})?[-.:]?(\d{2})?',  # 2026-01-24 15.07.14
        r'(\d{4})(\d{2})(\d{2})[-_.\s]*(\d{2})?(\d{2})?(\d{2})?',  # 20260124_150714
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
    """用文件修改时间作为最后兜底。"""
    import datetime
    ts = os.path.getmtime(filepath)
    dt = datetime.datetime.fromtimestamp(ts)
    return dt.strftime('%Y:%m:%d %H:%M:%S')


def extract_date(filepath: Path) -> tuple[str, str]:
    """
    按优先级提取拍摄日期：EXIF > 文件名 > 文件时间。
    返回 (date_string, source_label)
    """
    d = extract_date_exif(filepath)
    if d:
        return d, 'EXIF'
    d = extract_date_filename(filepath)
    if d:
        return d, '文件名'
    return extract_date_mtime(filepath), '文件时间'


def scan(ascending: bool = False):
    if not PHOTOS_DIR.exists():
        print(f'[!] 目录不存在: {PHOTOS_DIR}')
        print('    请先创建 photos/ 文件夹并放入照片')
        return

    files = []
    unknown = []
    for f in sorted(PHOTOS_DIR.iterdir()):
        if f.is_file() and f.suffix.lower() in EXTENSIONS:
            date_str, source = extract_date(f)
            rel = f.relative_to(SCRIPT_DIR).as_posix()
            files.append({
                'src': rel,
                'alt': f.stem,
                'date': date_str,
                '_source': source,
            })

    if not files:
        print('[!] photos/ 目录中没有找到图片文件')
        print('    支持的格式: ' + ', '.join(sorted(EXTENSIONS)))
        return

    # 按日期排序
    files.sort(key=lambda x: x['date'], reverse=not ascending)

    # 生成 JS
    entries_list = []
    for f in files:
        source = f.pop('_source')
        # 格式化为可读的 YYYY-MM-DD 给 JS 用
        d = f['date']
        display_date = d[:10].replace(':', '-') if len(d) >= 10 else d
        f['date'] = display_date
        entries_list.append(json.dumps(f, ensure_ascii=False))
        print(f'  [{source}] {display_date}  {f["src"]}')

    direction = '↓ 新→旧' if not ascending else '↑ 旧→新'
    entries = ',\n  '.join(entries_list)
    content = f'''// 巴巴博一的时光机 — 照片列表（由 scan-photos.py 自动生成）
// 共 {len(files)} 张 | 排序: 拍摄时间 {direction} | 添加新照片后重新运行扫描脚本即可
var PHOTOS = [
  {entries}
];
'''
    OUTPUT_FILE.write_text(content, encoding='utf-8')
    print(f'\n[OK] 已生成 {OUTPUT_FILE.name} — {len(files)} 张照片')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='扫描照片目录生成 photos.js')
    parser.add_argument('--asc', action='store_true', help='时间升序排列（旧→新），默认降序')
    args = parser.parse_args()
    scan(ascending=args.asc)
