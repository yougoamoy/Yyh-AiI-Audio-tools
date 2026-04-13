"""
从 Boom Library metadata xlsx/xls 文件中提取所有描述文本
输出: corpus.txt（每行一条描述）
     stats.txt（各库统计）
     descriptions.csv（带年份权重的详细数据）
"""

import os
import glob
import sys

sys.stdout.reconfigure(encoding="utf-8")

SCRIPT_DIR = r"G:\AI\Yyh-AiI-Audio-tools\Reaper Script\Search_Expander\boom_vocab"
SOURCE_DIR = r"G:\AI\Yyh-AiI-Audio-tools\Reaper Script\Search_Expander\boom source"
CORPUS_FILE = os.path.join(SCRIPT_DIR, "corpus.txt")
STATS_FILE = os.path.join(SCRIPT_DIR, "stats.txt")
DETAIL_FILE = os.path.join(SCRIPT_DIR, "descriptions.csv")

# 已知年份（TrackYear 或根据 CK/DS 配对推断）
LIB_YEARS = {
    "00_Alien_Life_CK_Metadata.xlsx": "2024",
    "00_Alien_Life_DS_Metadata.xlsx": "2024",
    "00_Anime_Essentials_Metadata.xlsx": "2024",
    "00_Aquatic_Predators_Metadata.xlsx": "2022",
    "00_Brute_Force_Metadata.xlsx": "2021",
    "00_BOP_Metadata.xls": "2017",
    "00_BabyBoom_Metadata.xls": "2017",
    "00_CECK_Metadata.xls": "2018",
    "00_CEDS Metadata.xls": "2018",
    "00_Cannons_CK_Metadata.xlsx": "2023",
    "00_Cannons_DS_Metadata.xlsx": "2023",
    "00_Casual_UI_CK_Metadata.xlsx": "2024",
    "00_Casual_UI_DS_Metadata.xlsx": "2024",
    "00_Cinematic_Expressions_CK_Metadata.xlsx": "2022",
    "00_Cinematic_Expressions_DS_Metadata.xlsx": "2022",
    "00_Cinematic_Metal_Titan_CK_Metadata.xls": "2019",
    "00_Cinematic_Metal_Titan_DS_Metadata.xls": "2019",
    "00_Cinematic_Motion_Metadata_CK.xlsx": "2023",
    "00_Cinematic_Motion_Metadata_DS.xlsx": "2023",
    "00_Cinematic_Strikes_CK_Metdata.xls": "2019",
    "00_Cinematic_Strikes_DS_Metdata.xls": "2019",
    "00_Creature_Foley_CK_Metadata.xls": "2019",
    "00_Creature_Foley_DS_Metadata.xls": "2019",
    "00_Creatures_Humanoid_CK_Metadata.xlsx": "2022",
    "00_Creatures_Humanoid_DS_Metadata.xlsx": "2022",
    "00_Crowds_War_And_Battle_Metadata.xlsx": "2025",
    "00_Cyber_Weapons_CK_Metadata.xlsx": "2020",
    "00_Cyber_Weapons_DS_Metadata.xlsx": "2020",
    "00_Destruction_CK_Metadata.xls": "2017",
    "00_Destruction_DS_Metadata.xls": "2017",
    "00_Electric_Vehicles_Metadata.xlsx": "2024",
    "00_MA_CK_Metadata.xls": "2017",
    "00_MA_DS_Metadata.xls": "2017",
    "00_MAFCK_Metadata.xls": "2020",
    "00_MAFDS_Metadata.xls": "2020",
    "00_MATTER_Metadata.xlsx": "2023",
    "00_Magic_Alchemy_CK_Metadata.xlsx": "2025",
    "00_Magic_Alchemy_DS_Metadata.xlsx": "2025",
    "00_Magic_Wisp_CK_Metadata.xlsx": "2023",
    "00_Magic_Wisp_DS_Metadata.xlsx": "2023",
    "00_Mechanicals_DS_Metadata.xls": "2017",
    "00_Medieval_Melee_CK_Metadata.xlsx": "2022",
    "00_Medieval_Melee_DS_Metadata.xlsx": "2022",
    "00_Mutate_Organic_CK.xlsx": "2021",
    "00_Mutate_Organic_DS.xlsx": "2021",
    "00_NEON_Metadata.xls": "2020",
    "00_SciFi_Momentum_Metadata_CK.xlsx": "2023",
    "00_SciFi_Momentum_Metadata_DS.xlsx": "2023",
    "00_Silencers_DS_Metadata.xls": "2017",
    "00_Skate_Metadata.xlsx": "2020",
    "00_Superheroes_Speed_and_Strength_CK_Metadata.xlsx": "2025",
    "00_Superheroes_Speed_and_Strength_DS_Metadata.xlsx": "2025",
    "00_Toons_Metadata.xls": "2017",
    "00_Toy_Guns_Metadata.xlsx": "2021",
    "00_Violent_Combat_CK_Metadata.xlsx": "2025",
    "00_Violent_Combat_DS_Metadata.xlsx": "2025",
}


def get_tier(year_str):
    """根据年份返回权重分级"""
    try:
        y = int(year_str)
        if y >= 2024:
            return "new"
        if y >= 2021:
            return "mid"
        return "old"
    except (ValueError, TypeError):
        return "unknown"


def read_xlsx(filepath):
    """读取 xlsx 文件，返回 [{col: val, ...}, ...]"""
    import openpyxl

    wb = openpyxl.load_workbook(filepath, read_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    wb.close()
    if len(rows) < 2:
        return []
    headers = [str(h).strip() if h else "" for h in rows[0]]
    result = []
    for row in rows[1:]:
        entry = {}
        for i, val in enumerate(row):
            if i < len(headers) and headers[i]:
                entry[headers[i]] = str(val).strip() if val else ""
        result.append(entry)
    return result


def read_xls(filepath):
    """读取 xls 文件，返回 [{col: val, ...}, ...]"""
    import xlrd

    wb = xlrd.open_workbook(filepath)
    ws = wb.sheet_by_index(0)
    if ws.nrows < 2:
        return []
    headers = [str(ws.cell_value(0, c)).strip() for c in range(ws.ncols)]
    result = []
    for r in range(1, ws.nrows):
        entry = {}
        for c in range(ws.ncols):
            if headers[c]:
                entry[headers[c]] = str(ws.cell_value(r, c)).strip()
        result.append(entry)
    return result


def find_column(entry, *candidates):
    """在 entry 中查找第一个存在的候选列名"""
    for c in candidates:
        if c in entry and entry[c]:
            return entry[c]
    return ""


def main():
    xlsx_files = sorted(glob.glob(os.path.join(SOURCE_DIR, "*.xlsx")))
    xls_files = sorted(glob.glob(os.path.join(SOURCE_DIR, "*.xls")))
    all_files = xlsx_files + xls_files

    print(f"找到 {len(all_files)} 个文件")

    all_descriptions = []
    stats = []

    for filepath in all_files:
        fname = os.path.basename(filepath)
        try:
            if filepath.endswith(".xlsx"):
                entries = read_xlsx(filepath)
            else:
                entries = read_xls(filepath)
        except Exception as e:
            print(f"  跳过 {fname}: {e}")
            continue

        lib_descriptions = []
        for entry in entries:
            desc = find_column(entry, "Description", "BWDescription")
            if desc and desc not in ("", "Description", "None"):
                filename = find_column(entry, "Filename", "File Name")
                category = find_column(entry, "Category")
                subcategory = find_column(entry, "SubCategory")
                vendor = find_column(entry, "VendorCategory")
                fxname = find_column(entry, "FXName")

                # 年份：优先从文件读取，其次查表
                year = find_column(entry, "TrackYear", "Year")
                if not year:
                    year = LIB_YEARS.get(fname, "")

                lib_descriptions.append(
                    {
                        "file": filename,
                        "desc": desc,
                        "category": category,
                        "subcategory": subcategory,
                        "vendor": vendor,
                        "fxname": fxname,
                        "library": fname,
                        "year": year,
                        "tier": get_tier(year),
                    }
                )

        all_descriptions.extend(lib_descriptions)
        stats.append((fname, len(lib_descriptions), len(entries)))
        print(f"  {fname}: {len(lib_descriptions)}/{len(entries)} 条描述")

    # 写 corpus.txt
    with open(CORPUS_FILE, "w", encoding="utf-8") as f:
        for d in all_descriptions:
            f.write(d["desc"] + "\n")
    print(f"\ncorpus.txt: {len(all_descriptions)} 条描述")

    # 写 stats.txt
    with open(STATS_FILE, "w", encoding="utf-8") as f:
        f.write(f"总计: {len(all_descriptions)} 条描述, {len(stats)} 个文件\n\n")
        # 年份分布
        from collections import Counter
        tier_counter = Counter(d["tier"] for d in all_descriptions)
        f.write("权重分布:\n")
        for t in ["new", "mid", "old"]:
            f.write(f"  {t}: {tier_counter.get(t, 0)} 条\n")
        f.write(f"\n各库统计:\n")
        for name, desc_count, total_count in sorted(stats, key=lambda x: -x[1]):
            year = LIB_YEARS.get(name, "?")
            tier = get_tier(year)
            f.write(f"  {year} [{tier}] {name}: {desc_count}/{total_count}\n")
    print(f"stats.txt: 已生成")

    # 写 descriptions.csv（带年份权重的详细数据）
    with open(DETAIL_FILE, "w", encoding="utf-8") as f:
        f.write("library,year,tier,category,subcategory,vendor,fxname,file,description\n")
        for d in all_descriptions:
            line = ",".join(
                [
                    d["library"],
                    d["year"],
                    d["tier"],
                    d["category"],
                    d["subcategory"],
                    d["vendor"],
                    d["fxname"],
                    d["file"],
                    '"' + d["desc"].replace('"', '""') + '"',
                ]
            )
            f.write(line + "\n")
    print(f"descriptions.csv: 已生成")

    # 写 corpus_new.txt（仅 new 级别的描述，用于训练）
    CORPUS_NEW = os.path.join(SCRIPT_DIR, "corpus_new.txt")
    with open(CORPUS_NEW, "w", encoding="utf-8") as f:
        for d in all_descriptions:
            if d["tier"] == "new":
                f.write(d["desc"] + "\n")
    new_count = sum(1 for d in all_descriptions if d["tier"] == "new")
    print(f"corpus_new.txt: {new_count} 条（2024-2025 新库描述）")

    # 写 corpus_all_weighted.txt（new 重复3次，mid 重复1次，old 不重复）
    CORPUS_WEIGHTED = os.path.join(SCRIPT_DIR, "corpus_weighted.txt")
    with open(CORPUS_WEIGHTED, "w", encoding="utf-8") as f:
        for d in all_descriptions:
            repeats = {"new": 3, "mid": 1, "old": 0}.get(d["tier"], 0)
            for _ in range(repeats):
                f.write(d["desc"] + "\n")
    weighted_count = sum({"new": 3, "mid": 1, "old": 0}.get(d["tier"], 0) for d in all_descriptions)
    print(f"corpus_weighted.txt: {weighted_count} 条（new×3 + mid×1）")


if __name__ == "__main__":
    main()
