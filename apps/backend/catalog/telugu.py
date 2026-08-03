"""Telugu names for catalog content, plus the search terms shoppers actually type.

Why a curated table rather than machine translation:

* Grocery vocabulary is small and bounded — a few hundred terms cover a kirana
  catalogue completely.
* Machine translation mangles exactly the words that matter. Brand names come
  back as literal nonsense ("Tata Tea" translated word-by-word), and staples
  like *dal*, *atta* or *ghee* have established Telugu names that a generic
  engine does not reliably produce.
* It costs nothing and needs no API key or billing.

`SEARCH_ALIASES` is separate from the display name on purpose: it holds the
romanised spellings people type on an English keyboard ("biyyam", "pappu"),
which must be searchable but must never be shown as a product name.
"""

#: English (lowercased) -> Telugu display name.
TELUGU = {
    # ── staples ──
    "rice": "బియ్యం",
    "basmati rice": "బాస్మతి బియ్యం",
    "sona masoori rice": "సోనా మసూరి బియ్యం",
    "wheat": "గోధుమలు",
    "atta": "గోధుమ పిండి",
    "wheat flour": "గోధుమ పిండి",
    "maida": "మైదా",
    "rava": "రవ్వ",
    "sooji": "రవ్వ",
    "poha": "అటుకులు",
    "sugar": "పంచదార",
    "jaggery": "బెల్లం",
    "salt": "ఉప్పు",
    # ── pulses ──
    "dal": "పప్పు",
    "toor dal": "కంది పప్పు",
    "moong dal": "పెసర పప్పు",
    "urad dal": "మినప పప్పు",
    "chana dal": "శనగ పప్పు",
    "masoor dal": "మసూర్ పప్పు",
    "pulses": "పప్పు ధాన్యాలు",
    "peanut": "వేరుశనగ",
    "groundnut": "వేరుశనగ",
    # ── oils & dairy ──
    "oil": "నూనె",
    "cooking oil": "వంట నూనె",
    "sunflower oil": "పొద్దుతిరుగుడు నూనె",
    "groundnut oil": "వేరుశనగ నూనె",
    "coconut oil": "కొబ్బరి నూనె",
    "ghee": "నెయ్యి",
    "butter": "వెన్న",
    "milk": "పాలు",
    "curd": "పెరుగు",
    "yogurt": "పెరుగు",
    "paneer": "పన్నీర్",
    "cheese": "చీజ్",
    "dairy": "పాల ఉత్పత్తులు",
    "eggs": "గుడ్లు",
    "egg": "గుడ్డు",
    # ── vegetables & fruit ──
    "vegetables": "కూరగాయలు",
    "fresh vegetables": "తాజా కూరగాయలు",
    "onion": "ఉల్లిపాయ",
    "potato": "బంగాళదుంప",
    "tomato": "టమాటా",
    "brinjal": "వంకాయ",
    "okra": "బెండకాయ",
    "ladies finger": "బెండకాయ",
    "carrot": "క్యారెట్",
    "cabbage": "క్యాబేజీ",
    "cauliflower": "కాలీఫ్లవర్",
    "spinach": "పాలకూర",
    "greens": "ఆకుకూరలు",
    "chilli": "మిర్చి",
    "green chilli": "పచ్చిమిర్చి",
    "ginger": "అల్లం",
    "garlic": "వెల్లుల్లి",
    "lemon": "నిమ్మకాయ",
    "coriander": "కొత్తిమీర",
    "curry leaves": "కరివేపాకు",
    "fruits": "పండ్లు",
    "fresh fruits": "తాజా పండ్లు",
    "banana": "అరటిపండు",
    "apple": "ఆపిల్",
    "mango": "మామిడి",
    "orange": "నారింజ",
    "grapes": "ద్రాక్ష",
    "watermelon": "పుచ్చకాయ",
    "papaya": "బొప్పాయి",
    "pomegranate": "దానిమ్మ",
    # ── spices ──
    "spices": "మసాలా దినుసులు",
    "masala": "మసాలా",
    "turmeric": "పసుపు",
    "turmeric powder": "పసుపు పొడి",
    "chilli powder": "కారం",
    "coriander powder": "ధనియాల పొడి",
    "cumin": "జీలకర్ర",
    "mustard": "ఆవాలు",
    "pepper": "మిరియాలు",              # black pepper, the spice
    "black pepper": "మిరియాలు",
    "bell pepper": "క్యాప్సికం",         # NOT మిరియాలు — a different vegetable
    "green bell pepper": "పచ్చి క్యాప్సికం",
    "capsicum": "క్యాప్సికం",
    "tamarind": "చింతపండు",
    "asafoetida": "ఇంగువ",
    # ── packaged / beverages ──
    "tea": "టీ",
    "coffee": "కాఫీ",
    "biscuits": "బిస్కెట్లు",
    "snacks": "స్నాక్స్",
    "namkeen": "నమ్‌కీన్",
    "chips": "చిప్స్",
    "chocolate": "చాక్లెట్",
    "juice": "జ్యూస్",
    "water": "నీరు",
    "soft drinks": "శీతల పానీయాలు",
    "beverages": "పానీయాలు",
    "noodles": "నూడుల్స్",
    "pasta": "పాస్తా",
    "bread": "బ్రెడ్",
    "honey": "తేనె",
    "pickle": "ఊరగాయ",
    "papad": "అప్పడం",
    # ── household & personal care ──
    "soap": "సబ్బు",
    "detergent": "డిటర్జెంట్",
    "shampoo": "షాంపూ",
    "toothpaste": "టూత్‌పేస్ట్",
    "household": "గృహోపకరణాలు",
    "cleaning": "శుభ్రపరచడం",
    "personal care": "వ్యక్తిగత సంరక్షణ",
    "baby care": "శిశు సంరక్షణ",
    "stationery": "స్టేషనరీ",
    # ── category-ish umbrella terms ──
    # ── compound category names (exact, so nothing is silently dropped) ──
    "staples & cooking": "నిత్యావసరాలు & వంట సామాగ్రి",
    "milk & cream": "పాలు & క్రీమ్",
    "oils & ghee": "నూనెలు & నెయ్యి",
    "rice & grains": "బియ్యం & ధాన్యాలు",
    "tea & coffee": "టీ & కాఫీ",
    "honey & spreads": "తేనె & స్ప్రెడ్‌లు",
    "frozen desserts": "ఫ్రోజెన్ డెజర్ట్‌లు",
    "paper & cleaning": "పేపర్ & శుభ్రత",
    "herbs & seasonings": "మూలికలు & మసాలాలు",
    "meat & seafood": "మాంసం & సముద్ర ఆహారం",
    "health foods": "ఆరోగ్య ఆహారం",
    "pet care": "పెంపుడు జంతువుల సంరక్షణ",
    "chicken": "చికెన్",
    "red meat": "ఎర్ర మాంసం",
    "seafood": "సముద్ర ఆహారం",
    "juices": "జ్యూస్‌లు",
    "orange juice": "నారింజ జ్యూస్",
    "drinking water": "తాగునీరు",
    "avocado": "అవకాడో",
    "avacados": "అవకాడో",
    "grocery": "కిరాణా",
    "groceries": "కిరాణా సామాను",
    "staples": "నిత్యావసరాలు",
    "essentials": "నిత్యావసరాలు",
    "frozen": "ఫ్రోజెన్",
    "bakery": "బేకరీ",
    "organic": "సేంద్రియ",
    "combo": "కాంబో",
    "offers": "ఆఫర్లు",
}

#: English term -> extra searchable spellings (romanised Telugu, synonyms).
#: Display never uses these; search does.
SEARCH_ALIASES = {
    "rice": ["biyyam", "బియ్యం", "chawal"],
    "wheat": ["godhuma", "gehu"],
    "atta": ["godhuma pindi", "pindi"],
    "dal": ["pappu", "పప్పు"],
    "toor dal": ["kandi pappu"],
    "moong dal": ["pesara pappu"],
    "urad dal": ["minapa pappu"],
    "chana dal": ["senaga pappu"],
    "oil": ["nune", "నూనె", "tel"],
    "ghee": ["neyyi", "నెయ్యి"],
    "milk": ["paalu", "పాలు", "doodh"],
    "curd": ["perugu", "పెరుగు", "dahi"],
    "sugar": ["panchadara", "cheeni"],
    "jaggery": ["bellam", "బెల్లం", "gud"],
    "salt": ["uppu", "ఉప్పు", "namak"],
    "onion": ["ullipaya", "pyaz"],
    "potato": ["bangaladumpa", "aloo"],
    "tomato": ["tamata"],
    "chilli": ["mirchi", "మిర్చి"],
    "turmeric": ["pasupu", "పసుపు", "haldi"],
    "tamarind": ["chintapandu"],
    "coriander": ["kothimeera", "dhania"],
    "curry leaves": ["karivepaku"],
    "tea": ["chai", "టీ"],
    "eggs": ["gudlu", "anda"],
    "vegetables": ["kuragayalu", "sabzi"],
    "fruits": ["pandlu", "phal"],
    "soap": ["sabbu"],
}


def _lookup(text, table):
    """Longest-match lookup, case-insensitive, ignoring surrounding punctuation."""
    if not text:
        return None
    key = text.strip().lower()
    if key in table:
        return table[key]
    # Partial matching is deliberately conservative. Falling back to a single
    # word inside a compound name silently changes its meaning — "Green Bell
    # Pepper" matched "pepper" and became the Telugu for *black pepper*, and
    # "Oils & Ghee" collapsed to just "ghee". A wrong translation is worse than
    # an untranslated one, so a name joined by "&"/"and" must match exactly.
    words = key.replace("-", " ").split()
    if any(w in ("&", "and", "with", "+") for w in words):
        return None

    # Otherwise allow a trailing size/pack qualifier to be ignored:
    # "Sona Masoori Rice 5kg" -> "rice", but only via a genuine head noun.
    for size in range(len(words), 0, -1):
        for start in range(0, len(words) - size + 1):
            phrase = " ".join(words[start:start + size])
            if phrase in table:
                # A single-word match is only trusted when it is the LAST
                # meaningful word (the head noun in English), not an adjective
                # buried mid-name.
                if size == 1 and start != len(words) - 1:
                    continue
                return table[phrase]
    return None


def telugu_name(english):
    """Telugu display name for an English catalog name, or None if unknown.

    A partial match is used deliberately: "Sona Masoori Rice 5kg" resolves via
    "rice" so a shopper still sees a Telugu word rather than nothing. Anything
    unmatched is left blank so it falls back to English — a wrong translation is
    worse than an untranslated one.
    """
    return _lookup(english, TELUGU)


def search_aliases(english):
    """Extra searchable spellings for an English catalog name."""
    hit = _lookup(english, SEARCH_ALIASES)
    return list(hit) if hit else []
