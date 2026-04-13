"""
从 descriptions.csv 提取去重词汇池
- Description 中的词 + Filename 中的词
- 按词频降序排列
- 每个词附带 2-3 条原始上下文示例
- 输出: word_pool.csv 和 word_pool.lua
"""

import csv
import re
from collections import Counter, defaultdict

SCRIPT_DIR = r"G:\AI\Yyh-AiI-Audio-tools\Reaper Script\Search_Expander\boom_vocab"
CSV_PATH = SCRIPT_DIR + "/descriptions.csv"
OUTPUT_CSV = SCRIPT_DIR + "/word_pool.csv"
OUTPUT_LUA = SCRIPT_DIR + "/word_pool.lua"

STOP_WORDS = {
    "the","a","an","and","or","of","in","on","at","to","for",
    "with","by","from","is","it","its","as","are","was","be",
    "been","being","have","has","had","do","does","did","will",
    "would","could","should","may","might","shall","can","not",
    "no","but","if","so","than","that","this","these","those",
    "which","what","who","whom","when","where","how","all",
    "each","every","both","few","more","most","other","some",
    "such","only","own","same","also","very","just","because",
    "between","through","during","before","after","above","below",
    "up","down","out","off","over","under","again","further",
    "then","once","here","there","into","onto","upon","via",
    "per","s","t","ll","re","ve","d","m",
    "mono","stereo","wav","co","k","hz","khz","db",
    "mid","side","left","right","channel","channels",
    "high","frequency","response","sample","rate","bit",
}

# Filename 中常见的 Boom 内部缩写代码，无实际语义
FILENAME_NOISE = {
    "dsgn","cfc","whsh","misc","ck","ds","alck","alds",
    "mick","mids","bfck","bfds","cwck","cwds","mmck","mmds",
    "bop","ceck","ceds","mabc","mabs","neon","sft","st",
    "b00m","anml","impct","foly","mchn","wthr","sci",
    "snd","fx","sfx","x","xx","xxx","idx","id","no",
}

def extract_words(text):
    """提取英文单词（小写，长度>=2）"""
    text = text.lower()
    words = re.findall(r"[a-z][a-z']*[a-z]+", text)
    return [w for w in words if len(w) >= 2 and w not in STOP_WORDS]

def extract_filename_words(filename):
    """从 UCS 风格文件名提取词（下划线/连字符分割，过滤缩写噪声）"""
    if not filename:
        return []
    # 去掉扩展名
    name = filename.rsplit(".", 1)[0]
    # 按下划线、连字符、驼峰分割
    parts = re.split(r"[_\-]+", name)
    words = []
    for p in parts:
        # 驼峰分割
        sub = re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?=[A-Z]|$)", p)
        for s in sub:
            s_lower = s.lower()
            if len(s_lower) >= 2 and s_lower not in STOP_WORDS and s_lower not in FILENAME_NOISE:
                words.append(s_lower)
    return words

# ---- 主流程 ----
word_counter = Counter()
word_desc_count = Counter()   # description 中出现次数
word_fn_count = Counter()     # filename 中出现次数
word_examples = defaultdict(list)  # word -> [desc snippets]
word_tier_max = {}  # word -> highest tier seen

TIER_ORDER = {"new": 3, "mid": 2, "old": 1, "unknown": 0}

with open(CSV_PATH, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        desc = row.get("description", "")
        filename = row.get("file", "")
        tier = row.get("tier", "unknown")

        # Description 词
        if desc:
            desc_words = extract_words(desc)
            seen = set()
            for w in desc_words:
                if w not in seen:
                    word_counter[w] += 1
                    word_desc_count[w] += 1
                    seen.add(w)
                # 保存上下文示例（最多3条，去重）
                if len(word_examples[w]) < 3:
                    snippet = desc[:150].replace('"', '""')
                    if snippet not in word_examples[w]:
                        word_examples[w].append(snippet)
                if w not in word_tier_max or TIER_ORDER.get(tier, 0) > TIER_ORDER.get(word_tier_max[w], 0):
                    word_tier_max[w] = tier

        # Filename 词（仅计数，不添加示例）
        if filename:
            fn_words = extract_filename_words(filename)
            seen_fn = set()
            for w in fn_words:
                if w not in seen_fn:
                    word_counter[w] += 1
                    word_fn_count[w] += 1
                    seen_fn.add(w)
                if w not in word_tier_max or TIER_ORDER.get(tier, 0) > TIER_ORDER.get(word_tier_max[w], 0):
                    word_tier_max[w] = tier

# 只保留有描述上下文的词（filename 独有词无法提供分拣语境）
pool_words = {w for w in word_counter if word_desc_count.get(w, 0) > 0}
total_words = len(pool_words)
total_all = len(word_counter)
print(f"总词汇: {total_all}, 有描述上下文: {total_words}, 仅文件名: {total_all - total_words}")

# 按词频排序
sorted_words = sorted(
    [(w, word_counter[w]) for w in pool_words],
    key=lambda x: -x[1]
)

# 判断来源
def get_source(w):
    has_desc = word_desc_count.get(w, 0) > 0
    has_fn = word_fn_count.get(w, 0) > 0
    if has_desc and has_fn:
        return "both"
    elif has_desc:
        return "desc"
    else:
        return "filename"

# ---- 输出 CSV ----
with open(OUTPUT_CSV, "w", encoding="utf-8", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["word", "count", "desc_count", "fn_count", "tier", "source", "example1", "example2", "example3"])
    for word, count in sorted_words:
        examples = word_examples.get(word, [])
        row = [
            word,
            count,
            word_desc_count.get(word, 0),
            word_fn_count.get(word, 0),
            word_tier_max.get(word, "unknown"),
            get_source(word),
        ]
        for i in range(3):
            row.append(examples[i] if i < len(examples) else "")
        writer.writerow(row)
print(f"CSV: {OUTPUT_CSV} ({len(sorted_words)} 条)")

# ---- 输出 Lua ----
with open(OUTPUT_LUA, "w", encoding="utf-8") as f:
    f.write("-- word_pool.lua\n")
    f.write("-- Boom Library 词汇池，由 build_word_pool.py 自动生成\n")
    f.write("-- 格式: { word=, count=, desc_count=, fn_count=, tier=, source=, examples= }\n\n")
    f.write("return {\n")
    for word, count in sorted_words:
        examples = word_examples.get(word, [])
        ex_parts = []
        for i, ex in enumerate(examples):
            escaped = ex.replace("\\", "\\\\").replace('"', '\\"')
            ex_parts.append(f'[{i+1}]="{escaped}"')
        ex_str = "{" + ",".join(ex_parts) + "}"
        f.write(f'  {{ word="{word}", count={count}, desc_count={word_desc_count.get(word,0)}, fn_count={word_fn_count.get(word,0)}, tier="{word_tier_max.get(word,"unknown")}", source="{get_source(word)}", examples={ex_str} }},\n')
    f.write("}\n")
print(f"Lua: {OUTPUT_LUA}")
