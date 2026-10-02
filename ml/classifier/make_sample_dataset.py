"""Writes ml/classifier/data/sample_reports.csv: a SAMPLE set of crowd report
descriptions for the incident type classifier (FR12, plan 10.4).

THIS IS NOT MDRRMD DATA. Every line is made up: phrases written for
development in English, Filipino, and Taglish, combined at random. It exists
so the whole pipeline (training, export, inference in the database and in
Dart) can be built and tested before the real labelled descriptions arrive
(thesis Table 3.1 item 6). Scores measured on it say how well the model
separates these made-up phrases, not how it will do on real reports. Replace
the file with the real set and retrain before reporting any accuracy.

Labels follow the thesis definitions:
  flood       rising water, residents trapped or unable to evacuate
  fire        active fire or smoke
  medical     injury, illness, or another health emergency
  structural  building, road, or infrastructure damage; debris blocking a route

Usage: python ml/classifier/make_sample_dataset.py
"""

import csv
import random
from pathlib import Path

SEED = 20261002
PER_CLASS = 300
OUT = Path(__file__).parent / "data" / "sample_reports.csv"

# Places are shared by every class, so a place name never gives the type away.
# Some hold words that matter elsewhere (tulay, covered court, health center).
PLACES = [
    "sa may España Blvd",
    "near the barangay hall",
    "along Taft Avenue",
    "sa kanto ng Dapitan at Blumentritt",
    "in Tondo near the market",
    "sa tapat ng simbahan",
    "behind the public school",
    "sa Baseco compound",
    "sa looban ng Sampaloc",
    "near Quiapo church",
    "sa ilalim ng tulay",
    "beside the covered court",
    "sa Pandacan",
    "at the corner of Recto and Rizal Avenue",
    "sa Sta. Mesa malapit sa riles",
    "near the health center",
    "sa Paco market",
    "in front of the elementary school",
    "sa Malate",
    "sa Port Area",
    "dito sa Barangay 412",
    "sa Barangay 105 Tondo",
    "on Lacson Avenue",
    "sa Legarda malapit sa LRT",
    "along Pedro Gil",
    "sa Binondo",
    "near the basketball court",
    "sa likod ng palengke",
    "sa eskinita namin",
    "in our street",
    "dito sa amin",
    "here in Sampaloc",
    "sa San Andres Bukid",
    "sa Sta. Ana",
    "near the creek",
    "sa tabi ng estero",
    "sa P. Noval",
    "along Quirino Avenue",
    "sa Vito Cruz",
    "near UST",
]

OPENERS = [
    "", "", "", "", "", "",
    "HELP!", "Help po.", "Emergency po.", "URGENT:", "Tulong!", "Tulong po.",
    "Report lang po:", "Good evening po,", "Good morning,", "Mga sir,",
    "Paki-check po,", "Attention MDRRMD:", "Saklolo!", "Pls help.",
]

CLOSERS = [
    "", "", "", "", "",
    "Please send help.", "Pakitulungan po kami.", "Kailangan namin ng rescue.",
    "May mga bata at matatanda dito.", "Urgent po.", "Pls hurry.", "Saklolo.",
    "Need help asap.", "Tulong po.", "Marami pong tao dito.",
    "Please respond.", "Pakibilisan po.", "Salamat po.", "Thank you.",
    "Wala pa pong dumarating.", "We have been waiting for an hour.",
    "Kanina pa po ito.", "Send someone please.", "Asap po sana.",
]

DEPTHS_EN = ["ankle", "knee", "waist", "chest", "neck"]
DEPTHS_FIL = ["sakong", "tuhod", "bewang", "dibdib", "leeg"]

CORES = {
    "flood": [
        # English
        "Flood water is rising fast {loc}",
        "The water is already {depth_en} deep {loc}",
        "Our street is flooded, {depth_en} high water",
        "We are trapped on the second floor because of the flood",
        "The creek overflowed and water is entering the houses {loc}",
        "A family is stuck on the roof and the flood keeps rising",
        "We cannot evacuate, the road is under water",
        "Flooding {loc}, vehicles can't pass",
        "The river is overflowing {loc}",
        "The flood reached our first floor, we need a boat",
        "Heavy rain since morning and the water level keeps going up {loc}",
        "Houses are submerged {loc}",
        "Strong current of flood water, people are stranded {loc}",
        "Water came in very fast, {depth_en} deep inside the house now",
        "Flash flood {loc}",
        # Filipino
        "Baha na {loc}, hanggang {depth_fil} na ang tubig",
        "Tumataas ang tubig {loc}",
        "Lubog na sa baha ang mga bahay {loc}",
        "Na-trap kami sa bubong dahil sa baha",
        "Umapaw na ang estero {loc}",
        "Hindi na kami makalabas, mataas na ang tubig",
        "Pumapasok na ang tubig baha sa loob ng bahay",
        "Umaapaw ang ilog at lumulubog na ang kalsada {loc}",
        "Hanggang {depth_fil} na ang baha {loc}",
        "Inaanod na ang mga gamit, malakas ang agos ng tubig",
        "Lampas tao na ang baha {loc}",
        "Binabaha kami, hindi makalikas ang pamilya ko",
        "Mabilis tumaas ang tubig, nasa ikalawang palapag na kami",
        "Bumabaha na naman {loc}, hindi madaanan",
        "Malalim na ang tubig {loc}, kailangan ng bangka",
        # Taglish
        "Grabe ang baha {loc}, hanggang {depth_fil} na",
        "Stranded kami dahil sa baha, di makadaan ang sasakyan",
        "Flooded na po {loc}, need rescue boat",
        "Rising pa rin ang tubig {loc}, trapped ang mga tao sa second floor",
        "Sobrang taas na ng baha, hindi makalikas ang mga residente",
        "{depth_en} deep na ang baha {loc}",
        "Baha po dito, pumasok na ang water sa bahay namin",
        "Nag-overflow ang creek {loc}, lubog na ang kalsada",
    ],
    "fire": [
        # English
        "There is a fire {loc}",
        "A house is on fire {loc}, the flames are spreading to the next houses",
        "Thick smoke is coming out of a building {loc}",
        "A fire broke out in the market {loc}",
        "An electric post is sparking and now burning {loc}",
        "Kitchen fire, the LPG tank might explode",
        "Big fire, several houses are burning {loc}",
        "Smoke and flames on the third floor of the building",
        "A warehouse is burning {loc}",
        "Grass fire spreading near the houses {loc}",
        "I can see flames from the roof of the store",
        "Something exploded and now there is a fire {loc}",
        "A jeepney caught fire {loc}",
        "Burning smell and black smoke from the transformer {loc}",
        "The fire is getting bigger and no fire truck yet",
        # Filipino
        "May sunog {loc}",
        "Nasusunog ang bahay {loc}, kumakalat na ang apoy",
        "Makapal na usok galing sa bodega {loc}",
        "Nagliliyab ang poste ng kuryente {loc}",
        "Sumabog ang tangke ng LPG, nasusunog na ang kusina",
        "Malaking sunog, maraming bahay ang natutupok {loc}",
        "May apoy sa ikatlong palapag ng gusali",
        "Umuusok ang kable ng kuryente at nag-aapoy na",
        "Tinutupok ng apoy ang mga barong-barong {loc}",
        "Nasusunog ang palengke {loc}",
        "Lumalaki ang apoy, wala pang bumbero",
        "May nasusunog na sasakyan {loc}",
        "Itim na usok at apoy galing sa bubong ng tindahan",
        "Nagsimula ang sunog sa kusina, mabilis kumalat",
        "Amoy sunog at may usok sa kabilang bahay",
        # Taglish
        "Sunog po {loc}, need ng bumbero",
        "May fire sa kapitbahay, kumakalat na ang apoy",
        "Nag-spark ang wire tapos nasunog ang bahay",
        "Ang kapal ng usok {loc}, may nasusunog na building",
        "May apoy sa stockroom, tumunog ang fire alarm",
        "Fire po dito, malaki na ang apoy",
        "Nasusunog ang warehouse {loc}, sobrang itim ng smoke",
        "Sumabog ang transformer {loc} tapos nagka-sunog",
    ],
    "medical": [
        # English
        "A man collapsed {loc} and is not breathing",
        "My father is having chest pain and can't breathe",
        "Someone is unconscious {loc}",
        "An old woman fainted, she needs an ambulance",
        "A child has a very high fever and is having a seizure",
        "A pregnant woman is in labor and cannot get to the hospital",
        "A man is bleeding badly from a head wound {loc}",
        "A motorcycle rider is injured, his leg is broken",
        "A person is having a stroke, half of the face is drooping",
        "Asthma attack, she can hardly breathe",
        "Someone was electrocuted and is not responding",
        "A boy was bitten by a dog and is bleeding",
        "An elderly man fell down the stairs and cannot move",
        "Vomiting and diarrhea, the children are very weak",
        "Diabetic patient is shaking and confused, needs a medic",
        # Filipino
        "May nahimatay {loc}, hindi na humihinga",
        "Inaatake sa puso ang tatay ko, masakit ang dibdib niya",
        "Walang malay ang isang lalaki {loc}",
        "Nanganganak na ang buntis, kailangan ng ambulansya",
        "Kinukumbulsyon ang bata, mataas ang lagnat",
        "Duguan ang ulo ng isang matanda matapos madulas",
        "Nabalian ng binti ang rider {loc}",
        "Hinihika ang anak ko, nahihirapang huminga",
        "Na-stroke ang lola ko, hindi maigalaw ang kalahati ng katawan",
        "Nakuryente ang isang lalaki, hindi na gumagalaw",
        "Nagsusuka at nagtatae ang mga bata, nanghihina na",
        "Nakagat ng aso ang bata, dumudugo ang sugat",
        "Nahulog sa hagdan ang lolo ko, hindi makatayo",
        "May sugatan {loc}, malalim ang sugat sa braso",
        "Nahihilo at naninikip ang dibdib ng nanay ko",
        # Taglish
        "Need ambulance po, may nag-collapse {loc}",
        "May injured na rider {loc}, dumudugo ang ulo",
        "Hirap huminga ang pasyente, need oxygen",
        "Unconscious ang lola ko, pakidala ng ambulansya",
        "Emergency po, inatake sa puso ang kapitbahay",
        "May seizure ang anak ko, need medic",
        "Buntis na manganganak na, wala kaming sasakyan papuntang hospital",
        "Dumudugo nang malakas ang sugat niya, need first aid",
    ],
    "structural": [
        # English
        "A wall collapsed {loc}",
        "Part of the building collapsed, people may be under the rubble",
        "There is a big crack on the bridge {loc}",
        "A tree fell and is blocking the road {loc}",
        "An electric post fell across the street {loc}",
        "The road caved in, there is a big sinkhole {loc}",
        "The roof of the covered court collapsed",
        "An old house is leaning and about to fall {loc}",
        "Debris is blocking the road {loc}, vehicles can't pass",
        "Scaffolding fell from the construction site {loc}",
        "A billboard fell on the road {loc}",
        "Soil and rocks slid down and covered the alley",
        "The footbridge is damaged and shaking {loc}",
        "A concrete fence fell on parked cars",
        "Cracks on the walls and posts of the building, it may collapse",
        # Filipino
        "Gumuho ang pader {loc}",
        "Bumagsak ang bahagi ng gusali, may natabunan",
        "May malaking bitak ang tulay {loc}",
        "Natumba ang puno at nakaharang sa kalsada {loc}",
        "Bumagsak ang poste ng kuryente sa kalye {loc}",
        "Lumubog ang kalsada, may malaking butas {loc}",
        "Bumigay ang bubong ng covered court",
        "Nakatagilid na ang lumang bahay, malapit nang gumuho",
        "Nakaharang ang mga debris sa daan {loc}",
        "Nabagsakan ng billboard ang kalsada {loc}",
        "Gumuho ang lupa at mga bato sa eskinita",
        "Sira ang tulay {loc}, delikadong daanan",
        "Bumagsak ang bakod na semento sa mga nakaparadang sasakyan",
        "May bitak ang mga haligi ng gusali, baka gumuho",
        "Natumba ang malaking puno sa bahay {loc}",
        # Taglish
        "Nag-collapse ang wall {loc}, may na-trap sa ilalim",
        "May crack ang bridge {loc}, delikado dumaan",
        "Bumagsak ang scaffolding sa construction site",
        "Blocked ang road dahil sa natumbang puno {loc}",
        "Sira ang pader ng building, baka gumuho",
        "Bumigay ang roof ng gym {loc}",
        "May sinkhole sa kalsada {loc}, lumulubog ang aspalto",
        "Natumbang poste nakaharang sa daan, hindi makadaan ang mga sasakyan",
    ],
}

# A second sentence. Some mention another hazard only to rule it out, so the
# model cannot lean on a single word.
DETAILS = {
    "flood": [
        "", "", "",
        "Malakas pa rin ang ulan.", "No electricity here.",
        "The water is still rising.", "Wala nang madaanan.",
        "May mga senior at bata na hindi makalabas.", "Walang sunog, baha lang.",
        "Wala namang nasaktan pero hindi kami makaalis.",
        "Our things are floating.", "Hindi na abot ng sasakyan.",
        "The current is strong.", "Brownout na rin dito.",
    ],
    "fire": [
        "", "", "",
        "Wala pang bumbero.", "Strong wind is spreading it.",
        "People are trying to put it out with buckets.",
        "Dikit-dikit ang mga bahay dito.", "May mga naiwan pa sa loob.",
        "Hindi naman baha dito, sunog talaga.", "Wala pang nasaktan.",
        "The smoke is very thick.", "Light materials ang mga bahay.",
        "Kumakalat na sa katabing bahay.", "We can hear explosions.",
    ],
    "medical": [
        "", "", "",
        "He is about 60 years old.", "May diabetes siya.",
        "Nangingitim na ang labi niya.", "She is not responding.",
        "Walang sasakyan papunta sa ospital.", "Hindi dahil sa baha o sunog.",
        "Mahina na ang pulso.", "He lost a lot of blood.",
        "May high blood ang pasyente.", "Namumutla at pinagpapawisan.",
        "We don't know first aid.",
    ],
    "structural": [
        "", "", "",
        "May mga taong naipit.", "No one is hurt so far.",
        "The road is not passable.", "Hindi makadaan ang mga sasakyan.",
        "Baka bumagsak pa ang iba.", "Walang sunog at walang baha.",
        "Wala namang sugatan.", "It needs heavy equipment.",
        "Nakalaylay pa ang mga kable.", "Delikado sa mga dumadaan.",
        "People are afraid to go back inside.",
    ],
}


def typo(rng: random.Random, text: str) -> str:
    """Drops one letter from one longer word, as hurried typing does."""
    words = text.split(" ")
    long_ones = [i for i, w in enumerate(words) if len(w) >= 6 and w.isalpha()]
    if not long_ones:
        return text
    i = rng.choice(long_ones)
    cut = rng.randrange(1, len(words[i]) - 1)
    words[i] = words[i][:cut] + words[i][cut + 1 :]
    return " ".join(words)


def style(rng: random.Random, text: str) -> str:
    roll = rng.random()
    if roll < 0.25:
        text = text.lower()
    elif roll < 0.32:
        text = text.upper()
    if rng.random() < 0.3:
        text = text.replace(",", "").replace(".", "")
    if rng.random() < 0.15:
        text = typo(rng, text)
    return " ".join(text.split())


def make(rng: random.Random, label: str) -> str:
    core = rng.choice(CORES[label])
    core = core.replace("{depth_en}", rng.choice(DEPTHS_EN))
    core = core.replace("{depth_fil}", rng.choice(DEPTHS_FIL))
    place = rng.choice(PLACES) if rng.random() < 0.8 else ""
    if "{loc}" in core:
        core = core.replace("{loc}", place)
    elif place and rng.random() < 0.4:
        core = f"{core} {place}"
    core = " ".join(core.split()).rstrip(",")
    if not core.endswith((".", "!", "?")):
        core += "."
    parts = [rng.choice(OPENERS), core, rng.choice(DETAILS[label]), rng.choice(CLOSERS)]
    return style(rng, " ".join(p for p in parts if p))


def main() -> None:
    rng = random.Random(SEED)
    rows: list[tuple[str, str]] = []
    for label in CORES:
        seen: set[str] = set()
        while len(seen) < PER_CLASS:
            seen.add(make(rng, label))
        rows += [(text, label) for text in sorted(seen)]
    rng.shuffle(rows)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["description", "label"])
        writer.writerows(rows)
    print(f"{len(rows)} sample descriptions -> {OUT}")


if __name__ == "__main__":
    main()
