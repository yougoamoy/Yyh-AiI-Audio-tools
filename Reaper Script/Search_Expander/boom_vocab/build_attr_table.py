import csv, re
from collections import Counter, defaultdict

SCRIPT_DIR = r"G:\AI\Yyh-AiI-Audio-tools\Reaper Script\Search_Expander\boom_vocab"
CSV_PATH = SCRIPT_DIR + "/descriptions.csv"
OUTPUT_PATH = SCRIPT_DIR + "/attr_words_table.csv"

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
    "mono","stereo","wav","sanken","co","k","hz","khz","db",
    "mid","side","left","right","channel","channels",
    "high","frequency","response","sample","rate","bit",
    "recording","recorded","record","mic","microphone",
    "close","distant","field","contact",
    "wild","various","multiple","single","one","two","three",
    "first","second","third","end","beginning","middle",
    "male","female","adult","young","baby","small","large",
    "foot","feet","hand","hands","home","studio",
}

CATEGORY_SEEDS = {
    "Duration": ["long","short","brief","sustained","momentary","prolonged","extended","quick","slow","fast","rapid","swift","gradual","fleeting","lasting","enduring","continuous","intermittent","lengthy","shorter","longer"],
    "Intensity": ["heavy","light","hard","soft","intense","mild","subtle","powerful","gentle","fierce","strong","weak","forceful","delicate","violent","moderate","extreme","slight","faint","loud","quiet","forcefully","aggressively","brutal","savage","tender","vigorous","heavily","lightly","strongly","softly"],
    "Texture": ["gritty","smooth","grainy","crisp","rough","silky","metallic","woody","glassy","fuzzy","velvety","coarse","fine","textured","polished","raw","organic","synthetic","clean","dirty","pristine","crunchy","squishy","flaky","chunky","powdery","slimy","crusty","glossy","wet","dry","chalky","sandy","muddy"],
    "Attack": ["sharp","punchy","abrupt","sudden","swift","snappy","explosive","percussive","tight","loose","immediate","delayed","precise","sloppy","mushy","bite","snap","click","thud","smack","slap","tap","strike"],
    "Pitch": ["deep","bright","thin","thick","bass","treble","dull","muddy","boomy","nasal","throaty","airy","breathy","tonal","atonal","resonant","dissonant","harmonic","inharmonic","pitched","unpitched","droning","buzzing","ringing","singing","whining","humming"],
    "Shape": ["hollow","solid","dense","full","empty","round","flat","wide","narrow","compact","diffuse","focused","scattered","concentrated","spread","layered","stacked","nested","cascading","clustered","isolated","sparse"],
    "Movement": ["rising","falling","pulsing","steady","erratic","oscillating","sweeping","swirling","spiraling","bouncing","rolling","sliding","gliding","drifting","flowing","streaming","gushing","trickling","dripping","plunging","soaring","diving","creeping","crawling","stuttering","staccato","legato","vibrato","tremolo","fluttering","flapping","wobbling","shaking","trembling","quivering","pulsating","throbbing","surging","ebbing","waxing","waning","fading","blooming"],
    "Space": ["wide","narrow","enveloping","surrounding","immersive","panoramic","localized","directional","ambient","atmospheric","spacious","cramped","open","enclosed","contained","vast","intimate"],
    "Mood": ["aggressive","calm","eerie","warm","cold","harsh","soothing","menacing","playful","dark","ominous","ethereal","ghostly","haunting","dreamy","nightmarish","peaceful","chaotic","serene","turbulent","sinister","cheerful","gloomy","mysterious","magical","ancient","futuristic","industrial","natural","mechanical","robotic","alien","exotic","apocalyptic","epic","cinematic","dramatic","heroic","tragic","whimsical"],
    "Voice": ["throaty","nasal","breathy","airy","guttural","raspy","hoarse","whispering","murmuring","muttering","growling","snarling","grunting","hissing","squeaking","chirping","clicking","chattering","babbling","cooing","howling","wailing","moaning","groaning","sighing","panting","gasping","choking","coughing","screaming","shrieking","yelling","barking","roaring","bellowing","croaking","singing","humming","whistling"],
    "Liquid": ["bubbling","splashing","dripping","trickling","gurgling","foaming","frothing","churning","swirling","rippling","lapping","sloshing","spilling","pouring","streaming","flowing","gushing","spraying","misting","soaking","drenching","submerged"],
    "Material": ["wooden","stone","concrete","plastic","rubber","leather","fabric","cloth","paper","cardboard","foam","ceramic","porcelain","crystal","bone","bamboo","coral","shell","marble","granite","sand","dirt","mud","clay","ice","snow","frost"],
}

WORD_TO_CAT = {}
for cat, words in CATEGORY_SEEDS.items():
    for w in words:
        WORD_TO_CAT[w.lower()] = cat

def extract_words(text):
    text = text.lower()
    words = re.findall(r"[a-z][a-z']*[a-z]+", text)
    return [w for w in words if len(w) >= 2 and w not in STOP_WORDS]

word_counter = Counter()
word_per_library = defaultdict(set)
word_examples = {}

with open(CSV_PATH, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        desc = row.get("description", "")
        lib = row.get("library", "")
        if not desc:
            continue
        words = extract_words(desc)
        seen_in_desc = set()
        for w in words:
            if w not in seen_in_desc:
                word_counter[w] += 1
                seen_in_desc.add(w)
            word_per_library[w].add(lib)
            if w not in word_examples:
                word_examples[w] = desc[:120]

filtered = {w: c for w, c in word_counter.items() if c >= 5}

rows = []
for word, count in sorted(filtered.items(), key=lambda x: -x[1]):
    cat = WORD_TO_CAT.get(word, "未分类")
    lib_count = len(word_per_library[word])
    example = word_examples.get(word, "")
    rows.append({"word": word, "category": cat, "count": count, "library_count": lib_count, "example": example})

cat_counts = Counter(r["category"] for r in rows)
total = len(word_counter)
kept = len(filtered)
print(f"总词汇量: {total}  (>=5次: {kept})")
print()
print("初步分类统计:")
for cat, cnt in sorted(cat_counts.items(), key=lambda x: -x[1]):
    print(f"  {cat:15s}: {cnt}")

with open(OUTPUT_PATH, "w", encoding="utf-8", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["word","category","count","library_count","example"])
    writer.writeheader()
    writer.writerows(rows)

print(f"输出: {OUTPUT_PATH} ({len(rows)} 条)")
